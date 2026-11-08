-- Table: portfolio_folders
-- Run in: BOTH projects (Student + Instructor)
-- Must be created before user_files.

create table public.portfolio_folders (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references auth.users (id) on delete cascade,
  role       text not null check (role in ('student', 'instructor')),
  name       text not null,
  parent_id  uuid references public.portfolio_folders (id) on delete cascade,
  created_at timestamptz not null default now()
);

create index on public.portfolio_folders (owner_id, created_at desc);

alter table public.portfolio_folders enable row level security;

create policy "folders_owner_all" on public.portfolio_folders
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());
