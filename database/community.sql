-- Community page: search the PUBLIC files of everybody in this project.
-- Run this in BOTH Supabase projects (Student and Instructor), SQL editor.
-- Safe to run again.

-- 1) Public files + author name (security definer: the author's name lives in
--    auth.users, which the app can't read directly). Only rows with
--    visibility = 'public' are ever returned, and only to logged-in users.
create or replace function public.community_files(p_query text default '')
returns table (
  id            text,
  owner_id      text,
  name          text,
  file_type     text,
  storage_path  text,
  created_at    timestamptz,
  author_name   text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select t.id, t.owner_id, t.name, t.file_type, t.storage_path,
         t.created_at, t.author_name
  from (
    select f.id::text       as id,
           f.owner_id::text as owner_id,
           f.name           as name,
           f.file_type      as file_type,
           f.storage_path   as storage_path,
           f.created_at     as created_at,
           coalesce(
             nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
             nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
             split_part(u.email, '@', 1)
           ) as author_name
    from public.user_files f
    join auth.users u on u.id = f.owner_id
    where f.visibility = 'public'
  ) t
  where coalesce(trim(p_query), '') = ''
     or t.name        ilike '%' || replace(replace(replace(trim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
     or t.author_name ilike '%' || replace(replace(replace(trim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  order by t.created_at desc
  limit 200;
$$;

revoke all on function public.community_files(text) from public;
revoke all on function public.community_files(text) from anon;
grant execute on function public.community_files(text) to authenticated;

-- 2) Let logged-in users open (signed link) files that are public.
drop policy if exists "community can read public files" on storage.objects;
create policy "community can read public files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'user-files'
    and exists (
      select 1
      from public.user_files f
      where f.storage_path = storage.objects.name
        and f.visibility = 'public'
    )
  );
