-- Storage bucket: user-files (private, 50 MB)
-- Run in: BOTH projects (Student + Instructor)
-- Path format: <role>/<user id>/<unique>_<name>

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-files', 'user-files', false, 50000000,
  array[
    'application/pdf', 'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'text/plain', 'text/csv', 'application/rtf',
    'image/png', 'image/jpeg', 'image/gif', 'image/webp',
    'video/mp4', 'video/quicktime', 'video/webm',
    'audio/mpeg', 'audio/wav', 'application/zip'
  ]
)
on conflict (id) do nothing;

create policy "userfiles_select_own" on storage.objects
  for select using (
    bucket_id = 'user-files'
    and (storage.foldername(name))[2] = auth.uid()::text);

create policy "userfiles_insert_own" on storage.objects
  for insert with check (
    bucket_id = 'user-files'
    and (storage.foldername(name))[2] = auth.uid()::text);

create policy "userfiles_delete_own" on storage.objects
  for delete using (
    bucket_id = 'user-files'
    and (storage.foldername(name))[2] = auth.uid()::text);
