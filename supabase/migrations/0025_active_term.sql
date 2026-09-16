alter table public.schools
  add column if not exists current_term_number integer;

alter table public.schools
  drop constraint if exists schools_current_term_number_check;

alter table public.schools
  add constraint schools_current_term_number_check
  check (current_term_number is null or current_term_number between 1 and 3);
