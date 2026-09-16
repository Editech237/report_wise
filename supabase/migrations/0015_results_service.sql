-- =============================================================================
-- ReportWise — Migration 0015
-- Results computation service & ranking (spec sections 15, 16-17, 26, 30, 44).
--
-- compute_period_results is the server-side domain engine for results. Given a
-- class + period (SEQUENCE | TERM | ANNUAL) and the academic configuration that
-- applies to that class (resolved subjects/coefficients, assessment scheme,
-- missing-mark policy, ranking rule, display precision — all passed as JSON
-- and stored in config_snapshot for reproducibility), it:
--
--   1. computes each student's per-subject average from mark entries
--      (weighted scheme components, excluded statuses, /20 normalization),
--   2. computes weighted points (subject_average × coefficient) and the
--      coefficient-weighted general average,
--   3. computes the class average and ranks students (competition / dense /
--      sequential with tie-break),
--   4. persists period_results + subject_results atomically (DRAFT), carrying
--      the full config_snapshot so historical results stay reproducible.
--
-- TERM aggregates the term's sequence results (mean of sequence averages and
-- mean of sequence subject averages). ANNUAL aggregates the year's term results
-- (mean of term averages). Both follow the stored academic rules.
--
-- Finalized results are immutable (Phase-0 triggers); unfinalize_period_results
-- is an audited, admin-only correction path.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Allow an administrator to unfinalize results (audited correction path).
-- The Phase-0 immutability trigger is replaced to permit FINAL → DRAFT only
-- when the unfinalize RPC has set the transaction-local flag.
-- -----------------------------------------------------------------------------
create or replace function public.period_results_immutable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'FINAL' then
    if new.status = 'DRAFT'
       and coalesce(current_setting('reportwise.unfinalize', true), '') = '1' then
      return new;
    end if;
    raise exception 'Finalized period results are immutable';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Finalize all DRAFT results of a period (admin only). Finalized results can
