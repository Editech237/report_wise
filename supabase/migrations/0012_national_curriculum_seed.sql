-- =============================================================================
-- ReportWise — Migration 0012
-- Full national curriculum seed (spec sections 5, 23).
--
-- Completes the Cameroon-oriented defaults started in 0001 so that EVERY level
-- and series/specialty resolves subjects (previously only 3ème did). Includes:
--   * technical education levels (first & second cycle)
--   * Anglophone second-cycle streams (ARTS / SCI series)
--   * additional national subjects (Literature, Commerce, technical trades)
--   * a national curriculum + matching national coefficient layer for every
--     level / series / specialty
--
-- IMPORTANT: coefficients below are REPRESENTATIVE starting values, consistent
-- with the existing 3ème seed. They are configurable per school and must be
-- verified against official MINESEC documents before production use (the
-- source_ref on every row says exactly that).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- New technical education levels (first cycle: 4 years; second cycle: 2 years)
-- -----------------------------------------------------------------------------
insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, null, 'TECH_Y1', '1st Year (Technical)', '1ère Année', 1 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'TECHNICAL' and c.code = 'FIRST_CYCLE';

insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, null, 'TECH_Y2', '2nd Year (Technical)', '2ème Année', 2 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'TECHNICAL' and c.code = 'FIRST_CYCLE';

insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, null, 'TECH_Y3', '3rd Year (Technical)', '3ème Année', 3 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'TECHNICAL' and c.code = 'FIRST_CYCLE';

insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, null, 'TECH_Y4', '4th Year (Technical)', '4ème Année', 4 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'TECHNICAL' and c.code = 'FIRST_CYCLE';

insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, null, 'TECH_1ERE', 'Première (Technical)', 'Première Technique', 5 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'TECHNICAL' and c.code = 'SECOND_CYCLE';

insert into public.levels (cycle_id, subsystem, code, name, name_fr, sort_order)
select c.id, null, 'TECH_TLE', 'Terminale (Technical)', 'Terminale Technique', 6 from public.cycles c
join public.education_types et on et.id = c.education_type_id
where et.code = 'TECHNICAL' and c.code = 'SECOND_CYCLE';

-- -----------------------------------------------------------------------------
-- Anglophone second-cycle streams (Arts / Science)
-- -----------------------------------------------------------------------------
insert into public.series (education_type_id, subsystem, code, name, sort_order)
select et.id, 'ANGLOPHONE', 'ARTS', 'Arts', 6 from public.education_types et where et.code = 'GENERAL';

insert into public.series (education_type_id, subsystem, code, name, sort_order)
select et.id, 'ANGLOPHONE', 'SCI', 'Science', 7 from public.education_types et where et.code = 'GENERAL';

-- -----------------------------------------------------------------------------
-- Additional national subjects
-- -----------------------------------------------------------------------------
insert into public.subjects (code, name, name_fr, subject_type) values
  ('LIT',  'Literature',             'Littérature',             'GENERAL'),
  ('COMM', 'Commerce',               'Techniques Commerciales', 'PROFESSIONAL'),
  ('ELEC', 'Electronics',            'Électronique',            'TECHNICAL'),
  ('MEC',  'Mechanics',              'Mécanique Générale',      'TECHNICAL'),
  ('GCIV', 'Civil Engineering',      'Génie Civil',             'TECHNICAL');

-- -----------------------------------------------------------------------------
-- Seeding helper (dropped at the end of this migration).
-- Creates a curriculum row for a scope + its curriculum_subjects and the
-- matching NATIONAL_DEFAULT coefficient configuration with the same scope.
-- -----------------------------------------------------------------------------
create or replace function public.tmp_seed_national_curriculum(
  p_education_type text,
  p_subsystem      text,
  p_cycle          text,
  p_level          text,
  p_series         text default null,
  p_specialty      text default null,
  p_entries        jsonb default '[]'
)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_et uuid; v_cy uuid; v_lv uuid; v_sr uuid; v_sp uuid; v_cur uuid;
  v_subj uuid; v_type text;
  e jsonb; i int := 0;
