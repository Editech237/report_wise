-- =============================================================================
-- ReportWise — Migration 0008
-- DB-level result immutability (spec section 26).
--
-- Once a period result is FINAL, its row and every child subject_result row
-- become immutable. Historical report cards stay reproducible because the
-- inputs/coefficients/rules were captured in config_snapshot at calculation
-- time and can never be silently rewritten afterwards.
-- =============================================================================

-- period_results: no UPDATE or DELETE once FINAL.
create or replace function public.period_results_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'FINAL' then
    raise exception 'Finalized period results are immutable';
  end if;
  return new;
end;
$$;

create or replace function public.period_results_no_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'FINAL' then
    raise exception 'Finalized period results cannot be deleted';
  end if;
  return old;
end;
$$;

drop trigger if exists period_results_immutable on public.period_results;
create trigger period_results_immutable
  before update on public.period_results
  for each row execute function public.period_results_immutable();

drop trigger if exists period_results_no_delete on public.period_results;
create trigger period_results_no_delete
  before delete on public.period_results
  for each row execute function public.period_results_no_delete();

-- subject_results: immutable whenever their parent period result is FINAL.
create or replace function public.subject_results_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.period_results pr
  where pr.id = old.period_result_id;
  if v_status = 'FINAL' then
    raise exception 'Subject results belonging to a finalized period result are immutable';
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists subject_results_immutable on public.subject_results;
create trigger subject_results_immutable
  before update or delete on public.subject_results
  for each row execute function public.subject_results_immutable();