-- Fix: "Could not open the file. Try again." when someone other than the
-- owner taps Share or opens a public file on the Community page.
--
-- Run this in the Supabase SQL Editor of EACH project
-- (the Student project and the Instructor project).

-- Lets the storage policy check "is this file public?" without being
-- blocked by the owner-only rules on the user_files table.
create or replace function public.is_public_file(p_path text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_files
    where storage_path = p_path and visibility = 'public'
  );
$$;

grant execute on function public.is_public_file(text) to authenticated;

-- Any logged-in user may read files that their owner marked public.
-- Private files stay private.
drop policy if exists "Read public community files" on storage.objects;

create policy "Read public community files"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'user-files'
  and public.is_public_file(name)
);
