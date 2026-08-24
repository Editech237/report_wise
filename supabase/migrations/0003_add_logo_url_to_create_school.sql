-- =============================================================================
-- ReportWise — Migration 0003
-- Add logo_url parameter to create_school RPC
-- =============================================================================

create or replace function public.create_school(
  p_name          text,
  p_school_type   text,   -- GENERAL | TECHNICAL | BOTH
  p_subsystem     text,   -- FRANCOPHONE | ANGLOPHONE | BILINGUAL
  p_address       text default null,
  p_phone         text default null,
  p_email         text default null,
  p_region        text default null,
  p_division      text default null,
  p_sub_division  text default null,
  p_code          text default null,
  p_logo_url      text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_school uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if p_school_type not in ('GENERAL','TECHNICAL','BOTH')
     or p_subsystem not in ('FRANCOPHONE','ANGLOPHONE','BILINGUAL') then
    raise exception 'Invalid school type or subsystem';
  end if;

  insert into public.schools
    (name, code, school_type, subsystem, address, phone, email, region, division, sub_division, logo_url)
  values
    (p_name, p_code, p_school_type, p_subsystem, p_address, p_phone, p_email,
     p_region, p_division, p_sub_division, p_logo_url)
  returning id into v_school;

  insert into public.school_memberships (school_id, profile_id, role)
  values (v_school, auth.uid(), 'SUPER_ADMIN');

  return v_school;
end;
$$;