begin
  select id into v_et from public.education_types where code = p_education_type;
  select id into v_cy from public.cycles
    where education_type_id = v_et
      and subsystem is not distinct from p_subsystem
      and code = p_cycle;
  if v_cy is null then
    raise exception 'cycle not found: et=% subsystem=%s code=%',
      p_education_type, coalesce(p_subsystem, 'NULL'), p_cycle;
  end if;
  select id into v_lv from public.levels
    where cycle_id = v_cy
      and subsystem is not distinct from p_subsystem
      and code = p_level;
  if v_lv is null then raise exception 'level not found: %', p_level; end if;
  if p_series is not null then
    select id into v_sr from public.series
      where education_type_id = v_et
        and subsystem is not distinct from p_subsystem
        and code = p_series;
    if v_sr is null then raise exception 'series not found: %', p_series; end if;
  end if;
  if p_specialty is not null then
    select id into v_sp from public.specialties where code = p_specialty;
    if v_sp is null then raise exception 'specialty not found: %', p_specialty; end if;
  end if;

  insert into public.curriculum
    (education_type_id, subsystem, cycle_id, level_id, series_id, specialty_id, source, source_ref, name)
  values
    (v_et, p_subsystem, v_cy, v_lv, v_sr, v_sp, 'NATIONAL_DEFAULT',
     'MINESEC — representative; verify official coefficients',
     coalesce(p_specialty, p_series, p_level) || ' (national)')
  returning id into v_cur;

  for e in select * from jsonb_array_elements(p_entries) loop
    select id, subject_type into v_subj, v_type
      from public.subjects where code = (e ->> 'c') and school_id is null;
    if v_subj is null then raise exception 'subject not found: %', (e ->> 'c'); end if;
    i := i + 1;
    insert into public.curriculum_subjects
      (curriculum_id, subject_id, coefficient, weekly_hours, subject_type, sort_order)
    values
      (v_cur, v_subj, (e ->> 'coef')::numeric, nullif((e ->> 'h'), '')::numeric, v_type, i);
    insert into public.subject_coefficient_configurations
      (education_type_id, subsystem, cycle_id, level_id, series_id, specialty_id,
       subject_id, coefficient, source, source_ref)
    values
      (v_et, p_subsystem, v_cy, v_lv, v_sr, v_sp, v_subj, (e ->> 'coef')::numeric,
       'NATIONAL_DEFAULT', 'MINESEC — representative; verify official coefficients');
  end loop;
end;
$$;

-- -----------------------------------------------------------------------------
-- Francophone GENERAL — First cycle
-- -----------------------------------------------------------------------------
select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => '6EME',
  p_entries => '[{"c":"FR","coef":4,"h":5},{"c":"ENG","coef":3,"h":4},{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":2,"h":2},{"c":"SVT","coef":2,"h":2},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => '5EME',
  p_entries => '[{"c":"FR","coef":4,"h":5},{"c":"ENG","coef":3,"h":4},{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":2,"h":2},{"c":"SVT","coef":2,"h":2},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => '4EME',
  p_entries => '[{"c":"FR","coef":4,"h":5},{"c":"ENG","coef":3,"h":4},{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":3,"h":3},{"c":"SVT","coef":2,"h":2},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1}]');

