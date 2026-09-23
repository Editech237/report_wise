-- A report card may only be recorded for a complete TERM result.  This keeps
-- the academic gate effective even if a client bypasses the Flutter UI.
create or replace function public.report_card_ready(p_result uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.period_results pr
    where pr.id = p_result
      and pr.period_type = 'TERM'
      and public.is_school_admin(pr.school_id)
      and not exists (
        select 1
        from public.student_enrollments e
        where e.school_id = pr.school_id
          and e.class_id = pr.class_id
          and e.academic_year_id = pr.academic_year_id
          and not exists (
            select 1 from public.period_results term_result
            where term_result.school_id = pr.school_id
              and term_result.class_id = pr.class_id
              and term_result.academic_year_id = pr.academic_year_id
              and term_result.student_enrollment_id = e.id
              and term_result.period_type = 'TERM'
              and term_result.period_id = pr.period_id
              and exists (
                select 1 from public.subject_results sr
                where sr.period_result_id = term_result.id
              )
          )
      )
      and 2 = (
        select count(*) from public.sequences s
        join public.terms t on t.id = s.term_id
        where t.id = pr.period_id
      )
      and not exists (
        select 1
        from public.sequences s
        join public.terms t on t.id = s.term_id
        join public.student_enrollments e
          on e.school_id = pr.school_id
         and e.class_id = pr.class_id
         and e.academic_year_id = pr.academic_year_id
        where t.id = pr.period_id
          and not exists (
            select 1 from public.period_results sequence_result
            where sequence_result.school_id = pr.school_id
              and sequence_result.class_id = pr.class_id
              and sequence_result.academic_year_id = pr.academic_year_id
              and sequence_result.student_enrollment_id = e.id
              and sequence_result.period_type = 'SEQUENCE'
              and sequence_result.period_id = s.id
              and exists (
                select 1 from public.subject_results sr
                where sr.period_result_id = sequence_result.id
              )
          )
      )
  );
$$;

drop policy if exists "report_cards_insert" on public.report_cards;
create policy "report_cards_insert" on public.report_cards
  for insert with check (
    public.is_school_admin(school_id)
    and public.report_card_ready(period_result_id)
  );
