# ReportWise — Master Roadmap & Phase Tracker

Cameroon Secondary School Management Platform (CAMEROON-FIRST).

This file is the single benchmark for tracking delivery against the 48-section
master spec. Check off tasks as they are completed. Each task cites the spec
section(s) it satisfies.

## Cross-cutting quality bar (applies to every phase)

- SECURE: RLS-isolated by school; role enforcement at the database level (not
  only in the UI); LOCKED / UNLOCKED transitions audited; secrets never in
  code; national-default rows read-only.
- MODERN UX: consistent design system (Manrope/Lexend, green palette); guided
  forms, empty states, loading skeletons, responsive wide/compact, EN/FR
  localization.
- EFFICIENT: index-backed queries, caching, pagination, batched writes, minimal
  round-trips.
- ACCURATE: coefficient-weighted engine is the default; rules resolved
  centrally; historical results reproducible from immutable snapshots; no
  silent rounding of intermediates.

## Status legend

- `[x]` done
- `[~]` in progress
- `[ ]` pending

---

## Phase 0 — Foundation hardening

Grounds every later phase in security and accuracy guarantees.

- [x] Multi-tenant schema + RLS enabled on all tenant tables (migrations 0001–0006)
- [x] Auth (sign up/in, auto profile), RBAC roles (SUPER_ADMIN/ADMIN/PRINCIPAL/TEACHER/ACCOUNTANT/PARENT)
- [x] Academic engine: resolver, rules engine, calculator, ranking, rounding (+ unit tests)
- [x] School onboarding + academic-year + calendar seeding (3 terms × 2 sequences)
- [x] DB-level mark workflow enforcement (DRAFT→SUBMITTED by teacher; REVIEWED/APPROVED/LOCKED by admin; LOCKED blocks teacher edits; UNLOCKED audited with reason) [sec 27] — migration 0007
- [x] DB-level result immutability: period_results/subject_results cannot be modified once FINAL [sec 26] — migration 0008
- [x] Academic configuration audit table (who changed coefficient/curriculum/scheme/rule, when, from → to) [sec 40–41] — migration 0009
- [x] Tighten students/enrollments RLS: writes admin-only (currently any member can edit) [sec 46] — migration 0010
- [x] Enforce single is_current academic year per school (partial unique index + RPC) [sec 24] — migration 0011
- [x] Assessment scheme weight validation (components sum to 100) enforced at save [sec 13–14] — migration 0011
- [x] RLS coverage review query + role-scenario tests script [sec 46] — scripts/rls_coverage.sql
- [x] Seed smoke-test script (counts + constraints + helper functions) [sec 45] — scripts/smoke_test.sql

## Phase 1 — Curriculum data completeness & academic records UI

- [x] Seed full national curricula + coefficients for ALL levels and series/specialties (6ème→Tle, Form 1→Upper Sixth, technical STT/IND + specialties); representative values flagged for MINESEC verification [sec 5, 23, 42] — migration 0012
- [ ] Curriculum import/update tool for admins (upload official MINESEC config) [sec 24]
- [x] Academic Records UI: terms/sequences calendar view, open/close/finalize sequence [sec 10–11] — Academic screen (Calendar tab)
- [~] Academic Setup hub with guided forms: Education System, Years, Terms, Sequences, Classes, Series, Specialties, Subjects, Coefficients, Assessment Rules, Ranking Rules, Report Card, Grading Scale [sec 33] — Classes / Subjects / Academic screens cover most; hub shell still pending
- [x] Assessment scheme admin UI: create/edit schemes, assign to scope with preview [sec 13–14] — Academic screen (Schemes tab, save_assessment_scheme RPC)
- [x] Ranking rules UI (method, scopes, tie-breaker) with explicit default policy [sec 16–17] — Academic screen (Rules tab)
- [x] Administrative transparency: show "Source: National / School / Academic year" everywhere [sec 41] — subjects, schemes, rules screens

## Phase 2 — Teacher registry & assignments

- [x] Teacher registry UI (memberships, staff ids, subjects/classes taught) [sec 37] — Teachers screen; RPCs in migration 0013
- [x] Scalable teacher onboarding: admins create teachers → Edge Function (create-teacher) creates the auth user with a generated password (email pre-confirmed); admin shares it (WhatsApp/email/SMS) or the teacher resets it via the in-app "Forgot password" flow
- [x] Teacher assignment UI: teacher → class → subject → role (+ specialty for technical) [sec 37] — Teachers screen
- [ ] Teacher portal shell: teacher's classes/subjects/sequences landing page — teachers land directly on Mark entry (teacher portal shell)
- [x] Class teacher (professeur principal) assignment per class — Teachers screen

