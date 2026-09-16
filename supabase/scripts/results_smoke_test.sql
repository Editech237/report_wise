-- Scratch validation of compute_period_results (rolled back; nothing persists).
-- Expected: student A = (14*5 + 12*4)/9 = 13.11, student B = (10*5 + 15*4)/9 = 12.22
-- Run: supabase db query --linked -f supabase/scripts/results_smoke_test.sql
begin;

-- use the caller's real profile as the acting administrator
create temp table _admin on commit drop as
  select id from public.profiles order by created_at limit 1;

select set_config('request.jwt.claims',
  (select jsonb_build_object('sub', id::text, 'role', 'authenticated')::text from _admin),
  false);

insert into public.schools (id, name, school_type, subsystem)
values ('10000000-0000-0000-0000-000000000001', 'Scratch School', 'GENERAL', 'FRANCOPHONE');

insert into public.school_memberships (school_id, profile_id, role)
values ('10000000-0000-0000-0000-000000000001', (select id from _admin), 'SUPER_ADMIN');

insert into public.academic_years (id, school_id, name, is_current)
values ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '2026/2027', true);

insert into public.terms (id, school_id, academic_year_id, number, name)
values ('21000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', 1, 'Term 1');

insert into public.sequences (id, school_id, term_id, number, name, status)
values ('22000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
        '21000000-0000-0000-0000-000000000001', 1, 'Sequence 1', 'OPEN');

-- class on the national 3ème level
insert into public.classes (id, school_id, academic_year_id, subsystem, education_type_id, cycle_id, level_id, name)
select '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001', 'FRANCOPHONE', et.id, cy.id, lv.id, '3ème A'
from public.levels lv
join public.cycles cy on cy.id = lv.cycle_id
join public.education_types et on et.id = cy.education_type_id
where et.code='GENERAL' and cy.code='FIRST_CYCLE' and lv.code='3EME'
limit 1;

