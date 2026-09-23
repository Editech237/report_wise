-- Serialize retries of the same batch and lock each selected row. All writes
-- remain atomic: an invalid row rolls back the entire import.
create or replace function public.import_approved_student_rows(p_batch uuid, p_year uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_batch public.student_import_batches%rowtype;
  item public.student_import_rows%rowtype;
  v_student uuid;
  v_class uuid;
  v_count integer := 0;
begin
  select * into v_batch from public.student_import_batches where id = p_batch for update;
  if v_batch.id is null or not public.is_school_admin(v_batch.school_id) then
    raise exception 'Only a school administrator can commit this import';
  end if;
  if not exists (select 1 from public.academic_years where id = p_year and school_id = v_batch.school_id) then
    raise exception 'Academic year not found in this school';
  end if;

  update public.student_import_batches set status = 'IMPORTING', updated_at = now() where id = p_batch;
  for item in select * from public.student_import_rows where batch_id = p_batch and status = 'APPROVED' order by row_number for update loop
    if nullif(trim(item.normalized_data ->> 'full_name'), '') is null then
      raise exception 'Approved row % is missing a full name', item.row_number;
    end if;
    v_class := nullif(item.normalized_data ->> 'class_id', '')::uuid;
    if not exists (select 1 from public.classes where id = v_class and school_id = v_batch.school_id and academic_year_id = p_year and is_active) then
      raise exception 'Approved row % has an invalid class', item.row_number;
    end if;

    insert into public.students (school_id, full_name, matricule, external_student_id, date_of_birth, gender, source_import_batch_id)
    values (
      v_batch.school_id,
      trim(item.normalized_data ->> 'full_name'),
      nullif(trim(item.normalized_data ->> 'matricule'), ''),
      nullif(trim(item.normalized_data ->> 'external_student_id'), ''),
      nullif(item.normalized_data ->> 'date_of_birth', '')::date,
      nullif(trim(item.normalized_data ->> 'gender'), ''),
      p_batch
    ) returning id into v_student;

    insert into public.student_enrollments (school_id, student_id, academic_year_id, class_id, status, enrolled_on)
    values (v_batch.school_id, v_student, p_year, v_class, 'ENROLLED', current_date);
    update public.student_import_rows set status = 'IMPORTED', created_student_id = v_student where id = item.id;
    v_count := v_count + 1;
  end loop;

  update public.student_import_batches set status = 'COMPLETED', updated_at = now() where id = p_batch;
  return v_count;
end;
$$;

revoke all on function public.import_approved_student_rows(uuid, uuid) from public, anon;
grant execute on function public.import_approved_student_rows(uuid, uuid) to authenticated;

