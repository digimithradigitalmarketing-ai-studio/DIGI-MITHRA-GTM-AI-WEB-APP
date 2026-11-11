-- 39b_0006b_rollback_fail_closed.sql
-- Run AFTER supabase/rollbacks/0006b_down.sql (path F). Synthetic data only, inside one transaction the runner ends
-- with ROLLBACK. It checks what the rollback leaves behind for application roles, so the difference from the applied
-- state is known and not assumed.
--
-- Expected after the rollback:
--   * clients and deals keep RLS enabled but have NO policies. Every app role reads zero rows and every write is refused.
--     The application's readiness check then reports the module as not configured.
--   * companies keeps the four 0006 policies, but the 0006b archive guard and audit trigger are gone. An editor or manager
--     who passes the companies_update policy can archive a company. This is an observed limitation of the rollback, recorded
--     here so it is visible. It is not a fix.
--   * anon holds no privilege on the three tables (grants are not restored by the rollback).

create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.act_as_postgres() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

create function pg_temp.expect_error(p_label text, p_sql text, p_code text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when others then
    if sqlstate = 'P0100' then raise; end if;
    if sqlstate <> p_code then
      raise exception 'FAIL %: expected SQLSTATE %, got % (%)', p_label, p_code, sqlstate, sqlerrm using errcode = 'P0100';
    end if;
end $$;

create function pg_temp.expect_count(p_label text, p_sql text, p_expected bigint) returns void language plpgsql as $$
declare n bigint;
begin
  execute p_sql into n;
  if n is distinct from p_expected then
    raise exception 'FAIL %: expected %, got %', p_label, p_expected, n using errcode = 'P0100';
  end if;
end $$;

create function pg_temp.expect_zero(p_label text, p_sql text) returns void language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL %: % rows changed', p_label, n using errcode = 'P0100'; end if;
end $$;

-- Fixture (as postgres): one tenant, one workspace, an owner and an editor, one company and one client and one deal.
insert into auth.users (id, aud, role) values
  ('b0000000-0000-4000-8000-0000000000e1', 'authenticated', 'authenticated'),
  ('b0000000-0000-4000-8000-0000000000e2', 'authenticated', 'authenticated');
insert into public.tenants (id, name, slug, kind) values ('b1000000-0000-4000-8000-0000000000c0', 'RB Tenant', 'rb-tenant', 'agency');
insert into public.workspaces (id, tenant_id, name, slug) values ('b2000000-0000-4000-8000-0000000000c1', 'b1000000-0000-4000-8000-0000000000c0', 'RB1', 'rb1');
insert into public.tenant_members (tenant_id, user_id, role) values
  ('b1000000-0000-4000-8000-0000000000c0', 'b0000000-0000-4000-8000-0000000000e1', 'owner'),
  ('b1000000-0000-4000-8000-0000000000c0', 'b0000000-0000-4000-8000-0000000000e2', 'viewer');
insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values
  ('b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'b0000000-0000-4000-8000-0000000000e2', 'editor');
insert into public.pipeline_stages (id, tenant_id, workspace_id, name, "position", is_won, is_lost) values
  ('b5000000-0000-4000-8000-0000000000c1', 'b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'Open RB1', 1, false, false);
insert into public.companies (id, tenant_id, workspace_id, name) values
  ('b6000000-0000-4000-8000-0000000000c1', 'b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'RB Co 1'),
  ('b6000000-0000-4000-8000-0000000000c2', 'b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'RB Co 2');
insert into public.clients (id, tenant_id, workspace_id, company_id, status) values
  ('b7000000-0000-4000-8000-0000000000c1', 'b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'b6000000-0000-4000-8000-0000000000c1', 'active');
insert into public.deals (id, tenant_id, workspace_id, title, stage_id) values
  ('b8000000-0000-4000-8000-0000000000c1', 'b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'RB deal', 'b5000000-0000-4000-8000-0000000000c1');

-- 1. Clients and deals fail closed for every app role, including the tenant owner.
select pg_temp.act_as('b0000000-0000-4000-8000-0000000000e1');
select pg_temp.expect_count('owner reads clients after rollback', 'select count(*) from public.clients', 0);
select pg_temp.expect_count('owner reads deals after rollback',   'select count(*) from public.deals', 0);
select pg_temp.expect_error('owner inserts a client after rollback',
  $q$insert into public.clients (tenant_id, workspace_id, company_id) values ('b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'b6000000-0000-4000-8000-0000000000c2')$q$, '42501');
select pg_temp.expect_error('owner inserts a deal after rollback',
  $q$insert into public.deals (tenant_id, workspace_id, title, stage_id) values ('b1000000-0000-4000-8000-0000000000c0', 'b2000000-0000-4000-8000-0000000000c1', 'x', 'b5000000-0000-4000-8000-0000000000c1')$q$, '42501');
select pg_temp.expect_zero('owner updates a client after rollback', $q$update public.clients set status = 'x' where id = 'b7000000-0000-4000-8000-0000000000c1'$q$);
select pg_temp.expect_zero('owner deletes a deal after rollback',   $q$delete from public.deals where id = 'b8000000-0000-4000-8000-0000000000c1'$q$);

select pg_temp.act_as('b0000000-0000-4000-8000-0000000000e2');
select pg_temp.expect_count('editor reads clients after rollback', 'select count(*) from public.clients', 0);
select pg_temp.expect_count('editor reads deals after rollback',   'select count(*) from public.deals', 0);

-- 2. anon has no privilege on the three tables (not restored by the rollback).
select pg_temp.act_as_postgres();
set local role anon;
do $$
begin
  begin
    perform 1 from public.clients;
    raise exception 'FAIL 2: anon read clients after rollback' using errcode = 'P0100';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 3. Companies keep RLS and the 0006 policies, but the 0006b archive guard is gone. Observed limitation, asserted so it is visible.
select pg_temp.act_as('b0000000-0000-4000-8000-0000000000e2');
select pg_temp.expect_count('editor reads companies after rollback (0006 policy)', 'select count(*) from public.companies', 2);
-- The editor passes companies_update and nothing refuses the archive now that guard_archive is gone (observed).
select pg_temp.expect_count('editor archives a company after rollback (observed: guard removed)',
  $q$with u as (update public.companies set archived_at = now() where id = 'b6000000-0000-4000-8000-0000000000c2' returning 1) select count(*) from u$q$, 1);

select pg_temp.act_as_postgres();
do $$ begin raise notice 'PASS 39b_0006b_rollback_fail_closed (includes the observed archive-guard limitation)'; end $$;
