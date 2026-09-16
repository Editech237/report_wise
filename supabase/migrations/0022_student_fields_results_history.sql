-- =============================================================================
-- ReportWise — Migration 0022
-- Additional student identity fields (report-card header) + results history.
--
-- Report cards need: place of birth, parent/guardian name + contact, and a
-- repeater flag. The list_period_result_sets RPC powers the "computed results"
-- history strip (like the mark-book history): each computed period per class
-- can be reopened without re-picking class + sequence.
-- =============================================================================

-- ----- student identity fields -----
alter table public.students
  add column if not exists place_of_birth text,
  add column if not exists guardian_name text,
  add column if not exists guardian_phone text,
  add column if not exists repeater boolean not null default false;

-- ----- results history -----
create or replace function public.list_period_result_sets(p_school uuid, p_year uuid)
returns table (
  class_id      uuid,
  class_name    text,
  period_type   text,
  period_id     uuid,
  period_label  text,
  student_count bigint,
  status        text
)
language sql
stable
security definer
set search_path = public
as $$
  select pr.class_id,
         c.name,
         pr.period_type,
         pr.period_id,
         case pr.period_type
           when 'SEQUENCE' then coalesce((select s.name from public.sequences s where s.id = pr.period_id), 'Sequence')
           when 'TERM'     then coalesce((select t.name from public.terms t where t.id = pr.period_id), 'Term')
           else 'Annual'
         end,
         count(*)::bigint,
         max(pr.status)
  from public.period_results pr
  join public.classes c on c.id = pr.class_id
  where pr.school_id = p_school
    and pr.academic_year_id = p_year
    and public.is_school_member(p_school)
  group by pr.class_id, c.name, pr.period_type, pr.period_id
  order by c.name, pr.period_type, pr.period_id;
$$;