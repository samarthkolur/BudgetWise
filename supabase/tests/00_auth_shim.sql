-- Test-only shim.
--
-- The migrations target Supabase, which supplies the `auth` schema, the
-- `auth.users` table, `auth.uid()` and the `authenticated` role. A bare
-- Postgres container has none of them, so this file recreates the minimum the
-- schema depends on — nothing more, so a migration that quietly relies on some
-- other piece of Supabase fails here rather than in production.
--
-- NEVER applied to a real project. supabase/migrations/ is the only thing that
-- runs against a live database.

create schema if not exists auth;

create table if not exists auth.users (
  id                 uuid primary key,
  email              text unique,
  raw_user_meta_data jsonb       not null default '{}'::jsonb,
  created_at         timestamptz not null default now()
);

-- Supabase derives auth.uid() from the request JWT. PostgREST exposes the
-- claims as GUCs, so reading the same GUC is a faithful stand-in: the test can
-- "become" a user by setting it.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$$;

grant usage on schema public to authenticated;
grant usage on schema auth to authenticated;
