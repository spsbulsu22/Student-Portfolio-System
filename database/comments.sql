-- =============================================================================
-- Community comments + comment likes
-- Run this ONCE in the SQL editor of BOTH Supabase projects (student and
-- instructor), after file_upload.sql and community.sql.
--
-- Design: the two tables have Row Level Security ON and NO policies/grants, so
-- the app can never read or write them directly. Everything goes through the
-- four SECURITY DEFINER functions below, which check that the caller is logged
-- in and that the file is public (or the caller's own file).
-- =============================================================================

create table if not exists public.community_comments (
  id         uuid primary key default gen_random_uuid(),
  file_id    uuid not null references public.user_files (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  body       text not null
             check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);

create index if not exists community_comments_file_idx
  on public.community_comments (file_id, created_at desc);

create table if not exists public.community_comment_likes (
  comment_id uuid not null
             references public.community_comments (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

alter table public.community_comments      enable row level security;
alter table public.community_comment_likes enable row level security;

revoke all on public.community_comments      from anon, authenticated;
revoke all on public.community_comment_likes from anon, authenticated;

-- -----------------------------------------------------------------------------
-- The name shown for a commenter: the ACCOUNT name, never the email.
-- Looks at the account's user_metadata (full_name / name, where the app saves
-- it) and then at the profiles row (full_name / name / display_name /
-- username). to_jsonb() is used so this still works whichever of those
-- profile columns exist in your project.
-- -----------------------------------------------------------------------------
create or replace function public.community_display_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select coalesce(
              nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
              nullif(btrim(u.raw_user_meta_data ->> 'name'), ''))
       from auth.users u
      where u.id = p_user_id),
    (select coalesce(
              nullif(btrim(j ->> 'full_name'), ''),
              nullif(btrim(j ->> 'name'), ''),
              nullif(btrim(j ->> 'display_name'), ''),
              nullif(btrim(j ->> 'username'), ''))
       from (select to_jsonb(p) as j
               from public.profiles p
              where p.id = p_user_id) t),
    'Unknown user');
$$;

revoke all on function public.community_display_name(uuid) from public, anon;
grant execute on function public.community_display_name(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- List: comments of one file (newest first; the app re-sorts).
-- The name shown is the account name (auth user_metadata full_name / name, the
-- same place the app reads it from). Never the email.
-- -----------------------------------------------------------------------------
create or replace function public.community_file_comments(p_file_id uuid)
returns table (
  id          uuid,
  user_id     uuid,
  body        text,
  created_at  timestamptz,
  like_count  bigint,
  liked_by_me boolean,
  author_name text,
  is_mine     boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id,
    c.user_id,
    c.body,
    c.created_at,
    (select count(*) from public.community_comment_likes l
      where l.comment_id = c.id),
    exists (select 1 from public.community_comment_likes l
             where l.comment_id = c.id and l.user_id = auth.uid()),
    public.community_display_name(c.user_id),
    c.user_id = auth.uid()
  from public.community_comments c
  where c.file_id = p_file_id
    and auth.uid() is not null
    and exists (
      select 1 from public.user_files f
       where f.id = p_file_id
         and (f.visibility = 'public' or f.owner_id = auth.uid())
    )
  order by c.created_at desc;
$$;

-- -----------------------------------------------------------------------------
-- Add a comment; returns the new row in the same shape as the list.
-- -----------------------------------------------------------------------------
create or replace function public.add_community_comment(
  p_file_id uuid,
  p_body    text
)
returns table (
  id          uuid,
  user_id     uuid,
  body        text,
  created_at  timestamptz,
  like_count  bigint,
  liked_by_me boolean,
  author_name text,
  is_mine     boolean
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_id   uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 500 then
    raise exception 'invalid_comment' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.user_files f
     where f.id = p_file_id
       and (f.visibility = 'public' or f.owner_id = auth.uid())
  ) then
    raise exception 'file_not_found' using errcode = 'P0002';
  end if;

  insert into public.community_comments (file_id, user_id, body)
  values (p_file_id, auth.uid(), v_body)
  returning community_comments.id into v_id;

  return query
    select x.id, x.user_id, x.body, x.created_at, x.like_count,
           x.liked_by_me, x.author_name, x.is_mine
      from public.community_file_comments(p_file_id) x
     where x.id = v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Like / unlike (toggle). Returns the new state and the new total.
-- -----------------------------------------------------------------------------
create or replace function public.toggle_community_comment_like(
  p_comment_id uuid
)
returns table (liked boolean, like_count bigint)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  v_deleted int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not exists (
    select 1
      from public.community_comments c
      join public.user_files f on f.id = c.file_id
     where c.id = p_comment_id
       and (f.visibility = 'public' or f.owner_id = auth.uid())
  ) then
    raise exception 'comment_not_found' using errcode = 'P0002';
  end if;

  delete from public.community_comment_likes l
   where l.comment_id = p_comment_id and l.user_id = auth.uid();
  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    insert into public.community_comment_likes (comment_id, user_id)
    values (p_comment_id, auth.uid())
    on conflict do nothing;
  end if;

  return query
    select v_deleted = 0,
           (select count(*) from public.community_comment_likes l
             where l.comment_id = p_comment_id);
end;
$$;

-- -----------------------------------------------------------------------------
-- Delete: the author of the comment, or the owner of the file.
-- -----------------------------------------------------------------------------
create or replace function public.delete_community_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted int;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  delete from public.community_comments c
   using public.user_files f
   where c.id = p_comment_id
     and f.id = c.file_id
     and (c.user_id = auth.uid() or f.owner_id = auth.uid());
  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.community_file_comments(uuid)          from public, anon;
revoke all on function public.add_community_comment(uuid, text)      from public, anon;
revoke all on function public.toggle_community_comment_like(uuid)    from public, anon;
revoke all on function public.delete_community_comment(uuid)         from public, anon;

grant execute on function public.community_file_comments(uuid)       to authenticated;
grant execute on function public.add_community_comment(uuid, text)   to authenticated;
grant execute on function public.toggle_community_comment_like(uuid) to authenticated;
grant execute on function public.delete_community_comment(uuid)      to authenticated;
