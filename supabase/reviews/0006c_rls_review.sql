-- 0006c_rls_review.sql
-- REVIEW ONLY. NOT A MIGRATION. NOT APPLIED TO ANY DATABASE.
-- This file is kept outside supabase/migrations/ so no migration runner picks it up.
--
-- Scope: the three production tables that have RLS enabled and no policies:
--   public.clients, public.deals, public.webhook_events
--
-- Findings from the review:
--   clients and deals: the policies already exist in 0006b_gtm_rls_completion.sql
--     (members read; admin manages clients; admin, manager and editor manage deals;
--     admin hard-deletes). 0006b is not applied to production. This file does not
--     add policies for those tables. It only re-checks the privileges and records the
--     access rules the review approved.
--   webhook_events: no code in this repository reads or writes it (src/, supabase/
--     migrations, supabase/tests searched). It is not in any migration here, and it
--     is not in the local base schema. Consumers outside this repository cannot be
--     ruled out from here, so this file only removes client-role privileges. It adds
--     no public policies, because nothing shows a client-side requirement.
--
-- Prerequisites before any execution (all required):
--   1. A verified production backup, recorded with its ID and timestamp.
--   2. Written approval from the project owner for this specific file.
--   3. The 0004b, 0006b, 0007a and 0007 review sequence has been run against a
--      replica of production, and the local suites in supabase/tests/local pass.
--
-- Idempotent. Every statement can run more than once.

-- 1. clients and deals: privileges.
--    Supabase's default grants give anon and authenticated every privilege on new
--    tables. TRUNCATE is not filtered by RLS. Keep only what the app uses.
revoke all on public.clients, public.deals from anon, authenticated;
grant select, insert, update, delete on public.clients, public.deals to authenticated;

-- 2. clients and deals: policies. Created only when missing, using the same
--    definitions as 0006b, so this file is safe to run before or after 0006b.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_read') then
    create policy clients_read on public.clients for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_insert') then
    create policy clients_insert on public.clients for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_update') then
    create policy clients_update on public.clients for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin')
      with check (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_delete') then
    create policy clients_delete on public.clients for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_read') then
    create policy deals_read on public.deals for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_insert') then
    create policy deals_insert on public.deals for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_update') then
    create policy deals_update on public.deals for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]))
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_delete') then
    create policy deals_delete on public.deals for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;
end $$;

-- 3. clients and deals: RLS stays on. Archive rules come from the guard_archive trigger
--    in 0006 and 0006b, which admins alone pass.
alter table public.clients enable row level security;
alter table public.deals enable row level security;

-- 4. webhook_events: keep it closed to the client Data API.
--    RLS stays enabled with no policies, so anon and authenticated get no rows.
--    Revoking the grants makes that explicit and stops a later policy from being
--    the only barrier. service_role is not touched, so a backend that uses the
--    service key keeps working.
--    Skipped if the table does not exist in the database being reviewed.
do $$
begin
  if to_regclass('public.webhook_events') is null then
    raise notice 'public.webhook_events not found; step 4 skipped';
    return;
  end if;
  execute 'alter table public.webhook_events enable row level security';
  execute 'revoke all on public.webhook_events from anon, authenticated';
end $$;

-- 5. Compatibility checks. Run these in the same session before and after the file.
--    Each must return zero rows, or the expected count noted here.
--    a) RLS is enabled on the three tables:
--       select relname, relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
--        where n.nspname = 'public' and relname in ('clients','deals','webhook_events');
--    b) Only the expected policies exist:
--       select tablename, policyname from pg_policies where schemaname = 'public'
--          and tablename in ('clients','deals','webhook_events') order by 1,2;
--       Expected: 8 rows for clients and deals, none for webhook_events.
--    c) anon has no privileges on any of the three:
--       select table_name, privilege_type from information_schema.role_table_grants
--        where grantee = 'anon' and table_schema = 'public'
--          and table_name in ('clients','deals','webhook_events');
--       Expected: zero rows.

-- Rollback: see supabase/reviews/0006c_rls_rollback.sql.
