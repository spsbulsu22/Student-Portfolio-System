-- Table: instructor_notifications (one row per task; Realtime enabled)
-- Run in: INSTRUCTOR project only

create table public.instructor_notifications (
  id            uuid primary key default gen_random_uuid(),
  instructor_id uuid not null references auth.users (id) on delete cascade,
  class_id      uuid references public.classes (id) on delete cascade,
  assignment_id uuid unique references public.assignments (id) on delete cascade,
  title         text not null default '',
  message       text not null default '',
  student_count integer not null default 0,
  is_read       boolean not null default false,
  updated_at    timestamptz not null default now()
);

create index on public.instructor_notifications (instructor_id, is_read);

alter table public.instructor_notifications enable row level security;

create policy "notif_instructor_select" on public.instructor_notifications
  for select using (instructor_id = auth.uid());

create policy "notif_instructor_update" on public.instructor_notifications
  for update using (instructor_id = auth.uid());

alter publication supabase_realtime add table public.instructor_notifications;
