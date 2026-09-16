-- =============================================================================
-- ReportWise — Migration 0011
-- Integrity constraints for academic years + assessment schemes.
--
--   1. A school has exactly ONE current academic year.
--   2. Assessment scheme components carry a range check; schemes are created/
--      updated atomically through save_assessment_scheme which enforces that
--      component weights sum to 100.
--   3. set_current_academic_year RPC switches the school's current year safely.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Single current academic year per school.
-- -----------------------------------------------------------------------------
-- De-duplicate any existing data (keep the most recently created current year).
update public.academic_years
set is_current = false
where is_current
  and id not in (
    select distinct on (school_id) id
    from public.academic_years
    where is_current
    order by school_id, created_at desc
  );

create unique index if not exists academic_years_one_current_idx
  on public.academic_years(school_id)
  where is_current;

-- Atomically set one current year for the school (clears the previous one).
create or replace function public.set_current_academic_year(p_school uuid, p_year uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_school_admin(p_school) then
    raise exception 'Only an administrator can change the current academic year';
  end if;
  if not exists (
    select 1 from public.academic_years where id = p_year and school_id = p_school
  ) then
    raise exception 'Academic year not found in this school';
  end if;
  update public.academic_years set is_current = false where school_id = p_school;
  update public.academic_years set is_current = true where id = p_year;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. Assessment scheme validation.
-- -----------------------------------------------------------------------------
-- Per-component range check (safe for incremental construction).
create or replace function public.validate_component_weight()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.weight <= 0 or new.weight > 100 then
    raise exception 'Assessment component weight must be between 0 and 100';
  end if;
  return new;
end;
$$;

drop trigger if exists assessment_component_weight_check on public.assessment_scheme_components;
create trigger assessment_component_weight_check
  before insert or update on public.assessment_scheme_components
  for each row execute function public.validate_component_weight();

-- Atomic scheme save (create or replace) that enforces weights sum to 100.
create or replace function public.save_assessment_scheme(
  p_school_id        uuid,
  p_name             text,
  p_components       jsonb,      -- [{name, name_fr, component_type, weight, max_score, sort_order}]
  p_academic_year_id uuid default null,
  p_education_type_id uuid default null,
  p_level_id         uuid default null,
  p_series_id        uuid default null,
  p_source           text default 'SCHOOL_CONFIGURATION',
  p_scheme_id        uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scheme uuid := p_scheme_id;
  v_total  numeric := 0;
  c        jsonb;
begin
  if not public.is_school_admin(p_school_id) then
    raise exception 'Only an administrator can manage assessment schemes';
  end if;
  if p_components is null or jsonb_array_length(p_components) = 0 then
    raise exception 'An assessment scheme must have at least one component';
  end if;

  for c in select * from jsonb_array_elements(p_components) loop
    v_total := v_total + (c ->> 'weight')::numeric;
  end loop;
  if abs(v_total - 100) > 0.01 then
    raise exception 'Assessment scheme weights must sum to 100 (current: %)', v_total;
  end if;

  if v_scheme is null then
    insert into public.assessment_schemes
      (school_id, academic_year_id, education_type_id, level_id, series_id, name, source)
    values
      (p_school_id, p_academic_year_id, p_education_type_id, p_level_id, p_series_id, p_name, p_source)
    returning id into v_scheme;
  else
    if not exists (
      select 1 from public.assessment_schemes where id = v_scheme and school_id = p_school_id
    ) then
      raise exception 'Assessment scheme not found in this school';
    end if;
    update public.assessment_schemes
    set name = p_name,
        academic_year_id = p_academic_year_id,
        education_type_id = p_education_type_id,
        level_id = p_level_id,
        series_id = p_series_id,
        updated_at = now()
    where id = v_scheme;
    delete from public.assessment_scheme_components where scheme_id = v_scheme;
  end if;

  insert into public.assessment_scheme_components
    (scheme_id, school_id, name, name_fr, component_type, weight, max_score, sort_order)
  select
    v_scheme,
    p_school_id,
    c ->> 'name',
    c ->> 'name_fr',
    c ->> 'component_type',
    (c ->> 'weight')::numeric,
    coalesce((c ->> 'max_score')::numeric, 20),
    coalesce((c ->> 'sort_order')::numeric, 0)::int
  from jsonb_array_elements(p_components) c;

  return v_scheme;
end;
$$;