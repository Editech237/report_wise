create or replace function public.import_students_batch(
  p_school uuid,
  p_year uuid,
  p_rows jsonb
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  v_student uuid;
  v_class uuid;
  v_count integer := 0;
begin
  if not public.is_school_admin(p_school) then
    raise exception 'Only an administrator can import students';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Import rows must be an array';
  end if;
  if not exists (select 1 from public.academic_years where id = p_year and school_id = p_school) then
    raise exception 'Academic year not found in this school';
  end if;

  for item in select value from jsonb_array_elements(p_rows)
  loop
    if nullif(trim(item ->> 'full_name'), '') is null then
      raise exception 'Every imported row requires a full_name';
    end if;
    v_class := (item ->> 'class_id')::uuid;
    if not exists (select 1 from public.classes where id = v_class and school_id = p_school and academic_year_id = p_year) then
      raise exception 'Imported class does not belong to this school and academic year';
    end if;
    if nullif(trim(item ->> 'matricule'), '') is not null and exists (
      select 1 from public.students where school_id = p_school and matricule = trim(item ->> 'matricule')
    ) then
      raise exception 'Duplicate matricule in import: %', trim(item ->> 'matricule');
    end if;

    insert into public.students
      (school_id, full_name, matricule, date_of_birth, gender, place_of_birth,
       guardian_name, guardian_phone, repeater)
    values
      (p_school, trim(item ->> 'full_name'), nullif(trim(item ->> 'matricule'), ''),
       nullif(item ->> 'date_of_birth', '')::date, nullif(trim(item ->> 'gender'), ''),
       nullif(trim(item ->> 'place_of_birth'), ''), nullif(trim(item ->> 'guardian_name'), ''),
       nullif(trim(item ->> 'guardian_phone'), ''), coalesce((item ->> 'repeater')::boolean, false))
    returning id into v_student;

    insert into public.student_enrollments
      (school_id, student_id, academic_year_id, class_id, status, enrolled_on)
    values (p_school, v_student, p_year, v_class, 'ENROLLED', current_date);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
