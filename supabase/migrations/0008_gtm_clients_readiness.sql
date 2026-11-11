-- 0008_gtm_clients_readiness.sql (v2)
-- Additive. Creates one read-only function that the Clients screens call to decide whether the
-- clients table is ready. It returns booleans only: no table names, policy text, role lists or SQL.
-- The app reads the flags on the server and shows a generic "not configured" message.
--
-- Security properties (each checked by supabase/tests/local/32_clients_readiness_tests.sql):
--   * SECURITY INVOKER. It reads catalogs and the caller's privileges, and it reads no rows.
--   * EXECUTE is granted to authenticated only. PUBLIC and anon are revoked explicitly, and the
--     function reports whether either still has EXECUTE, so a later grant shows up as not configured.
--   * A policy counts only when it has the exact name the migrations create, the exact command, roles
--     exactly {authenticated}, and an expression that calls app_private.ws_role. An "ALL" policy, an
--     open "using (true)" policy, or a policy under another name does not count.
--   * Any policy that applies to anon or PUBLIC on clients is reported, and it blocks readiness.
--   * anon must hold no table privilege at all on clients (SELECT, INSERT, UPDATE, DELETE, TRUNCATE,
--     REFERENCES or TRIGGER). authenticated must hold SELECT, INSERT, UPDATE and DELETE.
--
-- Rollback: supabase/rollbacks/0008_down.sql. It drops the function and nothing else.
--
-- Prerequisites (R4): public.clients and app_private.ws_role(uuid, uuid). It does not need 0004b, 0006b, 0007a or 0007.
-- Until 0006b creates the clients policies, the function reports not_configured. That is expected, not an error.

-- 0. Preflight (R4). Stops before any change when a prerequisite is missing.
do $$
declare
  v_missing text := '';
begin
  if to_regclass('public.clients') is null then
    v_missing := v_missing || ' table public.clients (0004);';
  end if;
  if to_regprocedure('app_private.ws_role(uuid,uuid)') is null then
    v_missing := v_missing || ' function app_private.ws_role(uuid,uuid) (base);';
  end if;
  if v_missing <> '' then
    raise exception 'preflight failed for 0008; missing:%. No change was made.', v_missing using errcode = '42P01';
  end if;
end $$;

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
         and p.policyname = 'clients_read' and p.cmd = 'SELECT'
         and p.roles = array['authenticated']::name[]
         and coalesce(p.qual, '') like '%ws_role%'),
    'policy_insert', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.policyname = 'clients_insert' and p.cmd = 'INSERT'
         and p.roles = array['authenticated']::name[]
         and coalesce(p.with_check, '') like '%ws_role%'),
    'policy_update', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.policyname = 'clients_update' and p.cmd = 'UPDATE'
         and p.roles = array['authenticated']::name[]
         -- USING governs which rows an UPDATE may touch. Postgres reuses it as the check when WITH CHECK is absent.
         and coalesce(p.qual, '') like '%ws_role%'),
    'policy_delete', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.policyname = 'clients_delete' and p.cmd = 'DELETE'
         and p.roles = array['authenticated']::name[]
         and coalesce(p.qual, '') like '%ws_role%'),

    'grant_select', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'SELECT'), false),
    'grant_insert', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'INSERT'), false),
    'grant_update', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'UPDATE'), false),
    'grant_delete', coalesce(has_table_privilege('authenticated', to_regclass('public.clients'), 'DELETE'), false),

    -- Must be false: anon holds no table privilege of any kind on clients. has_table_privilege with a
    -- comma list is true if any listed privilege is held.
    'anon_has_any_privilege', coalesce(has_table_privilege('anon', to_regclass('public.clients'),
      'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'), false),

    -- Must be false: no policy on clients applies to anon or PUBLIC.
    'anon_or_public_policy', exists (
      select 1 from pg_catalog.pg_policies p
       where p.schemaname = 'public' and p.tablename = 'clients'
         and p.roles && array['anon', 'public']::name[]),

    -- Must be true: this function is SECURITY INVOKER.
    'function_security_invoker', coalesce((
      select not p.prosecdef from pg_catalog.pg_proc p
       where p.oid = 'public.clients_readiness()'::regprocedure), false),

    -- Must be false: PUBLIC has no EXECUTE on this function (an ACL entry with grantee 0 is PUBLIC).
    'public_execute', coalesce((
      select exists (
        select 1 from pg_catalog.pg_proc p,
                      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = 'public.clients_readiness()'::regprocedure
           and a.grantee = 0 and a.privilege_type = 'EXECUTE')), true),

    -- Must be false: anon has no EXECUTE on this function.
    'anon_execute', coalesce(has_function_privilege('anon', 'public.clients_readiness()', 'EXECUTE'), true)
  );
$$;

revoke all on function public.clients_readiness() from public;
revoke all on function public.clients_readiness() from anon;
grant execute on function public.clients_readiness() to authenticated;
