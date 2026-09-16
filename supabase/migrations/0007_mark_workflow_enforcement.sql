-- =============================================================================
-- ReportWise — Migration 0007
-- DB-level mark workflow enforcement (spec section 27).
--
-- Previously the DRAFT → SUBMITTED → REVIEWED → APPROVED → LOCKED workflow was
-- only an application convention: a teacher (or anyone with the right RLS) could
-- edit a LOCKED mark book through the API. This migration makes the workflow a
-- database invariant:
--
--   * Teachers may only create books (DRAFT) and move their own DRAFT → SUBMITTED.
--   * Administrators perform SUBMITTED → REVIEWED → APPROVED → LOCKED.
--   * A LOCKED book is immutable except by an administrator unlock, which is
--     audited with a required reason via the unlock_mark_book RPC.
--   * Mark entries are editable only while the parent book is not LOCKED, and
--     only by the assigned teacher while it is DRAFT or by an administrator.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helper: can this caller edit entries of a mark book?
--   * any school admin (unless the book is LOCKED), or
--   * the assigned teacher while the book is still DRAFT.
-- -----------------------------------------------------------------------------
create or replace function public.can_edit_mark_book(p_book uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.mark_books mb
    where mb.id = p_book
      and mb.status <> 'LOCKED'
      and (
        public.is_school_admin(mb.school_id)
        or (
          mb.status = 'DRAFT'
          and exists (
            select 1 from public.teacher_assignments ta
            where ta.id = mb.teacher_assignment_id
              and ta.teacher_membership_id in (
                select id from public.school_memberships
                where profile_id = auth.uid() and is_active
              )
          )
        )
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- Trigger: enforce legal status transitions and block edits to LOCKED books.
-- Also records every transition (SUBMITTED/REVIEWED/APPROVED/LOCKED/UNLOCKED)
-- into mark_book_events so the audit trail is complete by construction.
-- Unlock reason is carried via set_config('reportwise.unlock_reason', ...)
-- set by the unlock_mark_book RPC.
-- -----------------------------------------------------------------------------
create or replace function public.enforce_mark_book_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin    boolean := public.is_school_admin(new.school_id);
  v_is_teacher  boolean := public.is_teacher_of_book(new.id);
  v_reason      text;
begin
  -- A LOCKED book is immutable unless an administrator unlocks it.
  if old.status = 'LOCKED' then
    if new.status = old.status then
      raise exception 'LOCKED mark books are immutable; unlock them first';
    end if;
    if not v_is_admin then
      raise exception 'Only an administrator may unlock a LOCKED mark book';
    end if;
    -- It is an unlock. Legal destinations: DRAFT, SUBMITTED, REVIEWED or APPROVED.
    if new.status not in ('DRAFT','SUBMITTED','REVIEWED','APPROVED') then
      raise exception 'Illegal unlock destination %', new.status;
    end if;
    v_reason := nullif(current_setting('reportwise.unlock_reason', true), '');
    insert into public.mark_book_events
      (school_id, mark_book_id, actor_profile_id, action, previous_status, new_status, reason)
    values
      (new.school_id, new.id, auth.uid(), 'UNLOCKED', old.status, new.status, v_reason);
    new.locked_at := null;
    return new;
  end if;

  -- Status unchanged: only the owner teacher (DRAFT) or an admin may touch it.
  if new.status = old.status then
    if not v_is_admin and not v_is_teacher then
      raise exception 'Only the assigned teacher or an administrator may edit this mark book';
    end if;
    return new;
  end if;

  -- Teacher: only DRAFT -> SUBMITTED.
  if v_is_teacher and not v_is_admin then
    if old.status = 'DRAFT' and new.status = 'SUBMITTED' then
      new.submitted_at := now();
      insert into public.mark_book_events
        (school_id, mark_book_id, actor_profile_id, action, previous_status, new_status)
      values
        (new.school_id, new.id, auth.uid(), 'SUBMITTED', old.status, new.status);
      return new;
    end if;
    raise exception 'Teachers may only move a mark book from DRAFT to SUBMITTED (attempted % -> %)',
      old.status, new.status;
  end if;

  -- Administrator: legal forward transitions only.
  if not (
      (old.status = 'DRAFT'    and new.status in ('SUBMITTED','REVIEWED','APPROVED','LOCKED'))
   or (old.status = 'SUBMITTED' and new.status in ('REVIEWED','APPROVED','LOCKED'))
   or (old.status = 'REVIEWED'  and new.status in ('APPROVED','LOCKED'))
   or (old.status = 'APPROVED'  and new.status = 'LOCKED')
  ) then
    raise exception 'Illegal mark book status transition % -> %', old.status, new.status;
  end if;

  if new.status = 'SUBMITTED' then new.submitted_at := now(); end if;
  if new.status = 'REVIEWED'  then new.reviewed_at  := now(); end if;
  if new.status = 'APPROVED'  then new.approved_at  := now(); end if;
  if new.status = 'LOCKED'    then new.locked_at    := now(); end if;

  insert into public.mark_book_events
    (school_id, mark_book_id, actor_profile_id, action, previous_status, new_status)
  values
    (new.school_id, new.id, auth.uid(), new.status, old.status, new.status);

  return new;
end;
$$;

drop trigger if exists mark_books_workflow on public.mark_books;
create trigger mark_books_workflow
  before update on public.mark_books
  for each row execute function public.enforce_mark_book_transition();

-- -----------------------------------------------------------------------------
-- RPC: unlock a LOCKED mark book with an audited, mandatory reason.
-- -----------------------------------------------------------------------------
create or replace function public.unlock_mark_book(
  p_book uuid,
  p_reason text,
  p_new_status text default 'REVIEWED'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'An unlock reason is required';
  end if;

  select school_id into v_school from public.mark_books where id = p_book;
  if v_school is null then
    raise exception 'Mark book not found';
  end if;
  if not public.is_school_admin(v_school) then
    raise exception 'Only an administrator may unlock a mark book';
  end if;

  perform set_config('reportwise.unlock_reason', trim(p_reason), true);
  update public.mark_books set status = p_new_status where id = p_book;
end;
$$;

-- -----------------------------------------------------------------------------
-- RLS: route mark-entry writes through can_edit_mark_book so LOCKED books are
-- protected at the policy level too (defense in depth alongside the trigger).
-- -----------------------------------------------------------------------------
drop policy if exists "mark_entries_insert" on public.mark_entries;
create policy "mark_entries_insert" on public.mark_entries
  for insert with check (
    public.is_school_member(school_id)
    and public.can_edit_mark_book(mark_book_id)
  );

drop policy if exists "mark_entries_update" on public.mark_entries;
create policy "mark_entries_update" on public.mark_entries
  for update using (public.can_edit_mark_book(mark_book_id));

drop policy if exists "mark_entries_delete" on public.mark_entries;
create policy "mark_entries_delete" on public.mark_entries
  for delete using (public.can_edit_mark_book(mark_book_id));

-- mark_books updates: keep policy permissive (admin or assigned teacher) — the
-- trigger is the source of truth for legal transitions on this table.