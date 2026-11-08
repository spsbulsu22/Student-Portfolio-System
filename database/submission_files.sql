-- Table: submission_files (with a trigger: max 10 files per submission)
-- Run in: INSTRUCTOR project only

create table public.submission_files (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id) on delete cascade,
  file_name     text not null,
  mime_type     text not null default '',
  size_bytes    bigint not null default 0,
  storage_path  text not null,
  is_draft      boolean not null default true,
  created_at    timestamptz not null default now()
);

create index on public.submission_files (submission_id);

alter table public.submission_files enable row level security;

create policy "subfiles_instructor_select" on public.submission_files
  for select using (is_draft = false and exists (
    select 1 from public.submissions s
    join public.assignments a on a.id = s.assignment_id
    join public.classes c on c.id = a.class_id
    where s.id = submission_id and c.instructor_id = auth.uid()));

create or replace function public.limit_submission_files()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.submission_files
      where submission_id = new.submission_id) >= 10 then
    raise exception 'A submission can have at most 10 files';
  end if;
  return new;
end
$$;

create trigger submission_files_limit
  before insert on public.submission_files
  for each row execute function public.limit_submission_files();
