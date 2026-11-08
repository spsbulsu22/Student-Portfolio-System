-- Table: assignments
-- Run in: INSTRUCTOR project only

create table public.assignments (
  id           uuid primary key default gen_random_uuid(),
  class_id     uuid not null references public.classes (id) on delete cascade,
  title        text not null,
  instructions text not null default '',
  requirements text not null default '',
  deadline     timestamptz,
  created_at   timestamptz not null default now()
);

create index on public.assignments (class_id, created_at desc);

alter table public.assignments enable row level security;

create policy "assignments_instructor_all" on public.assignments
  for all using (exists (
    select 1 from public.classes c
    where c.id = class_id and c.instructor_id = auth.uid()))
  with check (exists (
    select 1 from public.classes c
    where c.id = class_id and c.instructor_id = auth.uid()));
