-- 0008_gtm_clients_readiness.sql
-- Additive. Creates one read-only function that the Clients screens call to decide whether the
-- clients table is ready. It returns booleans only: no table names, policy text, role lists or
-- SQL. The app reads the flags on the server and shows a generic "not configured" message.
--
-- Security:
--   * SECURITY INVOKER. It reads catalogs and the caller's own privileges, and it reads no rows.
--   * EXECUTE is granted to authenticated only. PUBLIC and anon are revoked explicitly.
--   * The function never uses a service key and never widens access.
--
-- A policy counts as present only when it grants the right command to authenticated and its
-- expression calls app_private.ws_role. A permissive policy such as "using (true)" does not count.
--
-- Rollback: supabase/rollbacks/0008_down.sql. It drops the function and nothing else.

create or replace function public.clients_readiness()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'table_exists', to_regclass('public.clients') is not null,
    'rls_enabled', coalesce(
      (select c.relrowsecurity from pg_catalog.pg_class c where c.oid = to_regclass('public.clients')), false),
    'policy_select', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.cmd in ('SELECT', 'ALL') and 'authenticated'::name = any (p.roles)
         and coalesce(p.qual, '') like '%ws_role%'),
    'policy_insert', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.cmd in ('INSERT', 'ALL') and 'authenticated'::name = any (p.roles)
         and coalesce(p.with_check, '') like '%ws_role%'),
    'policy_update', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.cmd in ('UPDATE', 'ALL') and 'authenticated'::name = any (p.roles)
         -- USING governs which rows an UPDATE may touch. Postgres reuses it as the check when WITH CHECK is absent.
         and coalesce(p.qual, '') like '%ws_role%'),
    'policy_delete', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.cmd in ('DELETE', 'ALL') and 'authenticated'::name = any (p.roles)
         and coalesce(p.qual, '') like '%ws_role%'),
    'grant_select', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'SELECT'), false),
    'grant_insert', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'INSERT'), false),
    'grant_update', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'UPDATE'), false),
    'grant_delete', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'DELETE'), false),
    'anon_has_any_privilege', coalesce(
      has_table_privilege('anon', to_regclass('public.clients'), 'SELECT')
      or has_table_privilege('anon', to_regclass('public.clients'), 'INSERT')
      or has_table_privilege('anon', to_regclass('public.clients'), 'UPDATE')
      or has_table_privilege('anon', to_regclass('public.clients'), 'DELETE'), false)
  );
$$;

revoke all on function public.clients_readiness() from public;
revoke all on function public.clients_readiness() from anon;
grant execute on function public.clients_readiness() to authenticated;
