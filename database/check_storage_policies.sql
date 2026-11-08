-- Diagnostic: lists the current policies on storage.objects.
-- Run it in the Supabase SQL Editor and send me the result if the fix
-- in fix_public_file_access.sql does not solve the problem.

select policyname, cmd, roles, qual
from pg_policies
where schemaname = 'storage' and tablename = 'objects';