-- -----------------------------------------------------------------------------
-- Francophone GENERAL — Second cycle (2nde is a common year; series from 1ère)
-- -----------------------------------------------------------------------------
select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => '2NDE',
  p_entries => '[{"c":"FR","coef":4,"h":5},{"c":"ENG","coef":3,"h":4},{"c":"MATHS","coef":5,"h":6},{"c":"PHY","coef":4,"h":4},{"c":"SVT","coef":3,"h":3},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"PHILO","coef":2,"h":2},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => '1ERE', p_series => 'A',
  p_entries => '[{"c":"FR","coef":5,"h":6},{"c":"ENG","coef":3,"h":4},{"c":"PHILO","coef":4,"h":4},{"c":"HIST","coef":3,"h":3},{"c":"GEO","coef":3,"h":3},{"c":"MATHS","coef":2,"h":3},{"c":"SVT","coef":2,"h":2},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => '1ERE', p_series => 'C',
  p_entries => '[{"c":"MATHS","coef":6,"h":7},{"c":"PHY","coef":5,"h":5},{"c":"CHM","coef":4,"h":4},{"c":"SVT","coef":4,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":3,"h":3},{"c":"ICT","coef":2,"h":2},{"c":"EPS","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => '1ERE', p_series => 'D',
  p_entries => '[{"c":"MATHS","coef":5,"h":6},{"c":"PHY","coef":4,"h":4},{"c":"CHM","coef":4,"h":4},{"c":"SVT","coef":5,"h":5},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":3,"h":3},{"c":"ICT","coef":2,"h":2},{"c":"EPS","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => '1ERE', p_series => 'TI',
  p_entries => '[{"c":"MATHS","coef":5,"h":6},{"c":"PHY","coef":4,"h":4},{"c":"ICT","coef":5,"h":5},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":3,"h":3},{"c":"CHM","coef":2,"h":2},{"c":"EPS","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => '1ERE', p_series => 'BIL',
  p_entries => '[{"c":"FR","coef":4,"h":5},{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":3,"h":4},{"c":"HIST","coef":3,"h":3},{"c":"GEO","coef":3,"h":3},{"c":"PHILO","coef":3,"h":3},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'TLE', p_series => 'A',
  p_entries => '[{"c":"FR","coef":5,"h":6},{"c":"ENG","coef":3,"h":4},{"c":"PHILO","coef":5,"h":5},{"c":"HIST","coef":3,"h":3},{"c":"GEO","coef":3,"h":3},{"c":"MATHS","coef":2,"h":3},{"c":"SVT","coef":2,"h":2},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'TLE', p_series => 'C',
  p_entries => '[{"c":"MATHS","coef":7,"h":8},{"c":"PHY","coef":6,"h":6},{"c":"CHM","coef":5,"h":5},{"c":"SVT","coef":3,"h":3},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"ICT","coef":2,"h":2},{"c":"EPS","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'TLE', p_series => 'D',
  p_entries => '[{"c":"MATHS","coef":6,"h":7},{"c":"PHY","coef":5,"h":5},{"c":"CHM","coef":5,"h":5},{"c":"SVT","coef":5,"h":5},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"ICT","coef":2,"h":2},{"c":"EPS","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'TLE', p_series => 'TI',
  p_entries => '[{"c":"MATHS","coef":5,"h":6},{"c":"PHY","coef":5,"h":5},{"c":"ICT","coef":6,"h":6},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"CHM","coef":2,"h":2},{"c":"EPS","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'FRANCOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'TLE', p_series => 'BIL',
  p_entries => '[{"c":"FR","coef":4,"h":5},{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":3,"h":4},{"c":"HIST","coef":3,"h":3},{"c":"GEO","coef":3,"h":3},{"c":"PHILO","coef":4,"h":4},{"c":"EPS","coef":2,"h":2},{"c":"ICT","coef":1,"h":1}]');

