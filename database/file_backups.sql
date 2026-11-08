-- Table: file_backups
-- Run in: BOTH projects (Student + Instructor)

create table public.file_backups (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references auth.users (id) on delete cascade,
  file_id       uuid references public.user_files (id) on delete set null,
  name          text not null,
  original_name text not null,
  file_type     text not null,
  mime_type     text not null,
  size_bytes    bigint not null,
  storage_path  text not null,
  created_at    timestamptz not null default now()
);

create index on public.file_backups (owner_id, created_at desc);

alter table public.file_backups enable row level security;

-- Writes are done by the manage-backups Edge Function (service role).
create policy "backups_select_own" on public.file_backups
  for select using (owner_id = auth.uid());
