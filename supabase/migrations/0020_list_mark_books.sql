-- =============================================================================
-- ReportWise — Migration 0020
-- Persistent mark-book history for the Mark entry screen.
--
-- list_mark_books returns the saved mark books of a school + year enriched for
-- the UI (class, subject, sequence, status, teacher, progress). A teacher sees
-- only the books of their own assignments; an administrator sees all books.
-- =============================================================================

create or replace function public.list_mark_books(p_school uuid, p_year uuid)
returns table (
  id                   uuid,
  teacher_assignment_id uuid,
  teacher_name         text,
  class_id             uuid,
  class_name           text,
  subject_id           uuid,
  subject_name         text,
  sequence_id          uuid,
  sequence_name        text,
  sequence_status      text,
  status               text,
  entered_count        bigint,
  student_count        bigint,
  created_at           timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select mb.id,
         mb.teacher_assignment_id,
         p.full_name,
         mb.class_id,
         c.name,
         mb.subject_id,
         s.name,
         mb.sequence_id,
         seq.name,
         seq.status,
         mb.status,
         (
           select count(*) from public.mark_entries me
           where me.mark_book_id = mb.id
             and me.absence_status is distinct from 'NOT_ENTERED'
         ),
         (
           select count(*) from public.student_enrollments se
           where se.class_id = mb.class_id
             and se.academic_year_id = mb.academic_year_id
         ),
         mb.created_at
  from public.mark_books mb
  join public.teacher_assignments ta on ta.id = mb.teacher_assignment_id
  join public.school_memberships sm on sm.id = ta.teacher_membership_id
  left join public.profiles p on p.id = sm.profile_id
  join public.classes c on c.id = mb.class_id
  join public.subjects s on s.id = mb.subject_id
  join public.sequences seq on seq.id = mb.sequence_id
  where mb.school_id = p_school
    and mb.academic_year_id = p_year
    and (
      public.is_school_admin(p_school)
      or ta.teacher_membership_id in (
        select id from public.school_memberships
        where profile_id = auth.uid() and is_active
      )
    )
  order by mb.created_at desc;
$$;