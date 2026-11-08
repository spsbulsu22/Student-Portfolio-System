-- Lets the app switch a file between Private and Public (My Portfolio >
-- "more" menu > Make Public / Make Private).
-- Run ONCE in the SQL editor of BOTH Supabase projects. Safe to run again.
--
-- Why: your user_files table has a database rule (trigger) that refuses every
-- change except name, folder and favorite ("Only the name, folder and favorite
-- can be changed."). This script finds that rule and also allows `visibility`.

-- 1) Let the owner update the visibility column.
grant update (visibility) on public.user_files to authenticated;

-- 2) Allow only the two known values.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.user_files'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%visibility%'
  ) then
    alter table public.user_files
      add constraint user_files_visibility_check
      check (visibility in ('private', 'public'));
  end if;
end $$;

-- 3) Patch the rule that blocks the change.
--    It looks for the function that raises that message and removes its
--    "visibility changed" check. If it cannot patch it safely, it stops with
--    an error that contains the function's code: copy that error and send it
--    to Claude.
do $$
declare
  r      record;
  def    text;
  newdef text;
  found  boolean := false;
begin
  for r in
    select p.oid, p.proname
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.prosrc ilike '%Only the name, folder and favorite%'
  loop
    found := true;
    def := pg_get_functiondef(r.oid);
    newdef := def;
    newdef := regexp_replace(newdef,
      'new\.visibility\s+is\s+distinct\s+from\s+old\.visibility', 'false', 'gi');
    newdef := regexp_replace(newdef,
      'old\.visibility\s+is\s+distinct\s+from\s+new\.visibility', 'false', 'gi');
    newdef := regexp_replace(newdef,
      'new\.visibility\s*(<>|!=)\s*old\.visibility', 'false', 'gi');
    newdef := regexp_replace(newdef,
      'old\.visibility\s*(<>|!=)\s*new\.visibility', 'false', 'gi');

    if newdef = def then
      raise exception
        'Could not patch % automatically. Send this function to Claude: %',
        r.proname, def;
    end if;

    execute newdef;
    raise notice 'Patched function %', r.proname;
  end loop;

  if not found then
    raise notice 'No function with that message was found in the public schema.';
  end if;
end $$;
