# School demo / launch readiness

## Implemented in this pass

- Review uses normalized fields with source aliases as fallback, preserves
  ambiguous dates for correction, and matches only available classes in the
  active school/year. Adding a row does not save an empty record on cancellation.
- Per-row Approve and Approve All mark valid rows approved; invalid rows remain
  for review. Approval is separate from importing. OCR correctness still requires
  human comparison with the original register.
- Registry enrollment loading is paginated rather than stopping at 500 records.
- Anglophone reports use English labels/appreciations; bilingual schools use the
  class's Anglophone/Francophone section for report language. Custom class/subject
  names are preserved. This is not full French translation of the application UI.
- Report PDF totals align with their columns; remote images have timeouts and
  size limits, and connections close on failure.
- Migration 0031 serializes batch import retries and locks approved rows.
- Migration 0032 adds a restricted tenant change journal. See the operator
  [recovery runbook](../../tools/recovery/README.md) from the repository root
  (`tools/recovery/README.md`) for off-site backup setup and limitations.

## Required before handling real school records

- Apply/test migrations 0031–0032 in a staging database first. They have not been
  applied to the hosted database by this task. Verify concurrent import clicks
  create each student once, invalid rows roll back, journal events are generated,
  and ordinary clients cannot alter recovery history.
- Run database RLS tests with school A admin, school B admin and a teacher;
  verify branded files/private registers cannot be modified/read outside policy.
- Choose an off-site backup location, protect keys, run a full restore drill,
  then schedule backups with failure/overdue alerts. None is activated yet.
- Run the Windows release build and native OCR smoke tests on Windows, including
  missing language packs, English/French registers and failed network saves.
  Windows runtime validation cannot be replaced by Mac tests.
- Confirm school-specific report formats with an actual Anglophone and bilingual
  school. Check long names, large subject lists, signature placement, annual and
  sequence reports; current report layout assumes a conventional term format.
- Use synthetic data during demos until these checks are complete. OCR supports
  table-style registers, not arbitrary handwriting/layouts with guaranteed accuracy.

## Reproducible checks

Verified on the development Mac in this pass: 58 application tests passed (one
live-project diagnostic intentionally skipped), 47 grading-engine tests passed,
3 backup fixture tests passed, and the debug macOS build succeeded. Static
analysis reported no compile errors, but still reports 211 warnings/style notices
across the project; this is not a clean-analyzer claim. Live SQL migrations,
off-site backup/restore and Windows execution remain unverified.

From `app`: `flutter test --no-pub`, `flutter analyze --no-pub`, and
`flutter build macos --debug --no-pub --dart-define-from-file=.env`.
From `engine`: `dart test`.
From the repository root: `python3 -m unittest discover -s tools/recovery`.

`diag_init_test.dart` is an explicitly opt-in live Supabase diagnostic, not an
offline unit test. Run with `--dart-define=RUN_SUPABASE_DIAGNOSTIC=true` only
against the intended test project. Its default skip is intentional.
