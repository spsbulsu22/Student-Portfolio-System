-- Lets a user delete THEIR OWN folders (My Portfolio > long-press a folder >
-- Delete). Run this in BOTH Supabase projects (Student and Instructor), in the
-- SQL editor. Safe to run more than once.

drop policy if exists "Owners delete their folders" on public.portfolio_folders;

create policy "Owners delete their folders"
  on public.portfolio_folders
  for delete
  to authenticated
  using (owner_id = auth.uid());

grant delete on public.portfolio_folders to authenticated;
