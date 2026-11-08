-- Table: submissions
-- Run in: INSTRUCTOR project only
-- student_id has no foreign key: students log in to the other project.

create table public.submissions (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  student_id    uuid not null,
  student_name  text not null default '',
  student_email text not null default '',
  status        text not null default 'draft'
                check (status in ('draft', 'submitted', 'reviewed')),
  feedback      text,
  submitted_at  timestamptz,
  reviewed_at   timestamptz,
  unique (assignment_id, student_id)
);

alter table public.submissions enable row level security;

-- Drafts are never visible to the instructor.
create policy "submissions_instructor_select" on public.submissions
  for select using (
    status <> 'draft' and exists (
      select 1 from public.assignments a
      join public.classes c on c.id = a.class_id
      where a.id = assignment_id and c.instructor_id = auth.uid()));

create policy "submissions_instructor_update" on public.submissions
  for update using (
    status <> 'draft' and exists (
      select 1 from public.assignments a
      join public.classes c on c.id = a.class_id
      where a.id = assignment_id and c.instructor_id = auth.uid()));
