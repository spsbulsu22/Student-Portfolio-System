-- Table: class_members
-- Run in: INSTRUCTOR project only
-- student_id has no foreign key: students log in to the other project.

create table public.class_members (
  id             uuid primary key default gen_random_uuid(),
  class_id       uuid not null references public.classes (id) on delete cascade,
  student_id     uuid not null,
  student_name   text not null default '',
  student_number text not null default '',
  student_email  text not null,
  status         text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected', 'removed')),
  requested_at   timestamptz not null default now(),
  joined_at      timestamptz,
  unique (class_id, student_id)
);

create index on public.class_members (class_id, status);

alter table public.class_members enable row level security;

create policy "members_instructor_select" on public.class_members
  for select using (exists (
    select 1 from public.classes c
    where c.id = class_id and c.instructor_id = auth.uid()));

create policy "members_instructor_update" on public.class_members
  for update using (exists (
    select 1 from public.classes c
    where c.id = class_id and c.instructor_id = auth.uid()));
