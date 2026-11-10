-- 00_auth_shim.sql
-- Local stand-in for the parts of Supabase that RLS depends on: the anon,
-- authenticated and service_role roles, the auth schema (auth.uid() reads the JWT
-- claims exactly as Supabase does), and the default privileges Supabase applies to
-- new objects in public. Not part of any migration. Never run against production.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

create schema if not exists public;
create schema if not exists app_private;
create schema if not exists auth;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema app_private to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  aud text,
  role text,
  email text,
  created_at timestamptz not null default now()
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select ((nullif(current_setting('request.jwt.claims', true), ''))::jsonb ->> 'sub')::uuid
$$;

-- Supabase default privileges: new tables and functions in public are granted to the
-- API roles. These are the defaults recorded on the live project (pg_default_acl).
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant execute on functions to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
