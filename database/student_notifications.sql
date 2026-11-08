-- Table: student_notifications  (ASSUMED structure)
-- Run in: INSTRUCTOR project only
-- Assumption: the app only reaches this data through the
-- "student-notifications" Edge Function, so its real structure is not visible.

create table public.student_notifications (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null,
  type          text not null default '',
  title         text not null default '',
  message       text not null default '',
  class_id      uuid references public.classes (id) on delete cascade,
  assignment_id uuid references public.assignments (id) on delete cascade,
  is_read       boolean not null default false,
  created_at    timestamptz not null default now()
);

create index on public.student_notifications (student_id, is_read);

alter table public.student_notifications enable row level security;
-- No policies: only the Edge Function (service role) reads/writes this table.
