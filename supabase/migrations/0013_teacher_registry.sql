-- =============================================================================
-- ReportWise — Migration 0013
-- Teacher registry & assignments (spec section 37).
--
-- Profiles are RLS-hidden (a user only sees their own), so administrators
-- cannot read other staff members' names/emails through normal selects. These
-- security-definer RPCs expose the minimal, auditable surface for managing
-- teachers while keeping the underlying tables locked down.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Add a teacher to the school by email.
-- The teacher must already have an account (profile row); otherwise a distinct
-- error is raised so the UI can guide the admin.
-- -----------------------------------------------------------------------------
create or replace function public.add_teacher(
  p_school    uuid,
  p_email     text,
  p_staff_id  text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile    uuid;
  v_membership uuid;
begin
  if not public.is_school_admin(p_school) then
    raise exception 'Only an administrator can add teachers';
  end if;
  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'An email is required';
  end if;

  select id into v_profile from public.profiles
    where lower(email) = lower(trim(p_email))
    limit 1;
  if v_profile is null then
    raise exception 'TEACHER_NO_ACCOUNT: no account exists for % — the teacher must sign up first',
      trim(p_email);
  end if;

  select id into v_membership from public.school_memberships
    where school_id = p_school and profile_id = v_profile
    limit 1;
  if v_membership is not null then
    raise exception 'ALREADY_MEMBER: this user is already a member of the school';
  end if;

  insert into public.school_memberships (school_id, profile_id, role, staff_id)
  values (p_school, v_profile, 'TEACHER', nullif(trim(coalesce(p_staff_id, '')), ''))
  returning id into v_membership;

  return v_membership;
end;
$$;

-- -----------------------------------------------------------------------------
-- Remove a TEACHER membership. Any class-teacher reference is cleared first
-- (classes.class_teacher_id is a plain FK with NO ACTION). Teacher assignments
-- are removed by their on-delete-cascade.
-- -----------------------------------------------------------------------------
create or replace function public.remove_teacher(p_school uuid, p_membership uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  if not public.is_school_admin(p_school) then
    raise exception 'Only an administrator can remove teachers';
  end if;

  select role into v_role
    from public.school_memberships
    where id = p_membership and school_id = p_school;
  if v_role is null then
    raise exception 'Membership not found in this school';
  end if;
  if v_role <> 'TEACHER' then
    raise exception 'Only TEACHER memberships can be removed here';
  end if;

  update public.classes set class_teacher_id = null where class_teacher_id = p_membership;
  delete from public.school_memberships where id = p_membership;
end;
$$;

-- -----------------------------------------------------------------------------
-- Staff directory for a school (membership + profile info).
-- Visible to any member of the school.
-- -----------------------------------------------------------------------------
create or replace function public.list_school_members(p_school uuid)
returns table (
  membership_id uuid,
  profile_id    uuid,
  role          text,
  staff_id      text,
  is_active     boolean,
  full_name     text,
  email         text,
  avatar_url    text
)
language sql
stable
security definer
set search_path = public
as $$
  select sm.id, sm.profile_id, sm.role, sm.staff_id, sm.is_active,
         p.full_name, p.email, p.avatar_url
  from public.school_memberships sm
  left join public.profiles p on p.id = sm.profile_id
  where sm.school_id = p_school
    and public.is_school_member(p_school)
  order by p.full_name nulls last;
$$;

-- -----------------------------------------------------------------------------
-- Create a teacher assignment (validates every reference stays in-school).
-- -----------------------------------------------------------------------------
create or replace function public.create_teacher_assignment(
  p_school    uuid,
  p_year      uuid,
  p_teacher   uuid,
  p_class     uuid,
  p_subject   uuid,
  p_specialty uuid default null,
  p_role      text default 'SUBJECT_TEACHER'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not public.is_school_admin(p_school) then
    raise exception 'Only an administrator can assign teachers';
  end if;
  if p_role not in ('SUBJECT_TEACHER', 'CLASS_TEACHER') then
    raise exception 'Invalid teaching role';
  end if;
  if not exists (select 1 from public.school_memberships where id = p_teacher and school_id = p_school) then
    raise exception 'Teacher is not a member of this school';
  end if;
  if not exists (select 1 from public.classes where id = p_class and school_id = p_school) then
    raise exception 'Class not found in this school';
  end if;
  if not exists (
    select 1 from public.subjects where id = p_subject and (school_id is null or school_id = p_school)
  ) then
    raise exception 'Subject not available in this school';
  end if;
  if p_specialty is not null and not exists (select 1 from public.specialties where id = p_specialty) then
    raise exception 'Specialty not found';
  end if;

  insert into public.teacher_assignments
    (school_id, academic_year_id, teacher_membership_id, class_id, subject_id, specialty_id, teaching_role)
  values
    (p_school, p_year, p_teacher, p_class, p_subject, p_specialty, p_role)
  returning id into v_id;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Teacher assignments for a school + academic year, enriched for the UI.
-- -----------------------------------------------------------------------------
create or replace function public.list_teacher_assignments(p_school uuid, p_year uuid)
returns table (
  id                    uuid,
  teacher_membership_id uuid,
  teacher_name          text,
  class_id              uuid,
  class_name            text,
  subject_id            uuid,
  subject_code          text,
  subject_name          text,
  specialty_id          uuid,
  specialty_name        text,
  teaching_role         text
)
language sql
stable
security definer
set search_path = public
as $$
  select ta.id, ta.teacher_membership_id, p.full_name,
         ta.class_id, c.name,
         ta.subject_id, s.code, s.name,
         ta.specialty_id, sp.name,
         ta.teaching_role
  from public.teacher_assignments ta
  join public.school_memberships sm on sm.id = ta.teacher_membership_id
  left join public.profiles p on p.id = sm.profile_id
  join public.classes c on c.id = ta.class_id
  join public.subjects s on s.id = ta.subject_id
  left join public.specialties sp on sp.id = ta.specialty_id
  where ta.school_id = p_school and ta.academic_year_id = p_year
    and public.is_school_member(p_school)
  order by p.full_name nulls last, c.name, s.name;
$$;

-- -----------------------------------------------------------------------------
-- Set (or clear) a class's class teacher. Validates the membership is a member
-- of the class's school.
-- -----------------------------------------------------------------------------
create or replace function public.set_class_teacher(p_class uuid, p_membership uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
begin
  select school_id into v_school from public.classes where id = p_class;
  if v_school is null then raise exception 'Class not found'; end if;
  if not public.is_school_admin(v_school) then
    raise exception 'Only an administrator can assign a class teacher';
  end if;
  if p_membership is not null and not exists (
    select 1 from public.school_memberships where id = p_membership and school_id = v_school
  ) then
    raise exception 'Membership does not belong to this school';
  end if;

  update public.classes set class_teacher_id = p_membership where id = p_class;
end;
$$;