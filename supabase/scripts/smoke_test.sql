-- =============================================================================
-- ReportWise — Seed & integrity smoke test (spec section 45)
--
-- Verifies that the Cameroon defaults seeded by migration 0001 exist, that the
-- Phase 0 hardening objects are in place, and that core invariants hold.
-- Safe to run repeatedly; raises (aborts) on any failure.
--
--   supabase db query --linked -f scripts/smoke_test.sql
--   or psql with the same file (assertions raise on any failure).
-- =============================================================================

do $$
declare
  n integer;
begin
  -- --- Cameroon defaults (migration 0001) ---
  select count(*) into n from public.education_types;
  assert n = 2, 'education_types should be 2 (GENERAL, TECHNICAL)';

  select count(*) into n from public.subsystems;
  assert n = 2, 'subsystems should be 2 (FRANCOPHONE, ANGLOPHONE)';

  select count(*) into n from public.cycles;
  assert n >= 6, 'cycles should be >= 6';

  select count(*) into n from public.levels;
  assert n >= 16, 'levels should be >= 16 (6ème..Tle, Form 1..Upper Sixth, technical)';

  select count(*) into n from public.series;
  assert n >= 7, 'series should be >= 7 (A,C,D,TI,BIL,STT,IND)';

  select count(*) into n from public.specialties;
  assert n >= 6, 'specialties should be >= 6';

  select count(*) into n from public.subjects where school_id is null;
  assert n >= 15, 'national subject catalog should be >= 15';

  select count(*) into n from public.curriculum where source = 'NATIONAL_DEFAULT';
  assert n >= 1, 'at least one national curriculum row';

  select count(*) into n from public.assessment_schemes where source = 'NATIONAL_DEFAULT';
  assert n >= 1, 'at least one national assessment scheme';

  select count(*) into n from public.academic_rules;
  assert n >= 1, 'at least one national academic rule';

  -- --- Phase 0 objects ---
  assert exists (select 1 from pg_proc where proname = 'can_edit_mark_book'), 'can_edit_mark_book missing';
  assert exists (select 1 from pg_proc where proname = 'unlock_mark_book'), 'unlock_mark_book missing';
  assert exists (select 1 from pg_proc where proname = 'set_current_academic_year'), 'set_current_academic_year missing';
  assert exists (select 1 from pg_proc where proname = 'save_assessment_scheme'), 'save_assessment_scheme missing';
  assert exists (select 1 from pg_proc where proname = 'enforce_mark_book_transition'), 'enforce_mark_book_transition missing';
  assert exists (select 1 from pg_proc where proname = 'audit_config_change'), 'audit_config_change missing';
  assert exists (select 1 from pg_proc where proname = 'period_results_immutable'), 'period_results_immutable missing';
  assert exists (select 1 from pg_proc where proname = 'subject_results_immutable'), 'subject_results_immutable missing';

  assert exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'academic_config_audit'), 'academic_config_audit missing';

  select count(*) into n from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  where c.relname = 'mark_books' and not t.tgisinternal;
  assert n >= 1, 'mark_books workflow trigger missing';

  select count(*) into n from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  where c.relname = 'period_results' and not t.tgisinternal;
  assert n >= 1, 'period_results immutability triggers missing';

  -- single current academic year index
  select count(*) into n from pg_indexes where indexname = 'academic_years_one_current_idx';
  assert n = 1, 'academic_years_one_current_idx missing';

  -- RLS enabled on core tenant tables
  select count(*) into n from pg_class c
  join pg_namespace nsp on nsp.oid = c.relnamespace
  where nsp.nspname = 'public'
    and c.relname in ('schools','students','mark_books','mark_entries','period_results','subject_coefficient_configurations')
    and c.relrowsecurity;
  assert n = 6, 'RLS should be enabled on the 6 core tenant tables';

  raise notice 'smoke test: ALL CHECKS PASSED';
end;
$$;