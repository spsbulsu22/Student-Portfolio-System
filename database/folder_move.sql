-- Lets a user move THEIR OWN files and folders into folders (My Portfolio >
-- hold a file or folder, drag it onto another folder).
-- Run this in the STUDENT Supabase project only (the Instructor project has
-- no folders), in the SQL editor. Safe to run more than once.

-- Folders: change which folder they are inside.
drop policy if exists "Owners move their folders" on public.portfolio_folders;

create policy "Owners move their folders"
  on public.portfolio_folders
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

grant update (parent_id) on public.portfolio_folders to authenticated;

-- Files: change which folder they are inside.
drop policy if exists "Owners move their files" on public.user_files;

create policy "Owners move their files"
  on public.user_files
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

grant update (folder_id) on public.user_files to authenticated;
