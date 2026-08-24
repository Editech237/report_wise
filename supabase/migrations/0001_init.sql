-- =============================================================================
-- ReportWise — Cameroon Secondary School Management Platform
-- Migration 0001: Foundation schema, multi-tenant RLS, Cameroon defaults
--
-- Design principles (per master spec):
--   * CAMEROON-FIRST: coefficient-weighted academic model is the default.
--   * Multi-tenant: every tenant row carries school_id; RLS enforces isolation.
--   * Configurable academic hierarchy (never hardcoded in app code).
--   * NATIONAL_DEFAULT / SCHOOL_CONFIGURATION / ACADEMIC_YEAR layers.
--   * Academic-year versioning: historical configs are never overwritten.
-- =============================================================================

-- =============================================================================
-- EXTENSIONS
-- =============================================================================
create extension if not exists "pgcrypto";

-- =============================================================================
-- TENANT: SCHOOLS
-- =============================================================================
create table public.schools (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  code             text unique,
  school_type      text not null check (school_type in ('GENERAL','TECHNICAL','BOTH')),
  subsystem        text not null check (subsystem in ('FRANCOPHONE','ANGLOPHONE','BILINGUAL')),
  logo_url         text,
  address          text,
  phone            text,
  email            text,
  region           text,
  division         text,
  sub_division     text,
  ministry_code    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- =============================================================================
-- PROFILES + MEMBERSHIPS (multi-tenancy / RBAC)
-- =============================================================================
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text not null,
  phone      text,
  email      text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.school_memberships (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role       text not null check (role in ('SUPER_ADMIN','ADMIN','PRINCIPAL','TEACHER','ACCOUNTANT','PARENT')),
  staff_id   text,
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, profile_id)
);

create index if not exists school_memberships_profile_idx on public.school_memberships(profile_id);
create index if not exists school_memberships_school_idx  on public.school_memberships(school_id);

-- =============================================================================
-- RLS HELPER FUNCTIONS (security definer to avoid recursion)
-- =============================================================================
create or replace function public.current_user_schools()
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select sm.school_id
  from public.school_memberships sm
  where sm.profile_id = auth.uid()
    and sm.is_active;
$$;

create or replace function public.current_user_roles_for_school(p_school uuid)
returns setof text
language sql
stable
security definer
set search_path = public
as $$
  select sm.role
  from public.school_memberships sm
  where sm.profile_id = auth.uid()
    and sm.school_id = p_school
    and sm.is_active;
$$;

create or replace function public.is_school_member(p_school uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.school_memberships sm
    where sm.profile_id = auth.uid()
      and sm.school_id = p_school
      and sm.is_active
  );
$$;

create or replace function public.is_school_admin(p_school uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.school_memberships sm
    where sm.profile_id = auth.uid()
      and sm.school_id = p_school
      and sm.is_active
      and sm.role in ('SUPER_ADMIN','ADMIN','PRINCIPAL')
  );
$$;

create or replace function public.is_school_teacher(p_school uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.school_memberships sm
    where sm.profile_id = auth.uid()
      and sm.school_id = p_school
      and sm.is_active
      and sm.role = 'TEACHER'
  );
$$;

-- =============================================================================
-- ACADEMIC HIERARCHY LOOKUPS (nullable school_id = national default layer)
-- =============================================================================
create table public.education_types (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,           -- GENERAL | TECHNICAL
  name       text not null,
  name_fr    text,
  sort_order int not null default 0
);

create table public.subsystems (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,           -- FRANCOPHONE | ANGLOPHONE
  name       text not null
);

create table public.cycles (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,  -- null = default
  education_type_id  uuid not null references public.education_types(id),
  subsystem          text check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  code               text not null,          -- FIRST_CYCLE | SECOND_CYCLE
  name               text not null,
  name_fr            text,
  sort_order         int not null default 0,
  unique (school_id, education_type_id, subsystem, code)
);

create table public.levels (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,
  cycle_id           uuid not null references public.cycles(id),
  subsystem          text check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  code               text not null,          -- 3EME | 2NDE | FORM_3 ...
  name               text not null,          -- 3ème | Form 3 ...
  name_fr            text,
  sort_order         int not null default 0,
  unique (school_id, cycle_id, subsystem, code)
);

create table public.series (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,
  education_type_id  uuid not null references public.education_types(id),
  subsystem          text check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  code               text not null,          -- A | C | D | TI | BIL | STT | IND ...
  name               text not null,
  name_fr            text,
  sort_order         int not null default 0,
  unique (school_id, education_type_id, subsystem, code)
);

create table public.specialties (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid references public.schools(id) on delete cascade,
  series_id  uuid references public.series(id),
  code       text not null,                  -- GCA | SESC | ELECTRO ...
  name       text not null,
  name_fr    text,
  sort_order int not null default 0,
  unique (school_id, series_id, code)
);

