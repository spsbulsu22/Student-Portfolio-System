-- Shows real names (not "Unknown user") for OTHER people on comments and
-- on the Community page.
--
-- Run this in the Supabase SQL Editor of EACH project
-- (the Student project and the Instructor project). Safe to run again.
--
-- Name rule (same as lib/utils/display_name.dart):
--   1. full_name / name saved on the account, if there is one
--   2. otherwise built from the email:
--        oliver@test.com      -> Oliver Test   (one word: add the domain)
--        john.doe@school.edu  -> John Doe      (several words: use them)
-- When the registration page saves a full_name, it is used automatically.

create or replace function public.derive_display_name(p_meta jsonb, p_email text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_name   text := nullif(btrim(coalesce(p_meta->>'full_name', p_meta->>'name', '')), '');
  v_local  text;
  v_domain text;
  v_parts  text[];
begin
  if v_name is not null then
    return v_name;
  end if;
  if p_email is null or position('@' in p_email) = 0 then
    return 'Unknown user';
  end if;

  v_local  := split_part(p_email, '@', 1);
  v_domain := regexp_replace(lower(split_part(split_part(p_email, '@', 2), '.', 1)), '[0-9]+', '', 'g');

  v_parts := array(
    select w
    from unnest(regexp_split_to_array(
           lower(regexp_replace(v_local, '[0-9]+', '', 'g')), '[._+-]+')) as w
    where w <> ''
  );

  if coalesce(array_length(v_parts, 1), 0) = 0 then
    v_parts := array[v_local];
  elsif array_length(v_parts, 1) = 1 and v_domain <> '' then
    v_parts := v_parts || v_domain;
  end if;

  return initcap(array_to_string(v_parts, ' '));
end;
$$;

-- Returns only names (never emails) for the given user ids.
create or replace function public.display_names(p_ids uuid[])
returns table (id uuid, name text)
language sql
stable
security definer
set search_path = public
as $$
  select u.id, public.derive_display_name(u.raw_user_meta_data, u.email)
  from auth.users u
  where u.id = any(p_ids);
$$;

revoke all on function public.display_names(uuid[]) from public, anon;
grant execute on function public.display_names(uuid[]) to authenticated;

-- Quick test (should show "Oliver Test" for oliver@test.com):
-- select * from public.display_names(array(select id from auth.users));