-- two students
insert into public.students (id, school_id, full_name)
values ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Student A'),
       ('40000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'Student B');

insert into public.student_enrollments (id, school_id, student_id, academic_year_id, class_id, status)
values ('41000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001', 'ENROLLED'),
       ('41000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
        '40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001', 'ENROLLED');

-- assignments point at the admin's membership (no second user needed here)
insert into public.teacher_assignments (id, school_id, academic_year_id, teacher_membership_id, class_id, subject_id)
select '51000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001', sm.id,
       '30000000-0000-0000-0000-000000000001', s.id
from public.school_memberships sm, public.subjects s
where sm.school_id='10000000-0000-0000-0000-000000000001'
  and s.code='MATHS' and s.school_id is null;

insert into public.teacher_assignments (id, school_id, academic_year_id, teacher_membership_id, class_id, subject_id)
select '51000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001', sm.id,
       '30000000-0000-0000-0000-000000000001', s.id
from public.school_memberships sm, public.subjects s
where sm.school_id='10000000-0000-0000-0000-000000000001'
  and s.code='PHY' and s.school_id is null;

-- scratch assessment scheme + single exam component (weight 100)
insert into public.assessment_schemes (id, school_id, name, source)
values ('23000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Scratch Exam', 'SCHOOL_CONFIGURATION');
insert into public.assessment_scheme_components (id, scheme_id, school_id, name, component_type, weight, max_score)
values ('24000000-0000-0000-0000-000000000001', '23000000-0000-0000-0000-000000000001',
        '10000000-0000-0000-0000-000000000001', 'Exam', 'EXAM', 100, 20);

-- mark books (one per subject)
insert into public.mark_books (id, school_id, academic_year_id, teacher_assignment_id, class_id, subject_id, sequence_id, status)
values ('60000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001', (select id from public.subjects where code='MATHS' and school_id is null),
        '22000000-0000-0000-0000-000000000001', 'DRAFT'),
       ('60000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001',
        '20000000-0000-0000-0000-000000000001', '51000000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-000000000001', (select id from public.subjects where code='PHY' and school_id is null),
        '22000000-0000-0000-0000-000000000001', 'DRAFT');

-- mark entries: A (14, 12), B (10, 15)
insert into public.mark_entries (school_id, mark_book_id, student_enrollment_id, scheme_component_id, score, absence_status)
select '10000000-0000-0000-0000-000000000001', mb.id, se.id, '24000000-0000-0000-0000-000000000001', 14, 'ENTERED'
from public.mark_books mb, public.student_enrollments se
where mb.class_id='30000000-0000-0000-0000-000000000001'
  and mb.subject_id=(select id from public.subjects where code='MATHS' and school_id is null)
  and se.id='41000000-0000-0000-0000-000000000001';

insert into public.mark_entries (school_id, mark_book_id, student_enrollment_id, scheme_component_id, score, absence_status)
select '10000000-0000-0000-0000-000000000001', mb.id, se.id, '24000000-0000-0000-0000-000000000001', 12, 'ENTERED'
from public.mark_books mb, public.student_enrollments se
where mb.class_id='30000000-0000-0000-0000-000000000001'
  and mb.subject_id=(select id from public.subjects where code='PHY' and school_id is null)
  and se.id='41000000-0000-0000-0000-000000000001';

insert into public.mark_entries (school_id, mark_book_id, student_enrollment_id, scheme_component_id, score, absence_status)
select '10000000-0000-0000-0000-000000000001', mb.id, se.id, '24000000-0000-0000-0000-000000000001', 10, 'ENTERED'
from public.mark_books mb, public.student_enrollments se
where mb.class_id='30000000-0000-0000-0000-000000000001'
  and mb.subject_id=(select id from public.subjects where code='MATHS' and school_id is null)
  and se.id='41000000-0000-0000-0000-000000000002';

insert into public.mark_entries (school_id, mark_book_id, student_enrollment_id, scheme_component_id, score, absence_status)
select '10000000-0000-0000-0000-000000000001', mb.id, se.id, '24000000-0000-0000-0000-000000000001', 15, 'ENTERED'
from public.mark_books mb, public.student_enrollments se
where mb.class_id='30000000-0000-0000-0000-000000000001'
  and mb.subject_id=(select id from public.subjects where code='PHY' and school_id is null)
  and se.id='41000000-0000-0000-0000-000000000002';

-- run the results service
select public.compute_period_results(
  p_school => '10000000-0000-0000-0000-000000000001',
  p_class => '30000000-0000-0000-0000-000000000001',
  p_year => '20000000-0000-0000-0000-000000000001',
  p_period_type => 'SEQUENCE',
  p_period_id => '22000000-0000-0000-0000-000000000001',
  p_sequence_ids => array['22000000-0000-0000-0000-000000000001']::uuid[],
  p_subjects => jsonb_build_array(
    jsonb_build_object(
      'subject_id', (select id from public.subjects where code='MATHS' and school_id is null),
      'coefficient', 5, 'counts_in_average', true, 'counts_in_ranking', true, 'shows_on_report', true),
    jsonb_build_object(
      'subject_id', (select id from public.subjects where code='PHY' and school_id is null),
      'coefficient', 4, 'counts_in_average', true, 'counts_in_ranking', true, 'shows_on_report', true)
  ),
  p_scheme => '[{"id":"24000000-0000-0000-0000-000000000001","weight":1.0,"max_score":20}]',
  p_policy => '{"exclude":["NOT_ENTERED","ABSENT","EXCUSED","NOT_APPLICABLE","PENDING"],"zero_is_score":true}',
  p_ranking => '{"method":"COMPETITION","tie_breaker":"TOTAL_WEIGHTED_POINTS","same_rank_for_ties":true}',
  p_display => '{"decimals":2,"rounding":"HALF_UP"}'
);

-- show results
select s.full_name as student, pr.general_average, pr.total_weighted_points,
       pr.total_coefficients, pr.class_average, pr.rank, pr.status
from public.period_results pr
join public.student_enrollments se on se.id = pr.student_enrollment_id
join public.students s on s.id = se.student_id
where pr.class_id='30000000-0000-0000-0000-000000000001'
order by pr.rank;

select s.full_name as student, sub.code as subject, sr.subject_average, sr.coefficient, sr.weighted_points
from public.subject_results sr
join public.period_results pr on pr.id = sr.period_result_id
join public.student_enrollments se on se.id = pr.student_enrollment_id
join public.students s on s.id = se.student_id
join public.subjects sub on sub.id = sr.subject_id
where pr.class_id='30000000-0000-0000-0000-000000000001'
order by s.full_name, sub.code;

-- finalize then attempt an (illegal) direct modification
select public.finalize_period_results('30000000-0000-0000-0000-000000000001','SEQUENCE','22000000-0000-0000-0000-000000000001');
do $$
begin
  begin
    update public.period_results set general_average = 0
     where class_id='30000000-0000-0000-0000-000000000001' and period_type='SEQUENCE';
    raise exception 'IMMUTABILITY_FAILED: finalized results were mutable';
  exception when others then
    if sqlerrm like '%immutable%' then
      raise notice 'OK: finalized results are immutable';
    else
      raise;
    end if;
  end;
end $$;

-- verify the computed values match the Cameroon model
do $$
declare v_ok int;
begin
  select count(*) into v_ok
  from public.period_results pr
  join public.student_enrollments se on se.id = pr.student_enrollment_id
  join public.students s on s.id = se.student_id
  where pr.class_id = '30000000-0000-0000-0000-000000000001'
    and ((s.full_name = 'Student A' and pr.general_average = 13.11 and pr.rank = 1)
      or (s.full_name = 'Student B' and pr.general_average = 12.22 and pr.rank = 2));
  if v_ok <> 2 then raise exception 'WRONG GENERAL AVERAGES/RANKS (% of 2)', v_ok; end if;

  select count(*) into v_ok
  from public.subject_results sr
  join public.period_results pr on pr.id = sr.period_result_id
  join public.student_enrollments se on se.id = pr.student_enrollment_id
  join public.students s on s.id = se.student_id
  where pr.class_id = '30000000-0000-0000-0000-000000000001'
    and ((s.full_name = 'Student A' and sr.weighted_points = 70)
      or (s.full_name = 'Student A' and sr.weighted_points = 48)
      or (s.full_name = 'Student B' and sr.weighted_points = 50)
      or (s.full_name = 'Student B' and sr.weighted_points = 60));
  if v_ok <> 4 then raise exception 'WRONG SUBJECT POINTS (% of 4)', v_ok; end if;

  raise notice 'OK: computed results match the Cameroon coefficient model';
end $$;

rollback;