-- Student matricules are system-generated unless an imported school identifier
-- is explicitly provided.  The trigger also covers rows created outside the app.
create or replace function public.ensure_student_matricule()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_id uuid;
begin
  if nullif(trim(new.matricule), '') is null then
    v_id := coalesce(new.id, gen_random_uuid());
    new.matricule := 'STU-' || upper(substr(replace(v_id::text, '-', ''), 1, 10));
  else
    new.matricule := trim(new.matricule);
  end if;
  return new;
end;
$$;

drop trigger if exists students_ensure_matricule on public.students;
create trigger students_ensure_matricule
before insert or update of matricule on public.students
for each row execute function public.ensure_student_matricule();

-- Backfill legacy rows created before matricule generation was introduced.
update public.students
set matricule = 'STU-' || upper(substr(replace(id::text, '-', ''), 1, 10))
where nullif(trim(matricule), '') is null;