## Phase 3 — Mark entry & workflow

- [x] Mark entry grid: teacher selects class → subject → sequence → enter component marks [sec 11, 27] — Mark entry screen + RPCs in migration 0014
- [x] Mark entry usability: score fields always typeable (auto-marked ENTERED), one-line grading legend, clearer pickers ("1. Choose class·subject / 2. Choose sequence"), friendly empty states — fixes "admin can't see how to enter marks"
- [x] Missing-mark statuses (NOT_ENTERED/ABSENT/EXCUSED/ZERO/NOT_APPLICABLE/PENDING) with configurable policy [sec 28] — per-cell status menu; policy read from academic rules
- [x] Cameroon exam-only default: national assessment scheme is a single 100% Composition/Examen per subject per sequence (no CA/exam split) — migration 0019
- [x] Mark entry shows the entering teacher's name + assigned teacher (mismatch warning = anti-impersonation reinforcement) — migration 0019
- [x] Teacher password management: create-teacher + reset-teacher-password Edge Functions (admin-generated passwords, shareable; in-app Forgot password)
- [x] Mark book workflow UI: DRAFT→SUBMITTED→REVIEWED→APPROVED→LOCKED; unlock with reason + audit [sec 27] — workflow bar + history; DB trigger enforces
- [x] Persistent mark-book history: "Saved mark books" strip (class·subject·sequence, status, progress) — tap to reopen the full grid; teachers see their own books, admins all (migration 0020)
- [x] Mark entry workflow simplified: teachers just enter + save; admins Lock/Unlock (intermediate Submit/Review/Approve states kept in DB, buttons removed) [sec 27]
- [x] Results history: "Computed results" strip (class · period · status · students) — tap to reopen (migration 0022)
- [x] Fixed "0×1" display: subject coefficients are stored correctly; parser no longer fabricates 1/0 and shows '—' for genuinely missing values
- [x] Report card: Mark /20 · Average /20 · Coef · Avg×Coef · Teacher's remark columns; subject rows include the teacher's name; header now has DOB, place of birth, guardian name + contact, repeater, gender, # subjects, # passed, class master
- [x] Student identity fields added (place_of_birth, guardian_name, guardian_phone, repeater) — migration 0022 + dialogs/details
- [x] Reports: Export PDF via save dialog (desktop) / share (mobile); native Print for one student; Print all / Export all = one multi-page PDF for the whole class
- [x] Validation preview: per-subject average + weighted points shown live per student; full general-average breakdown now computed by the results service [sec 30]
- [x] Batch/transactional mark save (single RPC, not N inserts) [sec 30] — save_mark_entries

## Phase 4 — Results computation service & ranking

- [x] Server-side results service: resolves rules → computes per student → persists period_results + subject_results snapshots (config_snapshot = subjects/coefficients/scheme/policy/ranking used) [sec 26, 44] — compute_period_results (migrations 0015–0016)
- [x] Term & annual average computation from stored rules [sec 15] — TERM (mean of sequence averages) and ANNUAL (mean of term averages) branches
- [~] Ranking engine wired: class / series / level / school scope per configurable policy [sec 16–17] — class ranking (competition/dense/sequential + tie-break) implemented; broader scopes config stored, computation pending
- [x] Results review screen for admins (breakdown per student, class averages, per-subject rows) [sec 30] — Results tab in Academic
- [x] Finalize / unfinalize (audited, admin-only) with DB immutability — finalize_period_results / unfinalize_period_results
- [ ] Class averages + appreciation thresholds configurable (grading scale UI) — class average computed; grading-scale/appreciation UI pending

## Phase 5 — Report cards

