# School data recovery — operator runbook

Status: **prepared, not activated**. No destination has been chosen. No live
backup or database restore has been performed by this task. Never promise that
all data can always be recovered: recovery is limited by the last verified copy.

## Architecture

- Supabase PostgreSQL is the authoritative shared backend. Tenant records carry
  `school_id`; RLS and administrator checks control access. Losing a school PC
  should not delete cloud records. This is not an offline-sync implementation.
- Migration 0032 journals before/after values for existing public tables with
  `school_id`, plus schools themselves. Ordinary clients cannot modify the journal.
  There are no cascading foreign keys on it. It records future changes only, not
  pre-migration history. Import page/row tables without `school_id`, Auth records,
  and Storage bytes are covered by full backups, not by this journal.
- This journal can help an operator reconstruct accidentally changed/deleted
  records. It is **not** an automatic undo UI, off-site backup, or protection
  against loss of the entire Supabase project. New tenant tables need triggers.
  Monitor growth and define a retention policy before production: it contains
  sensitive student information, including historical/deleted values.
- Encrypted full backups contain a PostgreSQL custom dump, bucket configuration,
  downloaded Storage objects, and a SHA-256 manifest. A database-only backup does
  not contain uploaded PDFs, logos or signatures. See
  [Supabase backups](https://supabase.com/docs/guides/platform/backups).

## Prepare once

1. Choose an off-site destination independent of the application database and the
   developer/school PC. Restrict access, enable versioning/retention where available,
   and agree ownership, retention and incident response with schools. No provider
   or paid subscription is selected by this repository.
2. On a trusted operator machine install Python 3.10+, PostgreSQL client tools
   matching the server major version, and `age`. Generate an age key with
   `age-keygen -o recovery-identity.txt`. Keep the private identity offline with a
   second secure copy; the public recipient can be used by the backup job.
3. Supply `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGSSLMODE=verify-full` with
   the appropriate CA, and `PGPASSFILE` (owner-only permissions) through the
   operator's secret store. Use a direct/session connection supporting pg_dump.
   Supply `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` there too. Never put
   these privileged credentials in Flutter, Git, CI logs or distributable builds.
4. Use a database account capable of dumping all required schemas/data, including
   `public`, `auth` and `storage`. Verify the dump inventory; do not assume a
   successful command proves it contains every required table.

## Create and verify (from repository root)

Stop application writes and Storage changes for the entire capture window using
an operator-controlled maintenance procedure. The command's flag acknowledges
that you have done this; it does not enforce maintenance mode. The database dump
has its own snapshot, but database and Storage APIs do not share one snapshot.

```sh
python3 tools/recovery/backup.py create --writes-paused \
  --recipient age1YOUR_PUBLIC_RECIPIENT \
  --output /secure/backups/reportwise-2026-09-21.tar.age
python3 tools/recovery/backup.py verify \
  --archive /secure/backups/reportwise-2026-09-21.tar.age \
  --identity /secure/offline/recovery-identity.txt
```

Use a new output filename each time. The script refuses to overwrite backups,
fails if any listed object cannot be downloaded, and deletes only its own partial
output on encryption failure. Temporary plaintext exists while running; use a
trusted encrypted disk. The script downloads objects serially and may need a
long maintenance window for large projects. It does not schedule, upload off-site,
rotate, or alert on failed backups yet.

Copy the encrypted archive to the chosen destination, download it again and run
verification on that copy. Record completion time, file hash, destination and
object/table counts without exposing student data. Resume writes after capture.
Schedule and monitor this only after the first successful restore drill. Choose
a recovery-point target (for example daily) and show operators when the last
verified backup is overdue; this monitoring is not yet implemented.

## Restore drill — required before production

1. Never experiment on the production project. Create an isolated compatible
   Supabase/PostgreSQL target and restrict access to the recovery operator.
2. Download an off-site archive and run `verify`. Decrypt into a private temporary
   directory. Inspect the manifest and `pg_restore --list database.dump`.
3. Follow the current [Supabase restore/migration guide](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore).
   Managed schemas, extensions, ownership, roles and versions require compatible
   target configuration. This is a raw pg_dump archive, not a Supabase CLI export;
   do not blindly run `pg_restore --clean` against a hosted project.
   Cluster roles, Edge Function code, secrets, OAuth/provider settings and project
   configuration are not in this bundle; maintain them separately in secure
   infrastructure configuration. Plan Auth migration and credential rotation.
4. Restore database data and constraints in dependency order. Recreate buckets
   from manifest settings and upload each `objects[].file` under its original
   bucket/name via the Storage API, preserving MIME type. Restored metadata alone
   is insufficient. Reconcile metadata/owners according to the supported target
   workflow; public URLs will need reconciliation if the project URL changes.
5. Compare school/student/enrollment/mark/report counts, sample matricules and
   stored PDF hashes. Test two schools and teacher/admin accounts: no cross-school
   visibility; teachers cannot change school branding. Test signing in again.
6. Record actual elapsed restore time, missing items and verification results.
   Only then mark the backup process operational. Restoring one school requires
   extracting its dependency graph from the isolated restored database—not
   overwriting unrelated schools in production.

Local tool checks: `python3 -m unittest discover -s tools/recovery -p 'test_*.py'`.
They test packaging/hash/path safety with fixtures, not live backup completeness.