-- =============================================================================
-- ACADEMIC YEAR / TERMS / SEQUENCES
-- =============================================================================
create table public.academic_years (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  name       text not null,                  -- 2025/2026
  starts_on  date,
  ends_on    date,
  is_current boolean not null default false,
  status     text not null default 'PLANNED' check (status in ('PLANNED','ACTIVE','CLOSED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (school_id, name)
);

create table public.terms (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null references public.schools(id) on delete cascade,
  academic_year_id uuid not null references public.academic_years(id) on delete cascade,
  number          int not null,
  name            text not null,             -- Term 1 | 1er Trimestre
  name_fr         text,
  starts_on       date,
  ends_on         date,
  unique (academic_year_id, number)
);

create table public.sequences (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools(id) on delete cascade,
  term_id    uuid not null references public.terms(id) on delete cascade,
  number     int not null,
  name       text not null,                  -- Sequence 1 | Séquence 1
  name_fr    text,
  starts_on  date,
  ends_on    date,
  status     text not null default 'OPEN' check (status in ('OPEN','CLOSED','FINALIZED')),
  unique (term_id, number)
);

-- =============================================================================
-- CLASSES (the concrete academic unit)
-- =============================================================================
create table public.classes (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools(id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years(id) on delete cascade,
  subsystem         text not null check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  education_type_id uuid not null references public.education_types(id),
  cycle_id          uuid not null references public.cycles(id),
  level_id          uuid not null references public.levels(id),
  series_id         uuid references public.series(id),
  specialty_id      uuid references public.specialties(id),
  name              text not null,           -- 3ème A | Form 3A | 2nde C
  room              text,
  class_teacher_id  uuid references public.school_memberships(id),
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists classes_school_year_idx on public.classes(school_id, academic_year_id);
create index if not exists classes_level_idx on public.classes(level_id, series_id, specialty_id);

-- =============================================================================
-- SUBJECTS (global catalog; school_id null = national catalog subject)
-- =============================================================================
create table public.subjects (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid references public.schools(id) on delete cascade,  -- null = national subject
  code         text not null,              -- MATHS | PHY | FR | ENG ...
  name         text not null,
  name_fr      text,
  subject_type text check (subject_type in
    ('GENERAL','TECHNICAL','PROFESSIONAL','PRACTICAL','THEORY','LANGUAGE','SPORT','OTHER')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (school_id, code)
);

-- =============================================================================
-- CURRICULUM LAYER (which subjects apply to a level/series + workload)
-- Scope columns nullable; most-specific match wins at resolution time.
-- =============================================================================
create table public.curriculum (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,
  academic_year_id   uuid references public.academic_years(id) on delete cascade,
  education_type_id  uuid references public.education_types(id),
  subsystem          text check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  cycle_id           uuid references public.cycles(id),
  level_id           uuid references public.levels(id),
  series_id          uuid references public.series(id),
  specialty_id       uuid references public.specialties(id),
  source             text not null check (source in ('NATIONAL_DEFAULT','SCHOOL_CONFIGURATION','ACADEMIC_YEAR')),
  source_ref         text,                  -- official MINESEC document reference
  name               text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table public.curriculum_subjects (
  id                 uuid primary key default gen_random_uuid(),
  curriculum_id      uuid not null references public.curriculum(id) on delete cascade,
  school_id          uuid references public.schools(id) on delete cascade,  -- denormalized for RLS
  subject_id         uuid not null references public.subjects(id),
  coefficient        numeric(5,2) not null check (coefficient > 0),
  weekly_hours       numeric(5,2),
  subject_type       text check (subject_type in
    ('GENERAL','TECHNICAL','PROFESSIONAL','PRACTICAL','THEORY','LANGUAGE','SPORT','OTHER')),
  counts_in_average  boolean not null default true,
  counts_in_ranking  boolean not null default true,
  shows_on_report    boolean not null default true,
  sort_order         int not null default 0,
  unique (curriculum_id, subject_id)
);

-- =============================================================================
-- SUBJECT COEFFICIENT CONFIGURATION (versioned by academic year)
-- The most specific applicable row wins at resolution time.
-- =============================================================================
create table public.subject_coefficient_configurations (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,  -- null = national layer
  academic_year_id   uuid references public.academic_years(id) on delete cascade,
  subsystem          text check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  education_type_id  uuid references public.education_types(id),
  cycle_id           uuid references public.cycles(id),
  level_id           uuid references public.levels(id),
  series_id          uuid references public.series(id),
  specialty_id       uuid references public.specialties(id),
  subject_id         uuid not null references public.subjects(id),
  coefficient        numeric(5,2) not null check (coefficient > 0),
  source             text not null check (source in ('NATIONAL_DEFAULT','SCHOOL_CONFIGURATION','ACADEMIC_YEAR')),
  source_ref         text,
  created_by         uuid references public.profiles(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists coef_cfg_resolve_idx on public.subject_coefficient_configurations
  (school_id, academic_year_id, education_type_id, level_id, series_id, specialty_id, subject_id);

-- =============================================================================
-- ASSESSMENT SCHEMES (weights per component) — distinct from coefficients
-- =============================================================================
create table public.assessment_schemes (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,  -- null = default layer
  academic_year_id   uuid references public.academic_years(id) on delete cascade,
  education_type_id  uuid references public.education_types(id),
  level_id           uuid references public.levels(id),
  series_id          uuid references public.series(id),
  name               text not null,
  source             text not null check (source in ('NATIONAL_DEFAULT','SCHOOL_CONFIGURATION')),
  is_default         boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table public.assessment_scheme_components (
  id             uuid primary key default gen_random_uuid(),
  scheme_id      uuid not null references public.assessment_schemes(id) on delete cascade,
  school_id      uuid references public.schools(id) on delete cascade,  -- denormalized for RLS
  name           text not null,             -- Composition | Devoir | Interrogation
  name_fr        text,
  component_type text check (component_type in
    ('CLASS_TEST','ASSIGNMENT','QUIZ','EXAM','PRACTICAL','CONTINUOUS_ASSESSMENT','PROJECT','ORAL')),
  weight         numeric(5,2) not null check (weight > 0),
  max_score      numeric(5,2) not null default 20 check (max_score > 0),
  sort_order     int not null default 0
);

-- =============================================================================
-- ACADEMIC RULES ENGINE (centralized, keyed, versionable)
-- =============================================================================
create table public.academic_rules (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid references public.schools(id) on delete cascade,
  academic_year_id uuid references public.academic_years(id) on delete cascade,
  rule_key         text not null,
  rule_value       jsonb not null,
  source           text not null check (source in ('NATIONAL_DEFAULT','SCHOOL_CONFIGURATION')),
  description      text,
  updated_at       timestamptz not null default now(),
  unique (school_id, academic_year_id, rule_key)
);

-- =============================================================================
-- STUDENTS + ENROLLMENTS
-- =============================================================================
create table public.students (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools(id) on delete cascade,
  profile_id        uuid references public.profiles(id),
  matricule         text,                    -- national student identifier
  full_name         text not null,
  date_of_birth     date,
  gender            text check (gender in ('M','F')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists students_school_idx on public.students(school_id);

create table public.student_enrollments (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools(id) on delete cascade,
  student_id        uuid not null references public.students(id) on delete cascade,
  academic_year_id  uuid not null references public.academic_years(id) on delete cascade,
  class_id          uuid not null references public.classes(id) on delete cascade,
  series_id         uuid references public.series(id),
  specialty_id      uuid references public.specialties(id),
  status            text not null default 'ENROLLED'
                    check (status in ('ENROLLED','TRANSFERRED','EXPELLED','GRADUATED','LEFT')),
  enrolled_on       date,
  left_on           date,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (student_id, academic_year_id)
);

create index if not exists enrollments_class_idx on public.student_enrollments(class_id, academic_year_id);

-- =============================================================================
-- TEACHER ASSIGNMENTS (one teacher <-> class <-> subject per year)
-- =============================================================================
create table public.teacher_assignments (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid not null references public.schools(id) on delete cascade,
  academic_year_id      uuid not null references public.academic_years(id) on delete cascade,
  teacher_membership_id uuid not null references public.school_memberships(id) on delete cascade,
  class_id              uuid not null references public.classes(id) on delete cascade,
  subject_id            uuid not null references public.subjects(id),
  specialty_id          uuid references public.specialties(id),
  teaching_role         text not null default 'SUBJECT_TEACHER'
                        check (teaching_role in ('SUBJECT_TEACHER','CLASS_TEACHER')),
  created_at            timestamptz not null default now(),
  unique (academic_year_id, class_id, subject_id, teacher_membership_id)
);

create index if not exists teacher_assignments_teacher_idx on public.teacher_assignments(teacher_membership_id);

-- =============================================================================
-- MARK BOOKS + ENTRIES (workflow: DRAFT→SUBMITTED→REVIEWED→APPROVED→LOCKED)
-- =============================================================================
create table public.mark_books (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid not null references public.schools(id) on delete cascade,
  academic_year_id      uuid not null references public.academic_years(id) on delete cascade,
  teacher_assignment_id uuid not null references public.teacher_assignments(id) on delete cascade,
  class_id              uuid not null references public.classes(id) on delete cascade,
  subject_id            uuid not null references public.subjects(id),
  sequence_id           uuid not null references public.sequences(id) on delete cascade,
  status                text not null default 'DRAFT'
                        check (status in ('DRAFT','SUBMITTED','REVIEWED','APPROVED','LOCKED')),
  submitted_at          timestamptz,
  reviewed_at           timestamptz,
  approved_at           timestamptz,
  locked_at             timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (teacher_assignment_id, sequence_id)
);

create table public.mark_entries (
  id                     uuid primary key default gen_random_uuid(),
  school_id              uuid not null references public.schools(id) on delete cascade,
  mark_book_id           uuid not null references public.mark_books(id) on delete cascade,
  student_enrollment_id  uuid not null references public.student_enrollments(id) on delete cascade,
  scheme_component_id    uuid not null references public.assessment_scheme_components(id),
  score                  numeric(7,2),       -- on the component's max_score scale
  absence_status         text not null default 'ENTERED'
                         check (absence_status in
                           ('NOT_ENTERED','ABSENT','EXCUSED','ZERO','NOT_APPLICABLE','PENDING','ENTERED')),
  teacher_note           text,
  entered_at             timestamptz,
  updated_at             timestamptz not null default now(),
  unique (mark_book_id, student_enrollment_id, scheme_component_id)
);

create index if not exists mark_entries_book_idx on public.mark_entries(mark_book_id);

-- Audit trail (every status change, especially UNLOCKED, must be recorded)
create table public.mark_book_events (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools(id) on delete cascade,
  mark_book_id       uuid not null references public.mark_books(id) on delete cascade,
  actor_profile_id   uuid not null references public.profiles(id),
  action             text not null check (action in
    ('CREATED','SUBMITTED','REVIEWED','APPROVED','LOCKED','UNLOCKED','EDITED')),
  previous_status    text,
  new_status         text,
  reason             text,
  created_at         timestamptz not null default now()
);

-- =============================================================================
-- RESULTS (immutable snapshots for historical integrity)
-- =============================================================================
create table public.period_results (
  id                      uuid primary key default gen_random_uuid(),
  school_id               uuid not null references public.schools(id) on delete cascade,
  academic_year_id        uuid not null references public.academic_years(id) on delete cascade,
  class_id                uuid not null references public.classes(id) on delete cascade,
  student_enrollment_id   uuid not null references public.student_enrollments(id) on delete cascade,
  period_type             text not null check (period_type in ('SEQUENCE','TERM','ANNUAL')),
  period_id               uuid,              -- sequence.id or term.id
  general_average         numeric(8,2),
  total_weighted_points   numeric(12,2),
  total_coefficients      numeric(8,2),
  class_average           numeric(8,2),
  rank                    int,
  tie_break_info          jsonb,
  config_snapshot         jsonb not null,    -- coefficients + rules used, for reproducibility
  status                  text not null default 'DRAFT' check (status in ('DRAFT','FINAL')),
  calculated_at           timestamptz not null default now(),
  unique (school_id, class_id, student_enrollment_id, period_type, period_id)
);

create table public.subject_results (
  id                uuid primary key default gen_random_uuid(),
  school_id         uuid not null references public.schools(id) on delete cascade,
  period_result_id  uuid not null references public.period_results(id) on delete cascade,
  subject_id        uuid not null references public.subjects(id),
  subject_average   numeric(8,2),
  coefficient       numeric(5,2),
  weighted_points   numeric(10,2),
  marks_count       int,
  rank_in_subject   int,
  unique (period_result_id, subject_id)
);

create index if not exists period_results_class_idx on public.period_results(class_id, period_type, period_id);

-- =============================================================================
-- REPORT TEMPLATES + GENERATED REPORT CARDS
-- =============================================================================
create table public.report_templates (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid references public.schools(id) on delete cascade,  -- null = national templates
  name               text not null,
  subsystem          text check (subsystem in ('FRANCOPHONE','ANGLOPHONE')),
  education_type_id  uuid references public.education_types(id),
  kind               text not null default 'SEQUENCE' check (kind in ('SEQUENCE','TERM','ANNUAL')),
  is_default         boolean not null default false,
  template_html      text not null,
  config             jsonb not null default '{}',
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table public.report_cards (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools(id) on delete cascade,
  academic_year_id uuid not null references public.academic_years(id) on delete cascade,
  period_result_id uuid not null references public.period_results(id) on delete cascade,
  template_id      uuid references public.report_templates(id),
  file_url         text,                     -- PDF in Storage
  version          int not null default 1,
  generated_at     timestamptz not null default now()
);

-- =============================================================================
-- NOTIFICATIONS
-- =============================================================================
create table public.notifications (
  id                    uuid primary key default gen_random_uuid(),
  school_id             uuid not null references public.schools(id) on delete cascade,
  recipient_profile_id  uuid not null references public.profiles(id) on delete cascade,
  type                  text not null,       -- MARK_REMINDER | APPROVAL | SYSTEM ...
  title                 text not null,
  body                  text,
  data                  jsonb,
  read_at               timestamptz,
  created_at            timestamptz not null default now()
);

create index if not exists notifications_recipient_idx on public.notifications(recipient_profile_id, read_at);

-- =============================================================================
-- ROW LEVEL SECURITY — enable on all tenant tables
-- =============================================================================
alter table public.schools                                 enable row level security;
alter table public.profiles                                enable row level security;
alter table public.school_memberships                      enable row level security;
alter table public.education_types                         enable row level security;
alter table public.subsystems                              enable row level security;
alter table public.cycles                                  enable row level security;
alter table public.levels                                  enable row level security;
alter table public.series                                  enable row level security;
alter table public.specialties                             enable row level security;
alter table public.academic_years                          enable row level security;
alter table public.terms                                   enable row level security;
alter table public.sequences                               enable row level security;
alter table public.classes                                 enable row level security;
alter table public.subjects                                enable row level security;
alter table public.curriculum                              enable row level security;
alter table public.curriculum_subjects                     enable row level security;
alter table public.subject_coefficient_configurations      enable row level security;
alter table public.assessment_schemes                      enable row level security;
alter table public.assessment_scheme_components             enable row level security;
alter table public.academic_rules                          enable row level security;
alter table public.students                                enable row level security;
alter table public.student_enrollments                     enable row level security;
alter table public.teacher_assignments                     enable row level security;
alter table public.mark_books                              enable row level security;
alter table public.mark_entries                            enable row level security;
alter table public.mark_book_events                        enable row level security;
alter table public.period_results                          enable row level security;
alter table public.subject_results                         enable row level security;
alter table public.report_templates                        enable row level security;
alter table public.report_cards                            enable row level security;
alter table public.notifications                           enable row level security;

-- =============================================================================
-- RLS POLICIES
-- Helpers:
--   visible(school_id)      -> school_id is null (national layer) OR caller is a member
--   tenant_admin(school_id) -> visible AND caller is school admin
-- =============================================================================

-- --- schools ---
create policy "schools_select" on public.schools for select using (public.is_school_member(id));

-- --- profiles ---
create policy "profiles_insert_own" on public.profiles
  for insert with check (id = auth.uid());
create policy "profiles_select_own" on public.profiles
  for select using (id = auth.uid());
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- --- school_memberships ---
create policy "memberships_select_own" on public.school_memberships
  for select using (profile_id = auth.uid());

-- --- national/default tables (nullable school_id): visible to every authenticated user ---
-- generic helper: a row is "visible" if its school_id is null or caller is a member.
-- These policies are repeated per table because Postgres policies cannot be shared.

create policy "cycles_select" on public.cycles
  for select using (school_id is null or public.is_school_member(school_id));
create policy "levels_select" on public.levels
  for select using (school_id is null or public.is_school_member(school_id));
create policy "series_select" on public.series
  for select using (school_id is null or public.is_school_member(school_id));
create policy "specialties_select" on public.specialties
  for select using (school_id is null or public.is_school_member(school_id));
create policy "subjects_select" on public.subjects
  for select using (school_id is null or public.is_school_member(school_id));
create policy "subjects_insert" on public.subjects
  for insert with check (school_id is not null and public.is_school_admin(school_id));
create policy "subjects_update" on public.subjects
  for update using (school_id is not null and public.is_school_admin(school_id));
create policy "subjects_delete" on public.subjects
  for delete using (school_id is not null and public.is_school_admin(school_id));
create policy "curriculum_select" on public.curriculum
  for select using (school_id is null or public.is_school_member(school_id));
create policy "curriculum_subjects_select" on public.curriculum_subjects
  for select using (school_id is null or public.is_school_member(school_id));
create policy "coef_cfg_select" on public.subject_coefficient_configurations
  for select using (school_id is null or public.is_school_member(school_id));
create policy "schemes_select" on public.assessment_schemes
  for select using (school_id is null or public.is_school_member(school_id));
create policy "scheme_components_select" on public.assessment_scheme_components
  for select using (school_id is null or public.is_school_member(school_id));
create policy "rules_select" on public.academic_rules
  for select using (school_id is null or public.is_school_member(school_id));
create policy "templates_select" on public.report_templates
  for select using (school_id is null or public.is_school_member(school_id));

-- system lookups (education_types, subsystems): read-only for all authenticated users
create policy "education_types_select" on public.education_types for select using (true);
create policy "subsystems_select" on public.subsystems for select using (true);

-- --- school-owned tables: SELECT for members, WRITE for admins ---
create policy "academic_years_select" on public.academic_years for select using (public.is_school_member(school_id));
create policy "academic_years_insert" on public.academic_years for insert with check (public.is_school_admin(school_id));
create policy "academic_years_update" on public.academic_years for update using (public.is_school_admin(school_id));
create policy "academic_years_delete" on public.academic_years for delete using (public.is_school_admin(school_id));

create policy "terms_select" on public.terms for select using (public.is_school_member(school_id));
create policy "terms_insert" on public.terms for insert with check (public.is_school_admin(school_id));
create policy "terms_update" on public.terms for update using (public.is_school_admin(school_id));
create policy "terms_delete" on public.terms for delete using (public.is_school_admin(school_id));

create policy "sequences_select" on public.sequences for select using (public.is_school_member(school_id));
create policy "sequences_insert" on public.sequences for insert with check (public.is_school_admin(school_id));
create policy "sequences_update" on public.sequences for update using (public.is_school_admin(school_id));
create policy "sequences_delete" on public.sequences for delete using (public.is_school_admin(school_id));

create policy "classes_select" on public.classes for select using (public.is_school_member(school_id));
create policy "classes_insert" on public.classes for insert with check (public.is_school_admin(school_id));
create policy "classes_update" on public.classes for update using (public.is_school_admin(school_id));
create policy "classes_delete" on public.classes for delete using (public.is_school_admin(school_id));

-- curriculum & coef & schemes: admins manage their school's rows; national rows are read-only.
-- (National rows carry school_id = null, so admin policies below never match them.)
create policy "curriculum_insert" on public.curriculum
  for insert with check (school_id is not null and public.is_school_admin(school_id));
create policy "curriculum_update" on public.curriculum
  for update using (school_id is not null and public.is_school_admin(school_id));
create policy "curriculum_delete" on public.curriculum
  for delete using (school_id is not null and public.is_school_admin(school_id));

create policy "curriculum_subjects_insert" on public.curriculum_subjects
  for insert with check (
    school_id is not null
    and public.is_school_admin(school_id)
    and school_id = (select c.school_id from public.curriculum c where c.id = curriculum_id)
  );
create policy "curriculum_subjects_update" on public.curriculum_subjects
  for update using (school_id is not null and public.is_school_admin(school_id));
create policy "curriculum_subjects_delete" on public.curriculum_subjects
  for delete using (school_id is not null and public.is_school_admin(school_id));

create policy "coef_cfg_insert" on public.subject_coefficient_configurations
  for insert with check (school_id is not null and public.is_school_admin(school_id));
create policy "coef_cfg_update" on public.subject_coefficient_configurations
  for update using (school_id is not null and public.is_school_admin(school_id));
create policy "coef_cfg_delete" on public.subject_coefficient_configurations
  for delete using (school_id is not null and public.is_school_admin(school_id));

create policy "schemes_insert" on public.assessment_schemes
  for insert with check (school_id is not null and public.is_school_admin(school_id));
create policy "schemes_update" on public.assessment_schemes
  for update using (school_id is not null and public.is_school_admin(school_id));
create policy "schemes_delete" on public.assessment_schemes
  for delete using (school_id is not null and public.is_school_admin(school_id));

create policy "rules_insert" on public.academic_rules
  for insert with check (school_id is not null and public.is_school_admin(school_id));
create policy "rules_update" on public.academic_rules
  for update using (school_id is not null and public.is_school_admin(school_id));
create policy "rules_delete" on public.academic_rules
  for delete using (school_id is not null and public.is_school_admin(school_id));

-- --- students ---
create policy "students_select" on public.students for select using (public.is_school_member(school_id));
create policy "students_insert" on public.students for insert with check (public.is_school_member(school_id));
create policy "students_update" on public.students for update using (public.is_school_member(school_id));
create policy "students_delete" on public.students for delete using (public.is_school_admin(school_id));

create policy "enrollments_select" on public.student_enrollments for select using (public.is_school_member(school_id));
create policy "enrollments_insert" on public.student_enrollments for insert with check (public.is_school_member(school_id));
create policy "enrollments_update" on public.student_enrollments for update using (public.is_school_member(school_id));
create policy "enrollments_delete" on public.student_enrollments for delete using (public.is_school_admin(school_id));

-- --- teacher assignments ---
create policy "assignments_select" on public.teacher_assignments for select using (public.is_school_member(school_id));
create policy "assignments_insert" on public.teacher_assignments for insert with check (public.is_school_admin(school_id));
create policy "assignments_update" on public.teacher_assignments for update using (public.is_school_admin(school_id));
create policy "assignments_delete" on public.teacher_assignments for delete using (public.is_school_admin(school_id));

-- --- mark books: teachers manage their own books; admins manage all in the school ---
-- Note: the INSERT policy for mark_books validates against the NEW row's
-- teacher_assignment_id, because the book's own id is not yet visible to
-- subqueries during an INSERT.
create or replace function public.is_assignment_teacher(p_assignment uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.teacher_assignments ta
    where ta.id = p_assignment
      and ta.teacher_membership_id in (
        select id from public.school_memberships
        where profile_id = auth.uid() and is_active
      )
  );
$$;

create or replace function public.is_teacher_of_book(p_book uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.mark_books mb
    join public.teacher_assignments ta on ta.id = mb.teacher_assignment_id
    where mb.id = p_book
      and ta.teacher_membership_id in (
        select id from public.school_memberships
        where profile_id = auth.uid() and is_active
      )
  );
$$;

create policy "mark_books_select" on public.mark_books
  for select using (public.is_school_member(school_id));
create policy "mark_books_insert" on public.mark_books
  for insert with check (
    public.is_school_member(school_id)
    and public.is_assignment_teacher(teacher_assignment_id)
  );
create policy "mark_books_update" on public.mark_books
  for update using (public.is_school_admin(school_id) or public.is_teacher_of_book(id));
create policy "mark_books_delete" on public.mark_books
  for delete using (public.is_school_admin(school_id));

create policy "mark_entries_select" on public.mark_entries
  for select using (public.is_school_member(school_id));
create policy "mark_entries_insert" on public.mark_entries
  for insert with check (
    public.is_school_member(school_id)
    and (public.is_school_admin(school_id) or public.is_teacher_of_book(mark_book_id))
  );
create policy "mark_entries_update" on public.mark_entries
  for update using (
    public.is_school_admin(school_id) or public.is_teacher_of_book(mark_book_id)
  );
create policy "mark_entries_delete" on public.mark_entries
  for delete using (public.is_school_admin(school_id) or public.is_teacher_of_book(mark_book_id));

create policy "mark_events_select" on public.mark_book_events
  for select using (public.is_school_member(school_id));
create policy "mark_events_insert" on public.mark_book_events
  for insert with check (
    public.is_school_member(school_id)
    and (public.is_school_admin(school_id) or public.is_teacher_of_book(mark_book_id))
  );

-- --- results ---
create policy "results_select" on public.period_results for select using (public.is_school_member(school_id));
create policy "results_insert" on public.period_results for insert with check (public.is_school_admin(school_id));
create policy "results_update" on public.period_results for update using (public.is_school_admin(school_id));
create policy "results_delete" on public.period_results for delete using (public.is_school_admin(school_id));

create policy "subject_results_select" on public.subject_results
  for select using (public.is_school_member(school_id));
create policy "subject_results_insert" on public.subject_results
  for insert with check (public.is_school_admin(school_id));
create policy "subject_results_update" on public.subject_results
  for update using (public.is_school_admin(school_id));
create policy "subject_results_delete" on public.subject_results
  for delete using (public.is_school_admin(school_id));

-- --- report cards ---
create policy "report_cards_select" on public.report_cards for select using (public.is_school_member(school_id));
create policy "report_cards_insert" on public.report_cards for insert with check (public.is_school_admin(school_id));
create policy "report_cards_delete" on public.report_cards for delete using (public.is_school_admin(school_id));

-- --- notifications: owner reads/updates own; school writes to its members ---
create policy "notifications_select" on public.notifications
  for select using (recipient_profile_id = auth.uid());
create policy "notifications_update" on public.notifications
  for update using (recipient_profile_id = auth.uid());
create policy "notifications_insert" on public.notifications
  for insert with check (public.is_school_admin(school_id));

-- =============================================================================
-- ONBOARDING RPC
-- School registration (sections 2, 3, 35). Runs as security definer so a brand
-- new user can create a school and become its first SUPER_ADMIN atomically.
-- =============================================================================
create or replace function public.create_school(
  p_name          text,
  p_school_type   text,   -- GENERAL | TECHNICAL | BOTH
  p_subsystem     text,   -- FRANCOPHONE | ANGLOPHONE | BILINGUAL
  p_address       text default null,
  p_phone         text default null,
  p_email         text default null,
  p_region        text default null,
  p_division      text default null,
  p_sub_division  text default null,
  p_code          text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if p_school_type not in ('GENERAL','TECHNICAL','BOTH')
     or p_subsystem not in ('FRANCOPHONE','ANGLOPHONE','BILINGUAL') then
    raise exception 'Invalid school type or subsystem';
  end if;

  insert into public.schools
    (name, code, school_type, subsystem, address, phone, email, region, division, sub_division)
  values
    (p_name, p_code, p_school_type, p_subsystem, p_address, p_phone, p_email,
     p_region, p_division, p_sub_division)
  returning id into v_school;

  insert into public.school_memberships (school_id, profile_id, role)
  values (v_school, auth.uid(), 'SUPER_ADMIN');

  return v_school;
end;
$$;

-- =============================================================================
-- CAMEROON DEFAULTS (Layer 1 — NATIONAL_DEFAULT)
-- Representative starting values, admin-overridable. Verify against official
-- MINESEC documents before relying on exact coefficients.
-- =============================================================================

insert into public.education_types (code, name, name_fr, sort_order) values
  ('GENERAL',  'General Education',        'Enseignement Général',    1),
  ('TECHNICAL','Technical & Vocational',   'Enseignement Technique',  2);

insert into public.subsystems (code, name) values
  ('FRANCOPHONE', 'Système Francophone'),
  ('ANGLOPHONE',  'Anglophone System');

insert into public.cycles (education_type_id, subsystem, code, name, name_fr, sort_order)
select et.id, 'FRANCOPHONE', 'FIRST_CYCLE', 'First Cycle', 'Premier Cycle', 1 from public.education_types et where et.code = 'GENERAL';
insert into public.cycles (education_type_id, subsystem, code, name, name_fr, sort_order)
select et.id, 'FRANCOPHONE', 'SECOND_CYCLE', 'Second Cycle', 'Second Cycle', 2 from public.education_types et where et.code = 'GENERAL';
insert into public.cycles (education_type_id, subsystem, code, name, name_fr, sort_order)
select et.id, 'ANGLOPHONE', 'FIRST_CYCLE', 'First Cycle', 'Premier Cycle', 1 from public.education_types et where et.code = 'GENERAL';
insert into public.cycles (education_type_id, subsystem, code, name, name_fr, sort_order)
select et.id, 'ANGLOPHONE', 'SECOND_CYCLE', 'Second Cycle', 'Second Cycle', 2 from public.education_types et where et.code = 'GENERAL';
insert into public.cycles (education_type_id, subsystem, code, name, name_fr, sort_order)
select et.id, null, 'FIRST_CYCLE', 'First Cycle', 'Premier Cycle', 1 from public.education_types et where et.code = 'TECHNICAL';
insert into public.cycles (education_type_id, subsystem, code, name, name_fr, sort_order)
select et.id, null, 'SECOND_CYCLE', 'Second Cycle', 'Second Cycle', 2 from public.education_types et where et.code = 'TECHNICAL';

-- Francophone levels: First cycle
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', '6EME', '6ème', 'Sixième', 1 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', '5EME', '5ème', 'Cinquième', 2 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', '4EME', '4ème', 'Quatrième', 3 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', '3EME', '3ème', 'Troisième', 4 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';

-- Francophone levels: Second cycle
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', '2NDE', '2nde', 'Seconde', 5 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'SECOND_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', '1ERE', '1ère', 'Première', 6 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'SECOND_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, 'FRANCOPHONE', 'TLE', 'Terminale', 'Terminale', 7 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'SECOND_CYCLE';

-- Anglophone levels: First cycle (Form 1–5)
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'FORM_1', 'Form 1', 1 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'FORM_2', 'Form 2', 2 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'FORM_3', 'Form 3', 3 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'FORM_4', 'Form 4', 4 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'FORM_5', 'Form 5', 5 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'FIRST_CYCLE';

-- Anglophone levels: Second cycle (Lower Sixth / Upper Sixth)
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'LOWER_SIXTH', 'Lower Sixth', 6 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'SECOND_CYCLE';
insert into public.levels (cycle_id, subsystem, code, name, sort_order)
select c.id, 'ANGLOPHONE', 'UPPER_SIXTH', 'Upper Sixth', 7 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'GENERAL' and c.code = 'SECOND_CYCLE';

-- Series (Francophone grammar + bilingual)
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, 'FRANCOPHONE', 'A',   'Lettres',        'Série A', 1  from public.education_types et where et.code = 'GENERAL';
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, 'FRANCOPHONE', 'C',   'Sciences Mathématiques', 'Série C', 2 from public.education_types et where et.code = 'GENERAL';
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, 'FRANCOPHONE', 'D',   'Sciences Expérimentales', 'Série D', 3 from public.education_types et where et.code = 'GENERAL';
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, 'FRANCOPHONE', 'TI',  'Techniques de l''Information', 'Série TI', 4 from public.education_types et where et.code = 'GENERAL';
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, 'FRANCOPHONE', 'BIL', 'Bilinguisme',    'Série BIL', 5 from public.education_types et where et.code = 'GENERAL';

-- Technical families: STT (tertiary) and IND (industrial)
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, null, 'STT', 'Sciences et Technologies du Tertiaire', 'STT', 1 from public.education_types et where et.code = 'TECHNICAL';
insert into public.series (education_type_id, subsystem, code, name_fr, name, sort_order)
select et.id, null, 'IND', 'Sciences et Technologies Industrielles', 'IND', 2 from public.education_types et where et.code = 'TECHNICAL';

-- Technical specialties
insert into public.specialties (series_id, code, name)
select s.id, 'GCA', 'Comptabilité et Gestion' from public.series s where s.code = 'STT';
insert into public.specialties (series_id, code, name)
select s.id, 'SESC', 'Sciences Économiques et Sociales' from public.series s where s.code = 'STT';
insert into public.specialties (series_id, code, name)
select s.id, 'TCA', 'Techniques Commerciales' from public.series s where s.code = 'STT';
insert into public.specialties (series_id, code, name)
select s.id, 'ELECTRO', 'Électronique' from public.series s where s.code = 'IND';
insert into public.specialties (series_id, code, name)
select s.id, 'MECA', 'Mécanique Générale' from public.series s where s.code = 'IND';
insert into public.specialties (series_id, code, name)
select s.id, 'GENIE_CIVIL', 'Génie Civil' from public.series s where s.code = 'IND';

-- National subject catalog (representative Cameroon set)
insert into public.subjects (code, name, name_fr, subject_type) values
  ('FR',    'Français',                'Français',                'LANGUAGE'),
  ('ENG',   'English',                 'Anglais',                 'LANGUAGE'),
  ('MATHS', 'Mathematics',             'Mathématiques',           'GENERAL'),
  ('PHY',   'Physics',                 'Physique',                'GENERAL'),
  ('CHM',   'Chemistry',               'Chimie',                  'GENERAL'),
  ('SVT',   'Biology / Earth Sciences','Sciences de la Vie et de la Terre', 'GENERAL'),
  ('HIST',  'History',                 'Histoire',                'GENERAL'),
  ('GEO',   'Geography',               'Géographie',              'GENERAL'),
  ('PHILO', 'Philosophy',              'Philosophie',             'GENERAL'),
  ('EPS',   'Physical Education',      'Éducation Physique et Sportive', 'SPORT'),
  ('CIVIC', 'Civics / Civic Education','Éducation Civique',       'GENERAL'),
  ('ICT',   'Information & Communication Technology', 'Informatique', 'TECHNICAL'),
  ('ACCT',  'Accounting',              'Comptabilité',            'PROFESSIONAL'),
  ('MGMT',  'Management',              'Gestion',                 'PROFESSIONAL'),
  ('ECON',  'Economics',               'Économie',                'PROFESSIONAL'),
  ('LAW',   'Law',                     'Droit',                   'PROFESSIONAL'),
  ('GEN',   'General Knowledge',       'Culture Générale',        'GENERAL'),
  ('DRAW',  'Technical Drawing',       'Dessin Technique',        'TECHNICAL'),
  ('PRAC',  'Practical Workshop',      'Travaux Pratiques',       'PRACTICAL');

-- Representative national curriculum for Francophone First Cycle (3ème)
insert into public.curriculum (education_type_id, subsystem, cycle_id, level_id, source, source_ref, name)
select et.id, 'FRANCOPHONE', cy.id, lv.id, 'NATIONAL_DEFAULT',
       'MINESEC — representative; verify official coefficients', '3ème national'
from public.education_types et
join public.cycles cy on cy.education_type_id = et.id and cy.code = 'FIRST_CYCLE'
join public.levels lv on lv.cycle_id = cy.id and lv.code = '3EME'
where et.code = 'GENERAL';

insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 5, 5, 'GENERAL', 1 from public.curriculum cur, public.subjects s where s.code = 'MATHS';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 4, 4, 'GENERAL', 2 from public.curriculum cur, public.subjects s where s.code = 'PHY';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 3, 3, 'GENERAL', 3 from public.curriculum cur, public.subjects s where s.code = 'SVT';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 4, 4, 'LANGUAGE', 4 from public.curriculum cur, public.subjects s where s.code = 'FR';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 3, 3, 'LANGUAGE', 5 from public.curriculum cur, public.subjects s where s.code = 'ENG';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 3, 3, 'GENERAL', 6 from public.curriculum cur, public.subjects s where s.code = 'HIST';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 3, 3, 'GENERAL', 7 from public.curriculum cur, public.subjects s where s.code = 'GEO';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 2, 2, 'SPORT', 8 from public.curriculum cur, public.subjects s where s.code = 'EPS';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 1, 1, 'TECHNICAL', 9 from public.curriculum cur, public.subjects s where s.code = 'ICT';
insert into public.curriculum_subjects (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
select cur.id, cur.school_id, s.id, 1, 1, 'GENERAL', 10 from public.curriculum cur, public.subjects s where s.code = 'CIVIC';

-- National coefficient layer (mirrors 3ème curriculum; applies as default fallback)
insert into public.subject_coefficient_configurations (education_type_id, level_id, subject_id, coefficient, source, source_ref)
select c.education_type_id, c.level_id, cs.subject_id, cs.coefficient, 'NATIONAL_DEFAULT', 'MINESEC — representative'
from public.curriculum c
join public.curriculum_subjects cs on cs.curriculum_id = c.id;

-- Default assessment schemes
insert into public.assessment_schemes (name, source, is_default)
values ('Classic Cameroon (CA/Interro/Devoir/Exam)', 'NATIONAL_DEFAULT', true);

insert into public.assessment_scheme_components (scheme_id, school_id, name, component_type, weight, max_score, sort_order)
select s.id, s.school_id, 'Interrogation', 'CLASS_TEST', 20, 20, 1 from public.assessment_schemes s where s.is_default;
insert into public.assessment_scheme_components (scheme_id, school_id, name, component_type, weight, max_score, sort_order)
select s.id, s.school_id, 'Devoir', 'ASSIGNMENT', 30, 20, 2 from public.assessment_schemes s where s.is_default;
insert into public.assessment_scheme_components (scheme_id, school_id, name, component_type, weight, max_score, sort_order)
select s.id, s.school_id, 'Examen / Composition', 'EXAM', 50, 20, 3 from public.assessment_schemes s where s.is_default;

insert into public.assessment_schemes (name, source, is_default)
values ('Continuous Assessment / Exam', 'NATIONAL_DEFAULT', false);
insert into public.assessment_scheme_components (scheme_id, school_id, name, component_type, weight, max_score, sort_order)
select s.id, s.school_id, 'Continuous Assessment', 'CONTINUOUS_ASSESSMENT', 40, 20, 1 from public.assessment_schemes s where s.name = 'Continuous Assessment / Exam';
insert into public.assessment_scheme_components (scheme_id, school_id, name, component_type, weight, max_score, sort_order)
select s.id, s.school_id, 'Examination', 'EXAM', 60, 20, 2 from public.assessment_schemes s where s.name = 'Continuous Assessment / Exam';

-- Default academic rules (national layer)
insert into public.academic_rules (rule_key, rule_value, source, description) values
  ('RANKING_METHOD',        '{"value":"COMPETITION"}',   'NATIONAL_DEFAULT', 'Standard competition ranking (1,2,2,4)'),
  ('RANKING_SCOPE',         '{"class":true,"level":false,"school":false}', 'NATIONAL_DEFAULT', 'Rank within class by default'),
  ('TIE_BREAKER',           '{"value":"TOTAL_WEIGHTED_POINTS"}', 'NATIONAL_DEFAULT', 'Tie-break by higher total weighted points'),
  ('ANNUAL_AVERAGE_METHOD', '{"value":"MEAN_OF_TERM_AVERAGES"}', 'NATIONAL_DEFAULT', 'Annual = mean of term averages'),
  ('DISPLAY_PRECISION',     '{"value":2,"rounding":"HALF_UP"}', 'NATIONAL_DEFAULT', 'Report-card display precision'),
  ('MISSING_MARK_POLICY',   '{"exclude":["NOT_ENTERED","ABSENT","EXCUSED","NOT_APPLICABLE","PENDING"],"zero_is_score":true}', 'NATIONAL_DEFAULT', 'Which absence statuses exclude the subject from averages'),
  ('RANK_TIES_SAME_RANK',   '{"value":true}', 'NATIONAL_DEFAULT', 'Equal averages share the same rank');
