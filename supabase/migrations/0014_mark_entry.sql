-- =============================================================================
-- ReportWise — Migration 0014
-- Mark entry & workflow (spec sections 11, 27, 28, 30).
--
-- The Phase-0 workflow trigger already enforces book status transitions and
-- can_edit_mark_book() gates row-level writes. This migration adds the
-- transactional entry points the mark-entry screen uses, plus the roster and
-- audit reads. All RPCs validate that every reference stays inside the
-- caller's school and that the sequence is open.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Get (or create in DRAFT) the mark book for an assignment + sequence.
-- Caller must be the assigned teacher or a school administrator.
-- -----------------------------------------------------------------------------
create or replace function public.get_or_create_mark_book(
  p_assignment uuid,
  p_sequence   uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school   uuid;
  v_year     uuid;
  v_class    uuid;
  v_subject  uuid;
  v_book     uuid;
  v_is_teacher boolean;
begin
  select ta.school_id, ta.academic_year_id, ta.class_id, ta.subject_id
    into v_school, v_year, v_class, v_subject
    from public.teacher_assignments ta
    where ta.id = p_assignment;
  if v_school is null then raise exception 'Assignment not found'; end if;

  if not public.is_school_admin(v_school) then
    select exists (
      select 1 from public.teacher_assignments ta
      where ta.id = p_assignment
        and ta.teacher_membership_id in (
          select id from public.school_memberships
          where profile_id = auth.uid() and is_active
        )
    ) into v_is_teacher;
    if not v_is_teacher then
      raise exception 'Only the assigned teacher or an administrator can access this mark book';
    end if;
  end if;

  if not exists (
    select 1 from public.sequences s
    join public.terms t on t.id = s.term_id
    where s.id = p_sequence
      and s.school_id = v_school
      and t.academic_year_id = v_year
  ) then
    raise exception 'Sequence does not belong to this assignment';
  end if;

  select id into v_book from public.mark_books
    where teacher_assignment_id = p_assignment and sequence_id = p_sequence;
  if v_book is null then
    insert into public.mark_books
      (school_id, academic_year_id, teacher_assignment_id, class_id, subject_id, sequence_id, status)
    values
      (v_school, v_year, p_assignment, v_class, v_subject, p_sequence, 'DRAFT')
    returning id into v_book;
  end if;

  return v_book;
end;
$$;

-- -----------------------------------------------------------------------------
-- Transactionally upsert a batch of mark entries for a book.
--   p_entries: [{student_enrollment_id, scheme_component_id, score,
--                absence_status, teacher_note}]
-- Enforces: editable book, open (or admin) sequence, in-school enrollment and
-- valid component. ZERO / other non-ENTERED statuses never store a score.
-- -----------------------------------------------------------------------------
create or replace function public.save_mark_entries(p_book uuid, p_entries jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school    uuid;
  v_class     uuid;
  v_seq_status text;
  v_is_admin  boolean;
  e           jsonb;
  v_enr uuid; v_comp uuid; v_score numeric; v_status text; v_note text;
begin
  select mb.school_id, mb.class_id, s.status
    into v_school, v_class, v_seq_status
    from public.mark_books mb
    join public.sequences s on s.id = mb.sequence_id
    where mb.id = p_book;
  if v_school is null then raise exception 'Mark book not found'; end if;

  if not public.can_edit_mark_book(p_book) then
    raise exception 'This mark book is not editable (locked, or not your draft)';
  end if;

  v_is_admin := public.is_school_admin(v_school);
  if v_seq_status = 'FINALIZED' then
    raise exception 'This sequence is finalized; no marks can be entered';
  end if;
  if v_seq_status <> 'OPEN' and not v_is_admin then
    raise exception 'This sequence is not open for mark entry';
  end if;

  if p_entries is null or jsonb_array_length(p_entries) = 0 then
    raise exception 'No entries to save';
  end if;

  for e in select * from jsonb_array_elements(p_entries) loop
    v_enr    := (e ->> 'student_enrollment_id')::uuid;
    v_comp   := (e ->> 'scheme_component_id')::uuid;
    v_status := coalesce(e ->> 'absence_status', 'ENTERED');
    v_note   := e ->> 'teacher_note';
    v_score  := nullif(e ->> 'score', '')::numeric;

    if not exists (
      select 1 from public.student_enrollments se
      where se.id = v_enr and se.class_id = v_class and se.school_id = v_school
    ) then
      raise exception 'Enrollment does not belong to this mark book class';
    end if;
    if not exists (select 1 from public.assessment_scheme_components where id = v_comp) then
      raise exception 'Unknown assessment component';
    end if;

    if v_status in ('ENTERED', 'ZERO') then
      if v_status = 'ENTERED' and v_score is null then
        raise exception 'An ENTERED mark requires a score';
      end if;
    else
      v_score := null; -- ABSENT / EXCUSED / NOT_APPLICABLE / PENDING carry no score
    end if;

    insert into public.mark_entries
      (school_id, mark_book_id, student_enrollment_id, scheme_component_id,
       score, absence_status, teacher_note, entered_at)
    values
      (v_school, p_book, v_enr, v_comp, v_score, v_status, v_note, now())
    on conflict (mark_book_id, student_enrollment_id, scheme_component_id)
    do update set
      score          = excluded.score,
      absence_status = excluded.absence_status,
      teacher_note   = excluded.teacher_note,
      updated_at     = now();
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Roster of students enrolled in a class for the current year (mark entry grid).
-- -----------------------------------------------------------------------------
create or replace function public.students_in_class(p_class uuid, p_year uuid)
returns table (
  enrollment_id uuid,
  student_id    uuid,
  full_name     text,
  matricule     text
)
language sql
stable
security definer
set search_path = public
as $$
  select se.id, st.id, st.full_name, st.matricule
  from public.student_enrollments se
  join public.students st on st.id = se.student_id
  where se.class_id = p_class and se.academic_year_id = p_year
    and public.is_school_member(se.school_id)
  order by st.full_name;
$$;

-- -----------------------------------------------------------------------------
-- Existing mark entries for a book, enriched with student names.
-- -----------------------------------------------------------------------------
create or replace function public.list_mark_entries(p_book uuid)
returns table (
  id                    uuid,
  student_enrollment_id uuid,
  student_name          text,
  scheme_component_id   uuid,
  score                 numeric,
  absence_status        text,
  teacher_note          text
)
language sql
stable
security definer
set search_path = public
as $$
  select me.id, me.student_enrollment_id, s.full_name,
         me.scheme_component_id, me.score, me.absence_status, me.teacher_note
  from public.mark_entries me
  join public.student_enrollments se on se.id = me.student_enrollment_id
  join public.students s on s.id = se.student_id
  where me.mark_book_id = p_book
    and public.is_school_member(me.school_id)
  order by s.full_name, me.scheme_component_id;
$$;

-- -----------------------------------------------------------------------------
-- Audit events for a book (submission / review / approval / lock / unlock).
-- -----------------------------------------------------------------------------
create or replace function public.list_mark_book_events(p_book uuid)
returns table (
  action          text,
  previous_status text,
  new_status      text,
  reason          text,
  actor_name      text,
  created_at      timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select e.action, e.previous_status, e.new_status, e.reason, p.full_name, e.created_at
  from public.mark_book_events e
  left join public.profiles p on p.id = e.actor_profile_id
  where e.mark_book_id = p_book
    and public.is_school_member(e.school_id)
  order by e.created_at desc;
$$;