-- -----------------------------------------------------------------------------
-- Anglophone GENERAL — First cycle
-- -----------------------------------------------------------------------------
select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => 'FORM_1',
  p_entries => '[{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":4,"h":5},{"c":"FR","coef":3,"h":4},{"c":"SVT","coef":2,"h":2},{"c":"PHY","coef":2,"h":2},{"c":"CHM","coef":2,"h":2},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"CIVIC","coef":1,"h":1},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => 'FORM_2',
  p_entries => '[{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":4,"h":5},{"c":"FR","coef":3,"h":4},{"c":"SVT","coef":2,"h":2},{"c":"PHY","coef":2,"h":2},{"c":"CHM","coef":2,"h":2},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"CIVIC","coef":1,"h":1},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => 'FORM_3',
  p_entries => '[{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":4,"h":5},{"c":"FR","coef":3,"h":4},{"c":"SVT","coef":3,"h":3},{"c":"PHY","coef":3,"h":3},{"c":"CHM","coef":2,"h":2},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"CIVIC","coef":1,"h":1},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => 'FORM_4',
  p_entries => '[{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":4,"h":5},{"c":"FR","coef":3,"h":4},{"c":"SVT","coef":3,"h":3},{"c":"PHY","coef":3,"h":3},{"c":"CHM","coef":3,"h":3},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"CIVIC","coef":1,"h":1},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'FIRST_CYCLE', p_level => 'FORM_5',
  p_entries => '[{"c":"ENG","coef":4,"h":5},{"c":"MATHS","coef":4,"h":5},{"c":"FR","coef":3,"h":4},{"c":"SVT","coef":3,"h":3},{"c":"PHY","coef":3,"h":3},{"c":"CHM","coef":3,"h":3},{"c":"HIST","coef":2,"h":2},{"c":"GEO","coef":2,"h":2},{"c":"CIVIC","coef":1,"h":1},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

-- -----------------------------------------------------------------------------
-- Anglophone GENERAL — Second cycle (streams: ARTS / SCI)
-- -----------------------------------------------------------------------------
select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'LOWER_SIXTH', p_series => 'ARTS',
  p_entries => '[{"c":"ENG","coef":5,"h":6},{"c":"FR","coef":3,"h":4},{"c":"HIST","coef":3,"h":3},{"c":"GEO","coef":3,"h":3},{"c":"LIT","coef":3,"h":3},{"c":"ECON","coef":3,"h":3},{"c":"MATHS","coef":2,"h":3},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'LOWER_SIXTH', p_series => 'SCI',
  p_entries => '[{"c":"MATHS","coef":5,"h":6},{"c":"PHY","coef":4,"h":4},{"c":"CHM","coef":4,"h":4},{"c":"SVT","coef":3,"h":3},{"c":"ENG","coef":4,"h":5},{"c":"FR","coef":2,"h":3},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'UPPER_SIXTH', p_series => 'ARTS',
  p_entries => '[{"c":"ENG","coef":5,"h":6},{"c":"FR","coef":3,"h":4},{"c":"HIST","coef":3,"h":3},{"c":"GEO","coef":3,"h":3},{"c":"LIT","coef":4,"h":4},{"c":"ECON","coef":3,"h":3},{"c":"EPS","coef":1,"h":1},{"c":"MATHS","coef":1,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'GENERAL', p_subsystem => 'ANGLOPHONE',
  p_cycle => 'SECOND_CYCLE', p_level => 'UPPER_SIXTH', p_series => 'SCI',
  p_entries => '[{"c":"MATHS","coef":6,"h":7},{"c":"PHY","coef":5,"h":5},{"c":"CHM","coef":5,"h":5},{"c":"SVT","coef":4,"h":4},{"c":"ENG","coef":4,"h":5},{"c":"FR","coef":2,"h":3},{"c":"ICT","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

-- -----------------------------------------------------------------------------
-- TECHNICAL — First cycle (common technical curriculum, no stream)
-- -----------------------------------------------------------------------------
select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'FIRST_CYCLE', p_level => 'TECH_Y1',
  p_entries => '[{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":3,"h":3},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"GEN","coef":2,"h":2},{"c":"DRAW","coef":2,"h":2},{"c":"PRAC","coef":3,"h":3},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'FIRST_CYCLE', p_level => 'TECH_Y2',
  p_entries => '[{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":3,"h":3},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"GEN","coef":2,"h":2},{"c":"DRAW","coef":2,"h":2},{"c":"PRAC","coef":3,"h":3},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'FIRST_CYCLE', p_level => 'TECH_Y3',
  p_entries => '[{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":3,"h":3},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"GEN","coef":2,"h":2},{"c":"DRAW","coef":3,"h":3},{"c":"PRAC","coef":4,"h":4},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'FIRST_CYCLE', p_level => 'TECH_Y4',
  p_entries => '[{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":3,"h":3},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"GEN","coef":2,"h":2},{"c":"DRAW","coef":3,"h":3},{"c":"PRAC","coef":4,"h":4},{"c":"ICT","coef":1,"h":1},{"c":"CIVIC","coef":1,"h":1},{"c":"EPS","coef":1,"h":1}]');

