-- =============================================================================
-- ReportWise — Migration 0018
-- Real dashboard metrics (replaces the hardcoded pass-rate and activity).
--
-- dashboard_metrics returns, for a school + academic year:
--   * pass_rate.overall  — mean pass rate across classes (latest SEQUENCE
--     results), using the Cameroonian 10/20 pass threshold by default.
--   * pass_rate.classes  — per-class pass rate for the latest sequence.
--   * activity           — recent real events (student enrollments, mark book
--     status changes, academic configuration changes), newest first.
--
-- When no results exist, pass_rate is null and classes is empty — the UI shows
-- an honest "no data yet" state instead of fabricated numbers.
-- =============================================================================

create or replace function public.dashboard_metrics(
  p_school    uuid,
  p_year      uuid,
  p_threshold numeric default 10,
  p_limit     int default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pass     jsonb;
  v_activity jsonb;
begin
  if not public.is_school_member(p_school) then
    raise exception 'Not a member of this school';
  end if;

  -- ----- pass rate from the latest sequence results per class -----
  with latest_seq as (
    select distinct on (class_id) class_id, period_id
    from public.period_results
    where school_id = p_school and academic_year_id = p_year
      and period_type = 'SEQUENCE'
    order by class_id, calculated_at desc
  ),
  per_class as (
    select pr.class_id,
           count(*) filter (where pr.general_average >= p_threshold) as passed,
           count(*) as total
    from public.period_results pr
    join latest_seq l
      on l.class_id = pr.class_id and l.period_id = pr.period_id
    where pr.school_id = p_school and pr.period_type = 'SEQUENCE'
      and pr.general_average is not null
    group by pr.class_id
  )
  select jsonb_build_object(
    'classes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'class_id', pc.class_id,
        'class_name', c.name,
        'total', pc.total,
        'passed', pc.passed,
        'pass_rate', round(pc.passed::numeric / pc.total * 100, 1)
      ) order by c.name)
      from per_class pc
      join public.classes c on c.id = pc.class_id
    ), '[]'),
    'overall', (
      select round(avg(pc.passed::numeric / pc.total * 100), 1) from per_class pc
    )
  ) into v_pass;

  -- ----- recent real activity -----
  with acts as (
    select 'enrollment' as kind,
           ('Enrolled ' || s.full_name || ' in ' || c.name) as title,
           se.created_at as created_at
    from public.student_enrollments se
    join public.students s on s.id = se.student_id
    join public.classes c on c.id = se.class_id
    where se.school_id = p_school and se.academic_year_id = p_year
    union all
    select 'mark' as kind,
           (initcap(lower(e.action)) || ' marks · ' || c.name || ' · ' || sub.name) as title,
           e.created_at as created_at
    from public.mark_book_events e
    join public.mark_books mb on mb.id = e.mark_book_id
    join public.classes c on c.id = mb.class_id
    join public.subjects sub on sub.id = mb.subject_id
    where e.school_id = p_school
    union all
    select 'config' as kind,
           ('Updated ' || lower(replace(a.entity_type, '_', ' '))) as title,
           a.created_at as created_at
    from public.academic_config_audit a
    where a.school_id = p_school
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', kind, 'title', title, 'created_at', created_at
  ) order by created_at desc), '[]')
  into v_activity
  from (select kind, title, created_at from acts order by created_at desc limit p_limit) t;

  return jsonb_build_object('pass_rate', v_pass, 'activity', v_activity);
end;
$$;