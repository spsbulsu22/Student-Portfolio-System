-- Storage bucket: class-submissions (private, 50 MB)
-- Run in: INSTRUCTOR project only
-- Student uploads go through the student-classes Edge Function.

insert into storage.buckets (id, name, public, file_size_limit)
values ('class-submissions', 'class-submissions', false, 50000000)
on conflict (id) do nothing;

-- Instructors can read files of submissions in their own classes.
create policy "classsub_instructor_select" on storage.objects
  for select using (
    bucket_id = 'class-submissions' and exists (
      select 1 from public.submission_files f
      join public.submissions s on s.id = f.submission_id
      join public.assignments a on a.id = s.assignment_id
      join public.classes c on c.id = a.class_id
      where f.storage_path = name and c.instructor_id = auth.uid()));
