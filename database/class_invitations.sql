-- Table: class_invitations
-- Run in: INSTRUCTOR project only

create table public.class_invitations (
  id            uuid primary key default gen_random_uuid(),
  class_id      uuid not null references public.classes (id) on delete cascade,
  invited_email text not null,
  status        text not null default 'pending'
                check (status in ('pending', 'accepted', 'declined')),
  expires_at    timestamptz not null default (now() + interval '7 days'),
  created_at    timestamptz not null default now(),
  unique (class_id, invited_email)
);

alter table public.class_invitations enable row level security;

create policy "invites_instructor_select" on public.class_invitations
  for select using (exists (
    select 1 from public.classes c
    where c.id = class_id and c.instructor_id = auth.uid()));

create policy "invites_instructor_insert" on public.class_invitations
  for insert with check (exists (
    select 1 from public.classes c
    where c.id = class_id and c.instructor_id = auth.uid()));
