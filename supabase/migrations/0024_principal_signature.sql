alter table public.schools
  add column if not exists principal_name text,
  add column if not exists principal_signature_url text;
