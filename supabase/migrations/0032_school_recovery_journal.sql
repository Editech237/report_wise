-- Recovery evidence, not a substitute for an encrypted off-site backup.
-- No foreign keys: history must survive deletion of a school or student.
create table public.school_recovery_events (
  id bigint generated always as identity primary key,
  school_id uuid not null,
  table_name text not null,
  operation text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),
  record_id text,
  before_data jsonb,
  after_data jsonb,
  actor_id uuid,
  recorded_at timestamptz not null default now(),
  transaction_id bigint not null default txid_current()
);
create index school_recovery_events_school_time
  on public.school_recovery_events(school_id, recorded_at desc);
alter table public.school_recovery_events enable row level security;
revoke all on public.school_recovery_events from anon, authenticated;
grant select on public.school_recovery_events to authenticated;
create policy recovery_events_admin_read on public.school_recovery_events
  for select to authenticated using (public.is_school_admin(school_id));

create function public.record_school_recovery_event() returns trigger
language plpgsql security definer set search_path = pg_catalog, public as $$
declare
  previous jsonb;
  following jsonb;
  school uuid;
begin
  if TG_OP <> 'INSERT' then previous := to_jsonb(OLD); end if;
  if TG_OP <> 'DELETE' then following := to_jsonb(NEW); end if;
  if TG_TABLE_NAME = 'schools' then
    school := coalesce(following ->> 'id', previous ->> 'id')::uuid;
  else
    school := coalesce(following ->> 'school_id', previous ->> 'school_id')::uuid;
  end if;
  -- Shared national reference rows do not belong to a tenant.
  if school is not null then
    insert into public.school_recovery_events
      (school_id, table_name, operation, record_id, before_data, after_data, actor_id)
    values (school, TG_TABLE_NAME, TG_OP,
      coalesce(following ->> 'id', previous ->> 'id'), previous, following, auth.uid());
  end if;
  return null;
end;
$$;
revoke all on function public.record_school_recovery_event() from public, anon, authenticated;

-- Attach to existing tenant tables. Future tenant tables need the same trigger.
do $$
declare item record;
begin
  for item in
    select t.table_name from information_schema.tables t
    where t.table_schema = 'public' and t.table_type = 'BASE TABLE'
      and t.table_name <> 'school_recovery_events'
      and (t.table_name = 'schools' or exists (
        select 1 from information_schema.columns c
        where c.table_schema = t.table_schema and c.table_name = t.table_name
          and c.column_name = 'school_id'))
  loop
    execute format('create trigger school_recovery_event after insert or update or delete on public.%I for each row execute function public.record_school_recovery_event()', item.table_name);
  end loop;
end;
$$;
