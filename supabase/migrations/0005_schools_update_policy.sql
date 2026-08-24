-- =============================================================================
-- ReportWise — Migration 0005
-- Allow school admins to update their school row (logo_url, address, etc.)
-- Fixes: logo upload succeeded to storage but `update schools set logo_url`
-- was silently denied by RLS (only `schools_select` existed, no update policy
-- → logo_url stayed null even after correct upload to `school-logos` bucket)
-- =============================================================================

-- Schools: admins can update their own school
create policy "schools_update" on public.schools
  for update using (public.is_school_admin(id))
  with check (public.is_school_admin(id));

-- Optional: allow admins to delete (not used by app but completes CRUD)
create policy "schools_delete" on public.schools
  for delete using (public.is_school_admin(id));

-- RPC fallback for logo updates (security definer, works even if RLS cache lags)
create or replace function public.update_school_logo(p_school uuid, p_logo_url text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_school_admin(p_school) then
    raise exception 'Not authorized to update this school';
  end if;
  update public.schools set logo_url = p_logo_url, updated_at = now() where id = p_school;
end;
$$;
