-- Import batches keep the original source document and every extraction/review
-- decision separate from the canonical student registry.
create table if not exists public.student_import_batches (
  id                 uuid primary key default gen_random_uuid(),
  school_id          uuid not null references public.schools(id) on delete cascade,
  uploaded_by        uuid not null default auth.uid() references public.profiles(id),
  source_type        text not null default 'PDF' check (source_type in ('PDF','CSV','XLSX')),
  original_filename  text not null,
  storage_path       text not null,
  status             text not null default 'UPLOADED'
                     check (status in ('UPLOADED','PROCESSING','NEEDS_REVIEW','APPROVED','IMPORTING','COMPLETED','FAILED')),
  page_count         integer,
  row_count          integer,
  reviewed_count     integer not null default 0,
  error_message      text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index if not exists student_import_batches_school_idx
  on public.student_import_batches(school_id, created_at desc);

create table if not exists public.student_import_pages (
  id                 uuid primary key default gen_random_uuid(),
  batch_id           uuid not null references public.student_import_batches(id) on delete cascade,
  page_number        integer not null,
  status             text not null default 'PENDING'
                     check (status in ('PENDING','PROCESSING','EXTRACTED','FAILED')),
  raw_text           text,
  extraction_payload jsonb,
  error_message      text,
  created_at         timestamptz not null default now(),
  unique (batch_id, page_number)
);

create table if not exists public.student_import_rows (
  id                 uuid primary key default gen_random_uuid(),
  batch_id           uuid not null references public.student_import_batches(id) on delete cascade,
  page_id            uuid references public.student_import_pages(id) on delete set null,
  row_number         integer not null,
  raw_data           jsonb not null default '{}'::jsonb,
  normalized_data    jsonb not null default '{}'::jsonb,
  confidence         jsonb not null default '{}'::jsonb,
  status             text not null default 'NEEDS_REVIEW'
                     check (status in ('NEEDS_REVIEW','READY','APPROVED','REJECTED','IMPORTED')),
  review_notes       text,
  matched_student_id uuid references public.students(id) on delete set null,
  created_student_id uuid references public.students(id) on delete set null,
  created_at         timestamptz not null default now(),
  unique (batch_id, row_number)
);

alter table public.students add column if not exists external_student_id text;
alter table public.students add column if not exists source_import_batch_id uuid references public.student_import_batches(id) on delete set null;

alter table public.student_import_batches enable row level security;
alter table public.student_import_pages enable row level security;
alter table public.student_import_rows enable row level security;

create policy "student_import_batches_select" on public.student_import_batches
  for select using (public.is_school_member(school_id));
create policy "student_import_batches_insert" on public.student_import_batches
  for insert with check (public.is_school_admin(school_id));
create policy "student_import_batches_update" on public.student_import_batches
  for update using (public.is_school_admin(school_id));

create policy "student_import_pages_select" on public.student_import_pages
  for select using (exists (
    select 1 from public.student_import_batches b
    where b.id = batch_id and public.is_school_member(b.school_id)
  ));
create policy "student_import_pages_write" on public.student_import_pages
  for all using (exists (
    select 1 from public.student_import_batches b
    where b.id = batch_id and public.is_school_admin(b.school_id)
  )) with check (exists (
    select 1 from public.student_import_batches b
    where b.id = batch_id and public.is_school_admin(b.school_id)
  ));

create policy "student_import_rows_select" on public.student_import_rows
  for select using (exists (
    select 1 from public.student_import_batches b
    where b.id = batch_id and public.is_school_member(b.school_id)
  ));
create policy "student_import_rows_write" on public.student_import_rows
  for all using (exists (
    select 1 from public.student_import_batches b
    where b.id = batch_id and public.is_school_admin(b.school_id)
  )) with check (exists (
    select 1 from public.student_import_batches b
    where b.id = batch_id and public.is_school_admin(b.school_id)
  ));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('student-imports', 'student-imports', false, 52428800, array['application/pdf'])
on conflict (id) do nothing;

create policy "student_import_files_insert" on storage.objects
  for insert with check (
    bucket_id = 'student-imports'
    and public.is_school_admin(split_part(name, '/', 1)::uuid)
  );
create policy "student_import_files_select" on storage.objects
  for select using (
    bucket_id = 'student-imports'
    and public.is_school_member(split_part(name, '/', 1)::uuid)
  );
create policy "student_import_files_delete" on storage.objects
  for delete using (
    bucket_id = 'student-imports'
    and public.is_school_admin(split_part(name, '/', 1)::uuid)
  );
