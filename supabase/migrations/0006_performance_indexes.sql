-- =============================================================================
-- ReportWise — Migration 0006 — Performance indexes for dashboard & registry
-- Fixes slow Supabase fetches reported by user (takes a lot of time)
-- Adds missing indexes on high-cardinality FKs, optimizes RLS hot paths,
-- and speeds up inner joins used by dashboard/students/classes
-- =============================================================================

-- academic_years: primary filter is school_id + is_current
create index if not exists academic_years_school_idx on public.academic_years(school_id);
create index if not exists academic_years_school_current_idx on public.academic_years(school_id, is_current) where is_current = true;

-- terms / sequences
create index if not exists terms_year_idx on public.terms(academic_year_id);
create index if not exists terms_school_idx on public.terms(school_id);
create index if not exists sequences_term_idx on public.sequences(term_id);
create index if not exists sequences_school_idx on public.sequences(school_id);

-- classes: already has (school_id, academic_year_id) but add covering for dashboard
create index if not exists classes_school_year_active_idx on public.classes(school_id, academic_year_id, is_active);

-- students: school filter is main
create index if not exists students_school_fullname_idx on public.students(school_id, full_name);
create index if not exists students_matricule_idx on public.students(school_id, matricule) where matricule is not null;

-- student_enrollments: the hot join for dashboard & students list
create index if not exists enrollments_school_year_idx on public.student_enrollments(school_id, academic_year_id);
create index if not exists enrollments_student_year_idx on public.student_enrollments(student_id, academic_year_id);
create index if not exists enrollments_class_idx2 on public.student_enrollments(class_id, academic_year_id);
create index if not exists enrollments_school_year_class_idx on public.student_enrollments(school_id, academic_year_id, class_id);

-- teacher_assignments
create index if not exists teacher_assignments_school_year_idx on public.teacher_assignments(school_id, academic_year_id);
create index if not exists teacher_assignments_class_idx2 on public.teacher_assignments(class_id);
create index if not exists teacher_assignments_subject_idx on public.teacher_assignments(subject_id);

-- subjects: school_id null = national, else school-owned
create index if not exists subjects_school_code_idx on public.subjects(school_id, code);

-- curriculum & coeffs: already has resolve idx, add school filter
create index if not exists curriculum_school_level_idx on public.curriculum(school_id, level_id);
create index if not exists curriculum_subjects_curriculum_idx on public.curriculum_subjects(curriculum_id);

-- RLS helper: ensure school_memberships lookups are fast (already has profile/school idx, add composite)
create index if not exists school_memberships_profile_school_active_idx on public.school_memberships(profile_id, school_id, is_active) where is_active = true;
create index if not exists school_memberships_school_role_idx on public.school_memberships(school_id, role) where is_active = true;

-- Analyze to refresh stats
analyze public.academic_years;
analyze public.terms;
analyze public.sequences;
analyze public.classes;
analyze public.students;
analyze public.student_enrollments;
analyze public.teacher_assignments;
analyze public.subjects;