- [x] Report template model: national default templates seeded (SEQUENCE/TERM/ANNUAL) [sec 18] — migration 0021
- [x] Cameroon bulletin renderer (Republic header, ministry, school, student, class/series/specialty, subjects/coefs/marks/points, general + class average, rank, appreciation, comments, signatures/stamp) [sec 18, 19] — report_card.dart
- [x] Report generation → PDF (client-side, vector) with in-app preview and share/save [sec 26] — report_pdf.dart + Reports screen
- [x] Historical reproducibility: reports are built from the immutable period_result snapshot; every generation is recorded (versioned) in report_cards [sec 26, 9]
- [~] Technical-school report variant (practical/workshop/competency fields) [sec 20] — pending
- [ ] HTML template customization UI [sec 18] — templates are DB rows; layout is code-rendered for now

## Phase 6 — Offline teacher mark entry & synchronization

- [ ] Local-first datastore (drift/sembast) for mark books + entries [sec 15–16, MVP 15]
- [ ] Offline mark entry with status badges (saved/syncing/conflict) [MVP 15]
- [ ] Sync engine: queue, retry, conflict resolution (server wins on LOCKED; last-write otherwise) [MVP 16]
- [ ] Connectivity detection + sync-on-reconnect
- [ ] Offline sync tests (partial failure, re-upload, duplicate protection)

## Phase 7 — Localization, notifications & settings

- [ ] EN/FR localization (arb) covering report terminology (Matière/Moyenne/Rang/…) [sec 19]
- [ ] Bilingual toggle + report language selection
- [ ] Notifications module (mark reminders, approval requests, system) [MVP 21]
- [ ] Settings screen: school profile, logo, preferences, data/backup
- [ ] User profile management (name, phone, avatar, password)

## Phase 8 — Import/export & analytics

- [ ] Student bulk import (CSV) with validation + preview; export lists/report cards [MVP 23]
- [ ] Curriculum/coefficient import/export (JSON) [sec 24]
- [ ] Advanced analytics: pass rates, per-subject distributions, class comparisons, trend charts [MVP 20]

## Phase 9 — Timetable engine & AI assistant

- [ ] Deterministic constraint solver: periods, rooms/labs/workshops, teacher+class availability, subject workloads, specialty constraints [sec 38]
- [ ] AI request → structured constraints pipeline (AI never emits an unchecked timetable) [sec 39]
- [ ] Timetable UI: grid view, conflict highlighting, exports

## Phase 10 — Production hardening & QA

- [ ] E2E test suite for all MVP flows (onboarding → marks → report card)
- [ ] Load test: 500+ student class, mark entry latency, report generation
- [ ] Security review: RLS matrix, role escalation tests, storage policies, rate limiting
- [ ] Error/analytics monitoring, crash reporting, graceful degradation
- [ ] Performance: pagination everywhere, query plan review, materialized views if needed
- [ ] Final domain acceptance: re-run section 45 scenarios against the live DB (not just the engine)

---

## Immediate next milestone (in progress)

Phase 0 hardening (migrations 0007–0011 + scripts), then the classroom
pipeline: teachers → mark entry → results/ranking → report cards.

---

## Post-Phase-4 hardening pass (bugs found in review, all fixed)

- [x] Fix duplicated national hierarchy seed (14 bogus levels caused empty subject sets on some classes) — migration 0017 (re-pointed classes/curriculum/configs, deduped curricula + coefficient configs, added guard trigger + coalesced unique indexes)
- [x] Class editor: cycle dropdown now filtered by subsystem; labels disambiguated for bilingual schools
- [x] Students: stale list after add/edit/delete fixed (invalidateSchoolData invalidates child providers); modern cards; row tap → Student details screen; modern scrollable add/edit dialog (overflow fixed); friendly permission/record errors; refresh button works
- [x] Dashboard: real pass rate + recent activity from dashboard_metrics RPC (migration 0018); no more dummy numbers; quick-action chips navigate; shimmer loading
- [x] Teachers: add-teacher dialog explains the signup path; assignment modal rebuilt (scrollable, modern dropdowns); refresh button added
- [x] Academic: Assessment Schemes + Ranking Rules tabs removed from UI (DB/API retained); Seq/Term/Annual control widened
- [x] Classes: refresh button; modern dropdowns; editing now limited to name/room (hierarchy read-only with explanation)
- [x] Subjects: empty-resolution state explained; resolution itself fixed by migration 0017 (verified: Form 1/Form 2 SCI/Form 3 SCI resolve 11 subjects)
- [x] General UI: header search navigates to Students; shared shimmer + modern dropdown/modal design system; widget_test wrapped in ProviderScope (was broken)