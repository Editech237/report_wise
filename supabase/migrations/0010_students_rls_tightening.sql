-- =============================================================================
-- ReportWise — Migration 0010
-- Tighten student/enrollment writes to administrators (spec section 46).
--
-- Previously any school member could INSERT/UPDATE students and enrollments.
-- Creating, editing and moving students changes a school's academic records and
-- must be an administrator action. Teachers keep read access (they need class
-- rosters for mark entry) and administrators keep full write access.
-- =============================================================================

-- students: writes admin-only.
drop policy if exists "students_insert" on public.students;
create policy "students_insert_admin" on public.students
  for insert with check (public.is_school_admin(school_id));

drop policy if exists "students_update" on public.students;
create policy "students_update_admin" on public.students
  for update using (public.is_school_admin(school_id));

drop policy if exists "students_delete" on public.students;
create policy "students_delete_admin" on public.students
  for delete using (public.is_school_admin(school_id));

-- student_enrollments: writes admin-only.
drop policy if exists "enrollments_insert" on public.student_enrollments;
create policy "enrollments_insert_admin" on public.student_enrollments
  for insert with check (public.is_school_admin(school_id));

drop policy if exists "enrollments_update" on public.student_enrollments;
create policy "enrollments_update_admin" on public.student_enrollments
  for update using (public.is_school_admin(school_id));

drop policy if exists "enrollments_delete" on public.student_enrollments;
create policy "enrollments_delete_admin" on public.student_enrollments
  for delete using (public.is_school_admin(school_id));