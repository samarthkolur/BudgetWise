-- Grants Supabase applies automatically to the `authenticated` role.
--
-- Applied after the migrations so it covers every table and function they
-- created. RLS still governs which ROWS are visible; grants only govern which
-- TABLES may be addressed at all. Both have to be right — a grant without a
-- policy exposes nothing, and a policy without a grant is unreachable.

grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on all functions in schema public to authenticated;
