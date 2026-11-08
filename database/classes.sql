-- Table: classes
-- Run in: INSTRUCTOR project only

create table public.classes (
  id              uuid primary key default gen_random_uuid(),
  instructor_id   uuid not null default auth.uid()
                  references auth.users (id) on delete cascade,
  name            text not null,
  description     text not null default '',
  instructor_name text not null default '',
  code            text not null unique
                  default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)),
  created_at      timestamptz not null default now()
);

alter table public.classes enable row level security;

create policy "classes_instructor_all" on public.classes
  for all using (instructor_id = auth.uid())
  with check (instructor_id = auth.uid());
