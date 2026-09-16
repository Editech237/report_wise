-- =============================================================================
-- ReportWise — Migration 0019
-- Cameroon exam-only default assessment scheme.
--
-- Cameroonian secondary schools grade each subject per sequence with a single
-- composition/exam (out of 20); the coefficient then weights the subject in the
-- general average. There is no national continuous-assessment split. The default
-- national scheme therefore becomes a single 100% exam component. Schools may
-- still define their own multi-component schemes (save_assessment_scheme).
-- =============================================================================

-- Remove the national continuous-assessment/exam scheme (components cascade).
delete from public.assessment_schemes
where school_id is null and name = 'Continuous Assessment / Exam';

-- Rename the classic scheme and reduce it to a single exam component.
update public.assessment_schemes
set name = 'Composition / Examen (100%)'
where school_id is null and name = 'Classic Cameroon (CA/Interro/Devoir/Exam)';

delete from public.assessment_scheme_components sc
where sc.scheme_id in (
  select id from public.assessment_schemes where school_id is null
);

insert into public.assessment_scheme_components
  (scheme_id, school_id, name, component_type, weight, max_score, sort_order)
select id, null, 'Composition / Examen', 'EXAM', 100, 20, 1
from public.assessment_schemes
where school_id is null and is_default;