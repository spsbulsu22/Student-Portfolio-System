-- Table: user_files
-- Run in: BOTH projects (Student + Instructor)

create table public.user_files (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id) on delete cascade,
  role          text not null check (role in ('student', 'instructor')),
  name          text not null,
  original_name text not null,
  file_type     text not null,
  mime_type     text not null,
  size_bytes    bigint not null check (size_bytes > 0 and size_bytes <= 50000000),
  storage_path  text not null unique,
  visibility    text not null default 'private'
                check (visibility in ('private', 'public')),
  description   text,
  is_favorite   boolean not null default false,
  folder_id     uuid references public.portfolio_folders (id) on delete set null,
  created_at    timestamptz not null default now()
);

create index on public.user_files (owner_id, created_at desc);
create index on public.user_files (owner_id) where is_favorite;

alter table public.user_files enable row level security;

create policy "files_select_own" on public.user_files
  for select using (owner_id = auth.uid());
create policy "files_insert_own" on public.user_files
  for insert with check (owner_id = auth.uid());
create policy "files_update_own" on public.user_files
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "files_delete_own" on public.user_files
  for delete using (owner_id = auth.uid());
