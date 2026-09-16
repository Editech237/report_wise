-- =============================================================================
-- ReportWise — Migration 0009
-- Academic configuration audit trail (spec sections 40-41).
--
-- Every write to the versioned academic configuration tables
-- (coefficients, curriculum, assessment schemes, academic rules) is recorded
-- with the actor, the entity, the field and the old/new JSONB state. This gives
-- administrators full transparency about "where a configuration came from" and
-- makes sensitive changes traceable.
-- =============================================================================

create table public.academic_config_audit (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools(id) on delete cascade,
  actor_profile_id uuid references public.profiles(id),
  entity_type      text not null,             -- table name: SUBJECT_COEFFICIENT_CONFIGURATIONS | CURRICULUM | ...
  entity_id        uuid,
  field_name       text not null,             -- created | updated | deleted
  old_value        jsonb,
  new_value        jsonb,
  created_at       timestamptz not null default now()
);

create index if not exists config_audit_school_idx on public.academic_config_audit(school_id, created_at desc);
create index if not exists config_audit_entity_idx on public.academic_config_audit(entity_type, entity_id);

alter table public.academic_config_audit enable row level security;

create policy "config_audit_select" on public.academic_config_audit
  for select using (public.is_school_member(school_id));

-- Rows are written by the audit trigger (security definer); the explicit insert
-- policy exists so an administrator can annotate a change if ever needed.
create policy "config_audit_insert" on public.academic_config_audit
  for insert with check (public.is_school_admin(school_id));

-- -----------------------------------------------------------------------------
-- Generic audit trigger used by every academic configuration table.
-- National (school_id null) rows are admin-privileged and rare; they are not
-- logged here (no tenant context), which keeps the audit strictly per-school.
-- -----------------------------------------------------------------------------
create or replace function public.audit_config_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entity text := upper(TG_TABLE_NAME);
  v_school uuid := coalesce(new.school_id, old.school_id);
begin
  if v_school is null then
    return coalesce(new, old);
  end if;

  if TG_OP = 'INSERT' then
    insert into public.academic_config_audit
      (school_id, actor_profile_id, entity_type, entity_id, field_name, new_value)
    values (v_school, auth.uid(), v_entity, new.id, 'created', to_jsonb(new));
  elsif TG_OP = 'UPDATE' then
    insert into public.academic_config_audit
      (school_id, actor_profile_id, entity_type, entity_id, field_name, old_value, new_value)
    values (v_school, auth.uid(), v_entity, new.id, 'updated', to_jsonb(old), to_jsonb(new));
  elsif TG_OP = 'DELETE' then
    insert into public.academic_config_audit
      (school_id, actor_profile_id, entity_type, entity_id, field_name, old_value)
    values (v_school, auth.uid(), v_entity, old.id, 'deleted', to_jsonb(old));
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists audit_coefficient_cfg on public.subject_coefficient_configurations;
create trigger audit_coefficient_cfg
  after insert or update or delete on public.subject_coefficient_configurations
  for each row execute function public.audit_config_change();

drop trigger if exists audit_curriculum on public.curriculum;
create trigger audit_curriculum
  after insert or update or delete on public.curriculum
  for each row execute function public.audit_config_change();

drop trigger if exists audit_curriculum_subjects on public.curriculum_subjects;
create trigger audit_curriculum_subjects
  after insert or update or delete on public.curriculum_subjects
  for each row execute function public.audit_config_change();

drop trigger if exists audit_assessment_schemes on public.assessment_schemes;
create trigger audit_assessment_schemes
  after insert or update or delete on public.assessment_schemes
  for each row execute function public.audit_config_change();

drop trigger if exists audit_assessment_components on public.assessment_scheme_components;
create trigger audit_assessment_components
  after insert or update or delete on public.assessment_scheme_components
  for each row execute function public.audit_config_change();

drop trigger if exists audit_academic_rules on public.academic_rules;
create trigger audit_academic_rules
  after insert or update or delete on public.academic_rules
  for each row execute function public.audit_config_change();