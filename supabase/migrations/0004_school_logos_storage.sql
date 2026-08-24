-- =============================================================================
-- ReportWise — Migration 0004
-- Create Supabase Storage bucket for school logos
-- =============================================================================

-- Create the storage bucket
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'school-logos',
  'school-logos',
  true,
  2097152, -- 2MB
  array['image/jpeg', 'image/png', 'image/webp']
) on conflict (id) do nothing;

-- RLS policies for school-logos bucket
-- Anyone authenticated can upload to their school's folder
create policy "school_logos_insert" on storage.objects
  for insert with check (
    bucket_id = 'school-logos'
    and auth.uid() is not null
  );

-- Anyone can view public logos
create policy "school_logos_select" on storage.objects
  for select using (
    bucket_id = 'school-logos'
  );

-- School admins can update/delete their school's logos
create policy "school_logos_update" on storage.objects
  for update using (
    bucket_id = 'school-logos'
    and exists (
      select 1 from public.school_memberships sm
      where sm.profile_id = auth.uid()
        and sm.is_active
        and sm.role in ('SUPER_ADMIN','ADMIN','PRINCIPAL')
        and (name like sm.school_id || '/%')
    )
  );

create policy "school_logos_delete" on storage.objects
  for delete using (
    bucket_id = 'school-logos'
    and exists (
      select 1 from public.school_memberships sm
      where sm.profile_id = auth.uid()
        and sm.is_active
        and sm.role in ('SUPER_ADMIN','ADMIN','PRINCIPAL')
        and (name like sm.school_id || '/%')
    )
  );