-- file_rename.sql
-- Lets a signed-in user rename their OWN files (user_files.name).
-- Run it in the Supabase SQL Editor of BOTH projects (Student and Instructor).
-- Safe to run more than once.

-- 1) Column permission. Needed when UPDATE was only granted for some columns
--    (for example is_favorite and folder_id). Harmless if the whole table is
--    already allowed.
grant update (name) on public.user_files to authenticated;

-- 2) Row permission: a user may update only their own rows.
--    Only created when the table has no UPDATE policy at all.
do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename  = 'user_files'
      and cmd in ('UPDATE', 'ALL')
  ) then
    create policy "Users update own files"
      on public.user_files
      for update
      to authenticated
      using (owner_id = auth.uid())
      with check (owner_id = auth.uid());
  end if;
end
$$;

-- Optional, only if renaming STILL fails after the two steps above:
-- list the triggers and constraints on the table, then send me the result.
--
--   select tgname from pg_trigger
--   where tgrelid = 'public.user_files'::regclass and not tgisinternal;
--
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.user_files'::regclass;