-- -----------------------------------------------------------------------------
-- TECHNICAL — Second cycle
-- -----------------------------------------------------------------------------
select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_1ERE', p_series => 'STT',
  p_entries => '[{"c":"MATHS","coef":4,"h":5},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"ACCT","coef":3,"h":3},{"c":"MGMT","coef":2,"h":2},{"c":"ECON","coef":2,"h":2},{"c":"GEN","coef":2,"h":2},{"c":"ICT","coef":2,"h":2},{"c":"PRAC","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_1ERE', p_series => 'IND',
  p_entries => '[{"c":"MATHS","coef":4,"h":5},{"c":"PHY","coef":4,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"DRAW","coef":3,"h":3},{"c":"PRAC","coef":4,"h":4},{"c":"GEN","coef":2,"h":2},{"c":"ICT","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_TLE', p_series => 'STT', p_specialty => 'GCA',
  p_entries => '[{"c":"ACCT","coef":5,"h":5},{"c":"MGMT","coef":4,"h":4},{"c":"ECON","coef":3,"h":3},{"c":"MATHS","coef":3,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"LAW","coef":2,"h":2},{"c":"ICT","coef":2,"h":2},{"c":"PRAC","coef":2,"h":2},{"c":"GEN","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_TLE', p_series => 'STT', p_specialty => 'SESC',
  p_entries => '[{"c":"ECON","coef":5,"h":5},{"c":"MGMT","coef":4,"h":4},{"c":"ACCT","coef":2,"h":2},{"c":"MATHS","coef":3,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"GEN","coef":2,"h":2},{"c":"ICT","coef":2,"h":2},{"c":"LAW","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_TLE', p_series => 'STT', p_specialty => 'TCA',
  p_entries => '[{"c":"COMM","coef":5,"h":5},{"c":"MGMT","coef":4,"h":4},{"c":"ACCT","coef":3,"h":3},{"c":"ECON","coef":2,"h":2},{"c":"MATHS","coef":3,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"ICT","coef":2,"h":2},{"c":"GEN","coef":2,"h":2}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_TLE', p_series => 'IND', p_specialty => 'ELECTRO',
  p_entries => '[{"c":"ELEC","coef":5,"h":5},{"c":"PRAC","coef":4,"h":4},{"c":"MATHS","coef":3,"h":4},{"c":"PHY","coef":4,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"DRAW","coef":2,"h":2},{"c":"ICT","coef":1,"h":1},{"c":"GEN","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_TLE', p_series => 'IND', p_specialty => 'MECA',
  p_entries => '[{"c":"MEC","coef":5,"h":5},{"c":"PRAC","coef":4,"h":4},{"c":"MATHS","coef":3,"h":4},{"c":"PHY","coef":4,"h":4},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"DRAW","coef":2,"h":2},{"c":"ICT","coef":1,"h":1},{"c":"GEN","coef":1,"h":1}]');

select public.tmp_seed_national_curriculum(
  p_education_type => 'TECHNICAL', p_subsystem => null,
  p_cycle => 'SECOND_CYCLE', p_level => 'TECH_TLE', p_series => 'IND', p_specialty => 'GENIE_CIVIL',
  p_entries => '[{"c":"GCIV","coef":5,"h":5},{"c":"PRAC","coef":4,"h":4},{"c":"DRAW","coef":3,"h":3},{"c":"MATHS","coef":3,"h":4},{"c":"PHY","coef":3,"h":3},{"c":"FR","coef":3,"h":4},{"c":"ENG","coef":2,"h":3},{"c":"ICT","coef":1,"h":1},{"c":"GEN","coef":1,"h":1}]');

-- -----------------------------------------------------------------------------
-- Cleanup: the seeding helper is a one-off.
-- -----------------------------------------------------------------------------
drop function if exists public.tmp_seed_national_curriculum(text, text, text, text, text, text, jsonb);