-- =============================================================================
-- ReportWise — Migration 0021
-- Default Cameroon report templates (spec section 18).
--
-- Report templates are DB entities so schools can customize them later. The
-- seeded national defaults describe the standard Cameroon sequence/term/annual
-- bulletin. The layout is rendered by the client (widget + PDF) using the
-- immutable period_result snapshot; template_html stays empty as a placeholder
-- until HTML-based rendering is supported.
-- =============================================================================

insert into public.report_templates (school_id, name, subsystem, kind, is_default, template_html, config)
values
  (null, 'Cameroon National Bulletin (Sequence)', null, 'SEQUENCE', true, '', '{"lang":"bilingual"}'),
  (null, 'Cameroon National Bulletin (Term)',     null, 'TERM',     true, '', '{"lang":"bilingual"}'),
  (null, 'Cameroon National Bulletin (Annual)',   null, 'ANNUAL',   true, '', '{"lang":"bilingual"}')
on conflict do nothing;