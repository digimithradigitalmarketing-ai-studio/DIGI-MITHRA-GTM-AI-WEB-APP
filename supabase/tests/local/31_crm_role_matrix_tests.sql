-- 31_crm_role_matrix_tests.sql
-- Synthetic-only. Checks that the write rules the CRM screens rely on (src/lib/crm/roles.ts)
-- match what the database enforces, for companies, contacts, leads and clients.
--
-- Matrix under test (must match roles.ts):
--   companies write    admin, manager, editor
--   companies archive  admin only (guard trigger; manager and editor are refused with 42501)
--   contacts write     admin, manager, editor, support
--   leads write        admin, manager, editor, support
--   clients write      admin only
--   clients archive    admin only
--
-- Denials are reported two ways. A refused INSERT raises 42501 (RLS with check). A refused UPDATE
-- that RLS filters out affects zero rows and raises nothing, so the test checks for zero rows.
--
-- Fixtures: tenant E with workspace E1. Users: manager, editor, support, viewer, analyst in
-- E1, and a tenant admin (who maps to admin in every workspace). Runs in one transaction the
-- runner ends with ROLLBACK.

-- ----------------------------------------------------------------- helpers (temporary)
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

create function pg_temp.expect_denied(p_label text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when insufficient_privilege then
    null;
end $$;

create function pg_temp.affected(p_sql text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- A filtered UPDATE must touch zero rows. Anything else is a failure.
create function pg_temp.expect_zero(p_label text, p_sql text) returns void language plpgsql as $$
declare n bigint;
begin
  n := pg_temp.affected(p_sql);
  if n <> 0 then
    raise exception 'FAIL %: % rows were changed', p_label, n using errcode = 'P0100';
  end if;
end $$;

create function pg_temp.expect_one(p_label text, p_sql text) returns void language plpgsql as $$
declare n bigint;
begin
  n := pg_temp.affected(p_sql);
  if n <> 1 then
    raise exception 'FAIL %: expected 1 row, got %', p_label, n using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- fixtures (owner)
insert into auth.users (id, aud, role) values
  ('e0000000-0000-4000-8000-00000000e001', 'authenticated', 'authenticated'),  -- manager E1
  ('e0000000-0000-4000-8000-00000000e002', 'authenticated', 'authenticated'),  -- editor E1
  ('e0000000-0000-4000-8000-00000000e003', 'authenticated', 'authenticated'),  -- support E1
  ('e0000000-0000-4000-8000-00000000e004', 'authenticated', 'authenticated'),  -- viewer E1
  ('e0000000-0000-4000-8000-00000000e005', 'authenticated', 'authenticated'),  -- analyst E1
  ('e0000000-0000-4000-8000-00000000e006', 'authenticated', 'authenticated');  -- tenant admin E

insert into public.tenants (id, name, slug, kind) values
  ('e1000000-0000-4000-8000-00000000000e', 'Tenant E', 'tenant-e', 'agency');

insert into public.workspaces (id, tenant_id, name, slug) values
  ('e2000000-0000-4000-8000-0000000000e1', 'e1000000-0000-4000-8000-00000000000e', 'E1', 'e1');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('e1000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-00000000e006', 'admin'),
  ('e1000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-00000000e001', 'viewer'),
  ('e1000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-00000000e002', 'viewer'),
  ('e1000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-00000000e003', 'viewer'),
  ('e1000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-00000000e004', 'viewer'),
  ('e1000000-0000-4000-8000-00000000000e', 'e0000000-0000-4000-8000-00000000e005', 'viewer');

insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values
  ('e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'e0000000-0000-4000-8000-00000000e001', 'manager'),
  ('e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'e0000000-0000-4000-8000-00000000e002', 'editor'),
  ('e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'e0000000-0000-4000-8000-00000000e003', 'support'),
  ('e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'e0000000-0000-4000-8000-00000000e004', 'viewer'),
  ('e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'e0000000-0000-4000-8000-00000000e005', 'analyst');

-- c1: company that will be archived. c3: company with no client yet, used by client inserts.
insert into public.companies (id, tenant_id, workspace_id, name) values
  ('e4000000-0000-4000-8000-0000000000c1', 'e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'Matrix Co 1'),
  ('e4000000-0000-4000-8000-0000000000c3', 'e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'Matrix Co 3');

insert into public.clients (id, tenant_id, workspace_id, company_id, status) values
  ('e7000000-0000-4000-8000-0000000000c1', 'e1000000-0000-4000-8000-00000000000e', 'e2000000-0000-4000-8000-0000000000e1', 'e4000000-0000-4000-8000-0000000000c1', 'active');

-- ----------------------------------------------------------------- create matrix
-- Each check runs one insert per table. Allowed inserts must touch one row; denied inserts must
-- raise 42501. The company insert uses a fresh row each time, so no unique key collides.
create function pg_temp.check_creates(p_label text, p_user uuid,
  p_company boolean, p_contact boolean, p_lead boolean, p_client boolean) returns void language plpgsql as $$
begin
  perform pg_temp.act_as(p_user);

  if p_company then
    perform pg_temp.expect_one(p_label || ' company create',
      'insert into public.companies (tenant_id, workspace_id, name) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''New ' || p_label || ''')');
  else
    perform pg_temp.expect_denied(p_label || ' company create',
      'insert into public.companies (tenant_id, workspace_id, name) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''Denied ' || p_label || ''')');
  end if;

  if p_contact then
    perform pg_temp.expect_one(p_label || ' contact create',
      'insert into public.contacts (tenant_id, workspace_id, name) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''Contact ' || p_label || ''')');
  else
    perform pg_temp.expect_denied(p_label || ' contact create',
      'insert into public.contacts (tenant_id, workspace_id, name) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''Denied ' || p_label || ''')');
  end if;

  if p_lead then
    perform pg_temp.expect_one(p_label || ' lead create',
      'insert into public.leads (tenant_id, workspace_id, title) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''Lead ' || p_label || ''')');
  else
    perform pg_temp.expect_denied(p_label || ' lead create',
      'insert into public.leads (tenant_id, workspace_id, title) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''Denied ' || p_label || ''')');
  end if;

  -- Client create is tried against company c3, which has no client. Only an admin can succeed,
  -- and only once, so the unique company index is not exercised here.
  if p_client then
    perform pg_temp.expect_one(p_label || ' client create',
      'insert into public.clients (tenant_id, workspace_id, company_id) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''e4000000-0000-4000-8000-0000000000c3'')');
  else
    perform pg_temp.expect_denied(p_label || ' client create',
      'insert into public.clients (tenant_id, workspace_id, company_id) values (''e1000000-0000-4000-8000-00000000000e'', ''e2000000-0000-4000-8000-0000000000e1'', ''e4000000-0000-4000-8000-0000000000c3'')');
  end if;
end $$;

-- label, user, company, contact, lead, client
select pg_temp.check_creates('manager', 'e0000000-0000-4000-8000-00000000e001', true,  true,  true,  false);
select pg_temp.check_creates('editor',  'e0000000-0000-4000-8000-00000000e002', true,  true,  true,  false);
select pg_temp.check_creates('support', 'e0000000-0000-4000-8000-00000000e003', false, true,  true,  false);
select pg_temp.check_creates('viewer',  'e0000000-0000-4000-8000-00000000e004', false, false, false, false);
select pg_temp.check_creates('analyst', 'e0000000-0000-4000-8000-00000000e005', false, false, false, false);
select pg_temp.check_creates('admin',   'e0000000-0000-4000-8000-00000000e006', true,  true,  true,  true);

-- ----------------------------------------------------------------- archive matrix
-- Companies: only admin may set archived_at. Manager and editor pass RLS but the guard refuses
-- them (42501). Support, analyst and viewer are filtered out by RLS (zero rows).
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e001');
select pg_temp.expect_denied('manager archives company',
  $$update public.companies set archived_at = now() where id = 'e4000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e002');
select pg_temp.expect_denied('editor archives company',
  $$update public.companies set archived_at = now() where id = 'e4000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e003');
select pg_temp.expect_zero('support archives company',
  $$update public.companies set archived_at = now() where id = 'e4000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e004');
select pg_temp.expect_zero('viewer archives company',
  $$update public.companies set archived_at = now() where id = 'e4000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e005');
select pg_temp.expect_zero('analyst archives company',
  $$update public.companies set archived_at = now() where id = 'e4000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e006');
select pg_temp.expect_one('admin archives company',
  $$update public.companies set archived_at = now() where id = 'e4000000-0000-4000-8000-0000000000c1'$$);

-- Clients: admin only, for updates and archive. The manager is filtered out (zero rows).
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e001');
select pg_temp.expect_zero('manager changes client',
  $$update public.clients set services = 'hijack' where id = 'e7000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.expect_zero('manager archives client',
  $$update public.clients set archived_at = now() where id = 'e7000000-0000-4000-8000-0000000000c1'$$);
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e006');
select pg_temp.expect_one('admin changes client',
  $$update public.clients set services = 'Monthly plan' where id = 'e7000000-0000-4000-8000-0000000000c1'$$);

select pg_temp.act_as_postgres();
do $$ begin raise notice 'PASS 31_crm_role_matrix_tests'; end $$;
