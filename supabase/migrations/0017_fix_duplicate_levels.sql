-- =============================================================================
-- ReportWise — Migration 0017
-- Fix duplicated national hierarchy seed (root cause of empty subject sets).
--
-- Migration 0001 inserted levels/series with INSERT..SELECT that matched BOTH
-- the ANGLOPHONE and FRANCOPHONE cycles of an education type (it did not filter
-- cycles.subsystem). This produced 14 bogus rows: ANGLOPHONE-tagged levels under
-- FRANCOPHONE cycles and vice-versa. Classes created against those bogus levels
-- then failed to resolve a curriculum (their level_id never matched), which is
-- why the Subjects/coefficients tab appeared empty.
--
-- This migration:
--   1. maps every bogus level to its correct sibling and re-points all
--      references (classes, curriculum, coefficient configs, schemes),
--   2. deletes the bogus level rows,
--   3. deduplicates curricula and coefficient configurations that were
--      double-created by the same multi-cycle JOIN in 0001,
--   4. adds a guard trigger (a level's subsystem must match its cycle) and
--      coalesced unique indexes so the duplication cannot recur.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Map bogus levels -> correct level + its cycle, then re-point references.
-- -----------------------------------------------------------------------------
create temp table _lv_fix on commit drop as
select distinct on (bogus.id)
       bogus.id as dup_id, good.id as canon_id, good.cycle_id as canon_cycle
from public.levels bogus
join public.cycles boguscy on boguscy.id = bogus.cycle_id
join public.levels good
  on good.code = bogus.code
 and good.subsystem is not distinct from bogus.subsystem
 and good.id <> bogus.id
join public.cycles goodcy on goodcy.id = good.cycle_id
where (bogus.subsystem = 'ANGLOPHONE' and boguscy.subsystem = 'FRANCOPHONE')
   or (bogus.subsystem = 'FRANCOPHONE' and boguscy.subsystem = 'ANGLOPHONE')
order by bogus.id, good.id;

update public.classes c
  set level_id = f.canon_id, cycle_id = f.canon_cycle
from _lv_fix f
where c.level_id = f.dup_id;

update public.curriculum cu
  set level_id = f.canon_id, cycle_id = f.canon_cycle
from _lv_fix f
where cu.level_id = f.dup_id;

update public.subject_coefficient_configurations cc
  set level_id = f.canon_id, cycle_id = f.canon_cycle
from _lv_fix f
where cc.level_id = f.dup_id;

update public.assessment_schemes s
  set level_id = f.canon_id
from _lv_fix f
where s.level_id = f.dup_id;

delete from public.levels lv using _lv_fix f where lv.id = f.dup_id;

-- Safety: a row's cycle must always match its level's cycle.
update public.classes c set cycle_id = lv.cycle_id
from public.levels lv where lv.id = c.level_id and c.cycle_id is distinct from lv.cycle_id;

update public.curriculum cu set cycle_id = lv.cycle_id
from public.levels lv where lv.id = cu.level_id and cu.cycle_id is distinct from lv.cycle_id;

update public.subject_coefficient_configurations cc set cycle_id = lv.cycle_id
from public.levels lv where lv.id = cc.level_id and cc.cycle_id is distinct from lv.cycle_id;

drop table _lv_fix;

-- -----------------------------------------------------------------------------
-- 2. Deduplicate curricula that were double-created by 0001's multi-cycle JOIN.
-- -----------------------------------------------------------------------------
create temp table _cur_fix on commit drop as
with ranked as (
  select id,
         first_value(id) over (
           partition by
             coalesce(school_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(academic_year_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(subsystem, ''),
             coalesce(education_type_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(cycle_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(level_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(series_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(specialty_id, '00000000-0000-0000-0000-000000000000'),
             source
           order by id
         ) as canon_id
  from public.curriculum
)
select id as dup_id, canon_id from ranked where id <> canon_id;

-- Merge the duplicate curriculum's subjects into the canonical curriculum,
-- then drop the duplicate curriculum's own rows.
insert into public.curriculum_subjects
  (curriculum_id, school_id, subject_id, coefficient, weekly_hours, subject_type,
   counts_in_average, counts_in_ranking, shows_on_report, sort_order)
select
  f.canon_id, cs.school_id, cs.subject_id, cs.coefficient, cs.weekly_hours, cs.subject_type,
  cs.counts_in_average, cs.counts_in_ranking, cs.shows_on_report, cs.sort_order
from public.curriculum_subjects cs
join _cur_fix f on f.dup_id = cs.curriculum_id
on conflict (curriculum_id, subject_id) do nothing;

delete from public.curriculum_subjects cs using _cur_fix f where cs.curriculum_id = f.dup_id;
delete from public.curriculum cu using _cur_fix f where cu.id = f.dup_id;

drop table _cur_fix;

-- -----------------------------------------------------------------------------
-- 3. Deduplicate coefficient configurations (0001 created them per curriculum).
-- -----------------------------------------------------------------------------
delete from public.subject_coefficient_configurations cc
using (
  select id,
         row_number() over (
           partition by
             coalesce(school_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(academic_year_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(subsystem, ''),
             coalesce(education_type_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(cycle_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(level_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(series_id, '00000000-0000-0000-0000-000000000000'),
             coalesce(specialty_id, '00000000-0000-0000-0000-000000000000'),
             subject_id, coefficient, source
           order by id
         ) as rn
  from public.subject_coefficient_configurations
) r
where cc.id = r.id and r.rn > 1;

-- -----------------------------------------------------------------------------
-- 4. Guards against recurrence.
-- -----------------------------------------------------------------------------
create or replace function public.validate_level_cycle_subsystem()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cycle_subsys text;
begin
  select subsystem into v_cycle_subsys from public.cycles where id = new.cycle_id;
  if v_cycle_subsys is null then
    if new.subsystem is not null then
      raise exception 'Level subsystem must be NULL when its cycle has no subsystem';
    end if;
  elsif new.subsystem is null or new.subsystem <> v_cycle_subsys then
    raise exception 'Level subsystem (%) must match its cycle subsystem (%)',
      new.subsystem, v_cycle_subsys;
  end if;
  return new;
end;
$$;

drop trigger if exists levels_subsystem_check on public.levels;
create trigger levels_subsystem_check
  before insert or update on public.levels
  for each row execute function public.validate_level_cycle_subsystem();

-- Coalesced unique indexes close the NULL != NULL loophole on national rows.
create unique index if not exists cycles_unique_key_idx
  on public.cycles (coalesce(school_id, '00000000-0000-0000-0000-000000000000'),
                    education_type_id, coalesce(subsystem, ''), code);

create unique index if not exists levels_unique_key_idx
  on public.levels (coalesce(school_id, '00000000-0000-0000-0000-000000000000'),
                    cycle_id, coalesce(subsystem, ''), code);

create unique index if not exists series_unique_key_idx
  on public.series (coalesce(school_id, '00000000-0000-0000-0000-000000000000'),
                    education_type_id, coalesce(subsystem, ''), code);

create unique index if not exists specialties_unique_key_idx
  on public.specialties (coalesce(school_id, '00000000-0000-0000-0000-000000000000'),
                         coalesce(series_id, '00000000-0000-0000-0000-000000000000'), code);

create unique index if not exists subjects_unique_key_idx
  on public.subjects (coalesce(school_id, '00000000-0000-0000-0000-000000000000'), code);