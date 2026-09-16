-- Prefer the newest mark book when duplicate books exist for a class, subject
-- and sequence. An older empty book previously made subject averages NULL.
do $$
declare
  definition text;
begin
  select pg_get_functiondef(p.oid)
    into definition
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'compute_period_results'
  limit 1;

  if definition is not null then
    definition := replace(
      definition,
      'order by class_id, subject_id, sequence_id, created_at',
      'order by class_id, subject_id, sequence_id, created_at desc'
    );
    execute definition;
  end if;
end $$;