-- no longer be edited or deleted.
-- -----------------------------------------------------------------------------
create or replace function public.finalize_period_results(
  p_class       uuid,
  p_period_type text,
  p_period_id   uuid
)
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
    raise exception 'Only an administrator can finalize results';
  end if;
  if p_period_type not in ('SEQUENCE','TERM','ANNUAL') then
    raise exception 'Invalid period type';
  end if;

  update public.period_results
    set status = 'FINAL', calculated_at = now()
  where class_id = p_class and period_type = p_period_type
    and period_id is not distinct from p_period_id
    and status = 'DRAFT';

  if not found then
    raise exception 'No DRAFT results to finalize for this period';
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- Unfinalize a period's results so they can be recomputed after corrections.
-- Audited; a reason is required.
-- -----------------------------------------------------------------------------
create or replace function public.unfinalize_period_results(
  p_class       uuid,
  p_period_type text,
  p_period_id   uuid,
  p_reason      text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'A reason is required to unfinalize results';
  end if;
  select school_id into v_school from public.classes where id = p_class;
  if v_school is null then raise exception 'Class not found'; end if;
  if not public.is_school_admin(v_school) then
    raise exception 'Only an administrator can unfinalize results';
  end if;

  perform set_config('reportwise.unfinalize', '1', true);
  update public.period_results
    set status = 'DRAFT', calculated_at = now()
  where class_id = p_class and period_type = p_period_type
    and period_id is not distinct from p_period_id
    and status = 'FINAL';
  perform set_config('reportwise.unfinalize', '', true);

  insert into public.academic_config_audit
    (school_id, actor_profile_id, entity_type, field_name, new_value)
  values
    (v_school, auth.uid(), 'PERIOD_RESULTS', 'unfinalized',
     jsonb_build_object('period_type', p_period_type, 'period_id', p_period_id, 'reason', trim(p_reason)));
end;
$$;

-- -----------------------------------------------------------------------------
-- The results computation service.
-- -----------------------------------------------------------------------------
create or replace function public.compute_period_results(
  p_school       uuid,
  p_class        uuid,
  p_year         uuid,
  p_period_type  text,      -- SEQUENCE | TERM | ANNUAL
  p_period_id    uuid,      -- sequence.id / term.id / null for ANNUAL
  p_sequence_ids uuid[],    -- sequences whose marks/results feed this period
  p_subjects     jsonb,     -- [{subject_id, coefficient, counts_in_average, counts_in_ranking, shows_on_report}]
  p_scheme       jsonb,     -- [{id, weight, max_score}]  (weight as fraction 0..1)
  p_policy       jsonb,     -- {exclude: [codes], zero_is_score}
  p_ranking      jsonb,     -- {method, tie_breaker, same_rank_for_ties}
  p_display      jsonb      -- {decimals, rounding}
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_excluded     text[];
  v_zero_is_score boolean;
  v_method       text;
  v_tie          text;
  v_snapshot     jsonb;
  v_meta_class_avg numeric;
  v_decimals     int;
  v_term_seq     uuid[];
  v_year_terms   uuid[];
begin
  -- ---------- validation ----------
  if not public.is_school_admin(p_school) then
    raise exception 'Only an administrator can compute results';
  end if;
  if not exists (
    select 1 from public.classes where id = p_class and school_id = p_school and academic_year_id = p_year
  ) then
    raise exception 'Class not found in this school/year';
  end if;
  if p_period_type not in ('SEQUENCE','TERM','ANNUAL') then
    raise exception 'Invalid period type';
  end if;
  if p_period_type in ('SEQUENCE','TERM') and p_period_id is null then
    raise exception 'This period type requires a period id';
  end if;
  if p_period_type = 'SEQUENCE' and (p_sequence_ids is null or array_length(p_sequence_ids,1) = 0) then
    raise exception 'A sequence period requires its sequence id';
  end if;
  if p_subjects is null or jsonb_array_length(p_subjects) = 0 then
    raise exception 'No resolved subjects provided';
  end if;
  if p_scheme is null or jsonb_array_length(p_scheme) = 0 then
    raise exception 'No resolved assessment scheme provided';
  end if;

  -- ---------- immutability ----------
  if exists (
    select 1 from public.period_results
    where school_id = p_school and class_id = p_class
      and period_type = p_period_type
      and period_id is not distinct from p_period_id
      and status = 'FINAL'
  ) then
    raise exception 'Finalized results exist for this period; unfinalize them first';
  end if;

  -- ---------- clear stale DRAFT results ----------
  drop table if exists t_subj_avg, t_gen, t_ranked, t_meta, t_pr;
  delete from public.subject_results sr using public.period_results pr
    where sr.period_result_id = pr.id
      and pr.school_id = p_school and pr.class_id = p_class
      and pr.period_type = p_period_type
      and pr.period_id is not distinct from p_period_id;
  delete from public.period_results
    where school_id = p_school and class_id = p_class
      and period_type = p_period_type
      and period_id is not distinct from p_period_id;

  -- ---------- config snapshot ----------
  v_snapshot := jsonb_build_object(
    'subjects', p_subjects,
    'scheme', p_scheme,
    'policy', p_policy,
    'ranking', p_ranking,
    'display', p_display,
    'computed_at', now()
  );

  v_excluded := coalesce(
    (select array_agg(x) from jsonb_array_elements_text(p_policy -> 'exclude') x), '{}');
  v_zero_is_score := coalesce((p_policy ->> 'zero_is_score')::boolean, true);
  v_method := coalesce(p_ranking ->> 'method', 'COMPETITION');
  v_tie    := coalesce(p_ranking ->> 'tie_breaker', 'TOTAL_WEIGHTED_POINTS');
  v_decimals := coalesce((p_display ->> 'decimals')::int, 2);

  -- =====================================================================
  -- SEQUENCE: subject averages straight from mark entries.
  -- =====================================================================
  if p_period_type = 'SEQUENCE' then
    create temp table t_subj_avg on commit drop as
    with book as (
      select distinct on (class_id, subject_id, sequence_id) id
      from public.mark_books
      where class_id = p_class and school_id = p_school
        and sequence_id = any(p_sequence_ids)
      order by class_id, subject_id, sequence_id, created_at
    ),
    ent as (
      select me.student_enrollment_id, mb.subject_id, me.scheme_component_id,
             me.score, me.absence_status
      from public.mark_entries me
      join public.mark_books mb on mb.id = me.mark_book_id
      where me.school_id = p_school and mb.id in (select id from book)
    ),
    comp as (
      select (c ->> 'id')::uuid as id,
             (c ->> 'weight')::numeric as weight,
             (c ->> 'max_score')::numeric as max_score
      from jsonb_array_elements(p_scheme) c
    ),
    subj as (
      select (s ->> 'subject_id')::uuid as subject_id,
             (s ->> 'coefficient')::numeric as coefficient,
             coalesce((s ->> 'counts_in_average')::boolean, true) as counts_in_average,
             coalesce((s ->> 'counts_in_ranking')::boolean, true) as counts_in_ranking,
             coalesce((s ->> 'shows_on_report')::boolean, true) as shows_on_report
      from jsonb_array_elements(p_subjects) s
    ),
    grid as (
      select se.id as student_enrollment_id, subj.subject_id, comp.id as component_id,
             comp.weight, comp.max_score, subj.coefficient,
             subj.counts_in_average, subj.counts_in_ranking, subj.shows_on_report
      from public.student_enrollments se
      cross join subj
      cross join comp
      where se.class_id = p_class and se.academic_year_id = p_year
        and se.school_id = p_school
    ),
    joined as (
      select g.*, e.score, e.absence_status,
             coalesce(e.absence_status, 'NOT_ENTERED') as status
      from grid g
      left join ent e
        on e.student_enrollment_id = g.student_enrollment_id
       and e.subject_id = g.subject_id
       and e.scheme_component_id = g.component_id
    ),
    included as (
      select joined.*,
             case when joined.status = any(v_excluded) then 0 else 1 end as inc
      from joined
    ),
    scored as (
      select student_enrollment_id, subject_id,
             sum(case when inc = 1 then
                   (case when status = 'ZERO' then 0 else coalesce(score, 0) end)
                   / nullif(max_score, 0) * 20 * weight
                 end) as wsum,
             sum(case when inc = 1 then weight end) as wtotal,
             count(case when inc = 1 then 1 end) as marks_count
      from included
      group by student_enrollment_id, subject_id
    )
    select sc.student_enrollment_id, sc.subject_id,
           case when sc.wtotal > 0 then sc.wsum / sc.wtotal end as subject_average,
           g.coefficient, g.counts_in_average, g.counts_in_ranking, g.shows_on_report,
           sc.marks_count
    from scored sc
    join (
      select distinct student_enrollment_id, subject_id, coefficient,
             counts_in_average, counts_in_ranking, shows_on_report
      from grid
    ) g
      on g.student_enrollment_id = sc.student_enrollment_id
     and g.subject_id = sc.subject_id;

    create temp table t_gen on commit drop as
    select student_enrollment_id,
           sum(coalesce(subject_average, 0) * coefficient) as total_points,
           sum(coefficient) as total_coefficients,
           case when sum(coefficient) > 0
                then sum(coalesce(subject_average, 0) * coefficient) / sum(coefficient)
           end as general_average
    from t_subj_avg
    where subject_average is not null and counts_in_average
    group by student_enrollment_id;
  end if;

  -- =====================================================================
  -- TERM: aggregate the term's sequence results.
  -- =====================================================================
  if p_period_type = 'TERM' then
    select coalesce(array_agg(id), '{}') into v_term_seq
      from public.sequences where term_id = p_period_id;
    if array_length(v_term_seq, 1) = 0 then
      raise exception 'Term has no sequences';
    end if;

    create temp table t_subj_avg on commit drop as
    select r.student_enrollment_id, r.subject_id,
           avg(r.subject_average) as subject_average,
           subj.coefficient, subj.counts_in_average, subj.counts_in_ranking,
           subj.shows_on_report,
           count(r.subject_average) as marks_count
    from (
      select pr.student_enrollment_id, sr.subject_id, sr.subject_average
      from public.period_results pr
      join public.subject_results sr on sr.period_result_id = pr.id
      where pr.school_id = p_school and pr.class_id = p_class
        and pr.period_type = 'SEQUENCE'
        and pr.period_id = any(v_term_seq)
    ) r
    join (
      select (s ->> 'subject_id')::uuid as subject_id,
             (s ->> 'coefficient')::numeric as coefficient,
             coalesce((s ->> 'counts_in_average')::boolean, true) as counts_in_average,
             coalesce((s ->> 'counts_in_ranking')::boolean, true) as counts_in_ranking,
             coalesce((s ->> 'shows_on_report')::boolean, true) as shows_on_report
      from jsonb_array_elements(p_subjects) s
    ) subj on subj.subject_id = r.subject_id
    group by r.student_enrollment_id, r.subject_id, subj.coefficient,
             subj.counts_in_average, subj.counts_in_ranking, subj.shows_on_report;

    create temp table t_gen on commit drop as
    select g.student_enrollment_id, g.total_points, g.total_coefficients,
           seq.term_general as general_average
    from (
      select student_enrollment_id,
             sum(coalesce(subject_average, 0) * coefficient) as total_points,
             sum(coefficient) as total_coefficients
      from t_subj_avg
      where subject_average is not null and counts_in_average
      group by student_enrollment_id
    ) g
    join (
      select student_enrollment_id, avg(general_average) as term_general
      from public.period_results
      where school_id = p_school and class_id = p_class
        and period_type = 'SEQUENCE'
        and period_id = any(v_term_seq)
        and general_average is not null
      group by student_enrollment_id
    ) seq on seq.student_enrollment_id = g.student_enrollment_id;
  end if;

  -- =====================================================================
  -- ANNUAL: aggregate the year's term results.
  -- =====================================================================
  if p_period_type = 'ANNUAL' then
    select coalesce(array_agg(id), '{}') into v_year_terms
      from public.terms where academic_year_id = p_year;
    if array_length(v_year_terms, 1) = 0 then
      raise exception 'Academic year has no terms';
    end if;

    create temp table t_subj_avg on commit drop as
    select r.student_enrollment_id, r.subject_id,
           avg(r.subject_average) as subject_average,
           subj.coefficient, subj.counts_in_average, subj.counts_in_ranking,
           subj.shows_on_report,
           count(r.subject_average) as marks_count
    from (
      select pr.student_enrollment_id, sr.subject_id, sr.subject_average
      from public.period_results pr
      join public.subject_results sr on sr.period_result_id = pr.id
      where pr.school_id = p_school and pr.class_id = p_class
        and pr.period_type = 'TERM'
        and pr.period_id = any(v_year_terms)
    ) r
    join (
      select (s ->> 'subject_id')::uuid as subject_id,
             (s ->> 'coefficient')::numeric as coefficient,
             coalesce((s ->> 'counts_in_average')::boolean, true) as counts_in_average,
             coalesce((s ->> 'counts_in_ranking')::boolean, true) as counts_in_ranking,
             coalesce((s ->> 'shows_on_report')::boolean, true) as shows_on_report
      from jsonb_array_elements(p_subjects) s
    ) subj on subj.subject_id = r.subject_id
    group by r.student_enrollment_id, r.subject_id, subj.coefficient,
             subj.counts_in_average, subj.counts_in_ranking, subj.shows_on_report;

    create temp table t_gen on commit drop as
    select g.student_enrollment_id, g.total_points, g.total_coefficients,
           seq.annual_general as general_average
    from (
      select student_enrollment_id,
             sum(coalesce(subject_average, 0) * coefficient) as total_points,
             sum(coefficient) as total_coefficients
      from t_subj_avg
      where subject_average is not null and counts_in_average
      group by student_enrollment_id
    ) g
    join (
      select student_enrollment_id, avg(general_average) as annual_general
      from public.period_results
      where school_id = p_school and class_id = p_class
        and period_type = 'TERM'
        and period_id = any(v_year_terms)
        and general_average is not null
      group by student_enrollment_id
    ) seq on seq.student_enrollment_id = g.student_enrollment_id;
  end if;

  -- =====================================================================
  -- Common: class average, ranking, persistence.
  -- =====================================================================
  create temp table t_meta on commit drop as
  select avg(general_average) as class_average
  from t_gen where general_average is not null;

  if v_method = 'SEQUENTIAL' then
    create temp table t_ranked on commit drop as
    select g.student_enrollment_id, g.general_average, g.total_points,
           row_number() over (
             order by g.general_average desc nulls last,
                      case when v_tie = 'NONE' then 0 else g.total_points end desc nulls last,
                      g.student_enrollment_id
           ) as rnk
    from t_gen g;
  else
    create temp table t_ranked on commit drop as
    select g.student_enrollment_id, g.general_average, g.total_points,
           case when v_method = 'DENSE'
                then dense_rank() over (order by g.general_average desc nulls last)
                else rank() over (order by g.general_average desc nulls last)
           end as rnk
    from t_gen g;
  end if;

  create temp table t_pr on commit drop as
  with ins as (
    insert into public.period_results
      (school_id, academic_year_id, class_id, student_enrollment_id, period_type, period_id,
       general_average, total_weighted_points, total_coefficients, class_average, rank,
       tie_break_info, config_snapshot, status, calculated_at)
    select
      p_school, p_year, p_class, g.student_enrollment_id, p_period_type, p_period_id,
      g.general_average, g.total_points, g.total_coefficients,
      (select class_average from t_meta),
      r.rnk,
      jsonb_build_object('tie_break_metric', 'TOTAL_WEIGHTED_POINTS', 'value', g.total_points),
      v_snapshot,
      'DRAFT',
      now()
    from t_gen g
    join t_ranked r on r.student_enrollment_id = g.student_enrollment_id
    returning *
  )
  select * from ins;

  insert into public.subject_results
    (school_id, period_result_id, subject_id, subject_average, coefficient,
     weighted_points, marks_count, rank_in_subject)
  select
    p_school, pr.id, sa.subject_id,
    sa.subject_average, sa.coefficient,
    case when sa.subject_average is not null then sa.subject_average * sa.coefficient end,
    sa.marks_count,
    rank() over (partition by sa.subject_id order by sa.subject_average desc nulls last)
  from t_subj_avg sa
  join t_pr pr on pr.student_enrollment_id = sa.student_enrollment_id
  where sa.subject_average is not null;

  drop table if exists t_subj_avg, t_gen, t_ranked, t_meta, t_pr;
end;
$$;