-- 30_gtm_completion_tests.sql
-- Synthetic-only. Verifies the gaps that 0006b closes, plus the access matrix for
-- companies, clients and deals. Runs inside ONE transaction that the runner ends with
-- ROLLBACK. Each check raises FAIL on violation, so psql stops with a non-zero exit.
--
-- Fixtures:
--   Tenant C: owner u_owner_c (admin everywhere in C); workspace C1 (manager u_mgr_c,
--             editor u_edit_c, viewer u_view_c, support u_supp_c, analyst u_anal_c);
--             workspace C2 (no sales or read members).
--   Tenant D: owner u_owner_d (admin in D only); workspace D1.
--
-- Expected denials use SQLSTATE 42501 (RLS or guard), 23503 (foreign key) or the deal
-- stage trigger's P0001. Any other failure is a real failure.

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

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
end $$;

-- Passes only if the statement is denied. Uses P0100 for its own failure so the
-- handler below cannot swallow it.
create function pg_temp.expect_denied(p_label text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when insufficient_privilege or foreign_key_violation or raise_exception then
    null;
end $$;

-- Returns the number of rows a DML statement touched.
create function pg_temp.affected(p_sql text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- ----------------------------------------------------------------- 0. fixtures (owner)
insert into auth.users (id, aud, role) values
  ('c0000000-0000-4000-8000-00000000c001', 'authenticated', 'authenticated'),  -- owner C
  ('c0000000-0000-4000-8000-00000000c002', 'authenticated', 'authenticated'),  -- manager C1
  ('c0000000-0000-4000-8000-00000000c003', 'authenticated', 'authenticated'),  -- editor C1
  ('c0000000-0000-4000-8000-00000000c004', 'authenticated', 'authenticated'),  -- viewer C1
  ('c0000000-0000-4000-8000-00000000c005', 'authenticated', 'authenticated'),  -- support C1
  ('c0000000-0000-4000-8000-00000000c006', 'authenticated', 'authenticated'),  -- analyst C1
  ('d0000000-0000-4000-8000-00000000d001', 'authenticated', 'authenticated');  -- owner D

insert into public.tenants (id, name, slug, kind) values
  ('c1000000-0000-4000-8000-00000000000c', 'Tenant C', 'tenant-c', 'agency'),
  ('d1000000-0000-4000-8000-00000000000d', 'Tenant D', 'tenant-d', 'agency');

insert into public.workspaces (id, tenant_id, name, slug) values
  ('c2000000-0000-4000-8000-0000000000c1', 'c1000000-0000-4000-8000-00000000000c', 'C1', 'c1'),
  ('c2000000-0000-4000-8000-0000000000c2', 'c1000000-0000-4000-8000-00000000000c', 'C2', 'c2'),
  ('d2000000-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-00000000000d', 'D1', 'd1');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c001', 'owner'),
  ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c002', 'viewer'),
  ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c003', 'viewer'),
  ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c004', 'viewer'),
  ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c005', 'viewer'),
  ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c006', 'viewer'),
  ('d1000000-0000-4000-8000-00000000000d', 'd0000000-0000-4000-8000-00000000d001', 'owner');

insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values
  ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-00000000c002', 'manager'),
  ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-00000000c003', 'editor'),
  ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-00000000c004', 'viewer'),
  ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-00000000c005', 'support'),
  ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-00000000c006', 'analyst');

insert into public.pipeline_stages (id, tenant_id, workspace_id, name, "position", is_won, is_lost) values
  ('e1000000-0000-4000-8000-00000000c101', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Open C1', 1, false, false),
  ('e1000000-0000-4000-8000-00000000c102', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Won C1', 2, true, false),
  ('e1000000-0000-4000-8000-00000000c103', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Lost C1', 3, false, true),
  ('e1000000-0000-4000-8000-00000000c201', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c2', 'Open C2', 1, false, false),
  ('e1000000-0000-4000-8000-00000000d101', 'd1000000-0000-4000-8000-00000000000d', 'd2000000-0000-4000-8000-0000000000d1', 'Open D1', 1, false, false);

insert into public.companies (id, tenant_id, workspace_id, name, domain) values
  ('f1000000-0000-4000-8000-00000000c001', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Acme Fitness', 'acme.test'),
  ('f1000000-0000-4000-8000-00000000c002', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Beta Gym', 'beta.test'),
  ('f1000000-0000-4000-8000-00000000c201', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c2', 'C2 Company', 'c2co.test'),
  ('f1000000-0000-4000-8000-00000000d001', 'd1000000-0000-4000-8000-00000000000d', 'd2000000-0000-4000-8000-0000000000d1', 'Tenant D Company', 'd1co.test');

insert into public.clients (id, tenant_id, workspace_id, company_id, status) values
  ('f2000000-0000-4000-8000-00000000c001', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c001', 'active'),
  ('f2000000-0000-4000-8000-00000000c002', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c002', 'onboarding');

insert into public.deals (id, tenant_id, workspace_id, title, stage_id, company_id) values
  ('f3000000-0000-4000-8000-00000000c001', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Acme deal', 'e1000000-0000-4000-8000-00000000c101', 'f1000000-0000-4000-8000-00000000c001');

-- ----------------------------------------------------------------- P. privileges and policy shape
do $$
declare t text; p text;
begin
  foreach t in array array['public.companies', 'public.clients', 'public.deals'] loop
    foreach p in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
      if has_table_privilege('anon', t, p) then
        raise exception 'FAIL P1: anon holds % on %', p, t using errcode = 'P0100';
      end if;
      if p in ('truncate', 'references', 'trigger') and has_table_privilege('authenticated', t, p) then
        raise exception 'FAIL P2: authenticated holds % on % (bypasses RLS or not needed)', p, t using errcode = 'P0100';
      end if;
      if p in ('select', 'insert', 'update', 'delete') and not has_table_privilege('authenticated', t, p) then
        raise exception 'FAIL P3: authenticated lacks % on %', p, t using errcode = 'P0100';
      end if;
    end loop;
  end loop;
end $$;

do $$
begin
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('companies', 'clients', 'deals')) <> 12 then
    raise exception 'FAIL P4: expected 12 policies on companies, clients and deals' using errcode = 'P0100';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('companies', 'clients', 'deals')
             group by tablename, policyname having count(*) > 1) then
    raise exception 'FAIL P5: duplicate policy names on GTM tables' using errcode = 'P0100';
  end if;
end $$;

do $$
begin
  if (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid
       where c.relname in ('companies', 'clients', 'deals') and not t.tgisinternal
         and t.tgname in ('trg_guard_archive', 'trg_audit', 'trg_created_by', 'trg_updated')) <> 12 then
    raise exception 'FAIL P6: expected the four standard triggers on companies, clients and deals' using errcode = 'P0100';
  end if;
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'deals' and t.tgname = 'trg_deal_status' and not t.tgisinternal) then
    raise exception 'FAIL P7: trg_deal_status missing on deals' using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- V. viewer (read only, C1)
select pg_temp.act_as('c0000000-0000-4000-8000-00000000c004');
do $$
begin
  if (select count(*) from public.companies where workspace_id = 'c2000000-0000-4000-8000-0000000000c1') <> 2 then
    raise exception 'FAIL V1: viewer should read both C1 companies';
  end if;
  if (select count(*) from public.companies where workspace_id = 'c2000000-0000-4000-8000-0000000000c2') <> 0 then
    raise exception 'FAIL V2: viewer in C1 can read C2 companies';
  end if;
  if (select count(*) from public.clients) <> 2 or (select count(*) from public.deals) <> 1 then
    raise exception 'FAIL V3: viewer should read clients and deals in C1';
  end if;
end $$;
select pg_temp.expect_denied('V4 viewer insert company',
  $sql$insert into public.companies (tenant_id, workspace_id, name) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Viewer Co')$sql$);
select pg_temp.expect_denied('V5 viewer insert client',
  $sql$insert into public.clients (tenant_id, workspace_id, company_id) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c002')$sql$);
select pg_temp.expect_denied('V6 viewer insert deal',
  $sql$insert into public.deals (tenant_id, workspace_id, title, stage_id) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Viewer deal', 'e1000000-0000-4000-8000-00000000c101')$sql$);
do $$
begin
  if pg_temp.affected($sql$update public.companies set name = 'Hacked' where id = 'f1000000-0000-4000-8000-00000000c001'$sql$) <> 0 then
    raise exception 'FAIL V7: viewer updated a company';
  end if;
end $$;
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- S. support and analyst (read only)
select pg_temp.act_as('c0000000-0000-4000-8000-00000000c005');
select pg_temp.expect_denied('S1 support insert company',
  $sql$insert into public.companies (tenant_id, workspace_id, name) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Support Co')$sql$);
-- Update policies filter rows silently, so a read-only role gets zero rows back, not an error.
do $$
begin
  if pg_temp.affected($sql$update public.deals set archived_at = now() where id = 'f3000000-0000-4000-8000-00000000c001'$sql$) <> 0 then
    raise exception 'FAIL S2: support archived a deal';
  end if;
end $$;
select pg_temp.act_as_postgres();

select pg_temp.act_as('c0000000-0000-4000-8000-00000000c006');
select pg_temp.expect_denied('S3 analyst insert client',
  $sql$insert into public.clients (tenant_id, workspace_id, company_id) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c002')$sql$);
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- M. manager (sales, C1)
select pg_temp.act_as('c0000000-0000-4000-8000-00000000c002');
insert into public.companies (id, tenant_id, workspace_id, name, domain) values
  ('f1000000-0000-4000-8000-00000000c003', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Manager Co', 'mgr.test');
select pg_temp.expect_denied('M1 manager insert company in C2 (no membership)',
  $sql$insert into public.companies (tenant_id, workspace_id, name) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c2', 'Cross Ws')$sql$);
do $$
begin
  if (select count(*) from public.companies where workspace_id = 'c2000000-0000-4000-8000-0000000000c2') <> 0 then
    raise exception 'FAIL M2: manager in C1 can read C2 companies';
  end if;
end $$;
do $$
begin
  if pg_temp.affected($sql$update public.companies set name = 'Acme Renamed' where id = 'f1000000-0000-4000-8000-00000000c001'$sql$) <> 1 then
    raise exception 'FAIL M3: manager could not edit a company in C1';
  end if;
end $$;
select pg_temp.expect_denied('M4 manager archive company (admin only)',
  $sql$update public.companies set archived_at = now() where id = 'f1000000-0000-4000-8000-00000000c001'$sql$);
do $$
begin
  if pg_temp.affected($sql$delete from public.companies where id = 'f1000000-0000-4000-8000-00000000c002'$sql$) <> 0 then
    raise exception 'FAIL M5: manager hard-deleted a company';
  end if;
end $$;
select pg_temp.expect_denied('M6 manager insert client (admin only)',
  $sql$insert into public.clients (tenant_id, workspace_id, company_id) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c003')$sql$);
do $$
begin
  if pg_temp.affected($sql$update public.clients set status = 'active' where id = 'f2000000-0000-4000-8000-00000000c002'$sql$) <> 0 then
    raise exception 'FAIL M7: manager edited a client';
  end if;
  if pg_temp.affected($sql$delete from public.clients where id = 'f2000000-0000-4000-8000-00000000c002'$sql$) <> 0 then
    raise exception 'FAIL M8: manager deleted a client';
  end if;
end $$;
do $$
begin
  if pg_temp.affected($sql$update public.clients set archived_at = now() where id = 'f2000000-0000-4000-8000-00000000c001'$sql$) <> 0 then
    raise exception 'FAIL M9: manager archived a client (admin only)';
  end if;
end $$;
insert into public.deals (id, tenant_id, workspace_id, title, stage_id, company_id) values
  ('f3000000-0000-4000-8000-00000000c002', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Manager deal', 'e1000000-0000-4000-8000-00000000c101', 'f1000000-0000-4000-8000-00000000c001');
select pg_temp.expect_denied('M10 manager deal in a stage from C2',
  $sql$insert into public.deals (tenant_id, workspace_id, title, stage_id) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Cross stage', 'e1000000-0000-4000-8000-00000000c201')$sql$);
select pg_temp.expect_denied('M11 manager archive deal (admin only)',
  $sql$update public.deals set archived_at = now() where id = 'f3000000-0000-4000-8000-00000000c002'$sql$);
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- E. editor (sales, C1)
select pg_temp.act_as('c0000000-0000-4000-8000-00000000c003');
insert into public.companies (id, tenant_id, workspace_id, name) values
  ('f1000000-0000-4000-8000-00000000c004', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Editor Co');
select pg_temp.expect_denied('E1 editor archive company',
  $sql$update public.companies set archived_at = now() where id = 'f1000000-0000-4000-8000-00000000c004'$sql$);
insert into public.deals (id, tenant_id, workspace_id, title, stage_id, status, closed_at)
  values ('f3000000-0000-4000-8000-00000000c003', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Forged status', 'e1000000-0000-4000-8000-00000000c101', 'won', now());
do $$
begin
  if (select status from public.deals where id = 'f3000000-0000-4000-8000-00000000c003') <> 'open' then
    raise exception 'FAIL E3: deal status was not recalculated from the stage';
  end if;
end $$;
do $$
begin
  if pg_temp.affected($sql$update public.deals set stage_id = 'e1000000-0000-4000-8000-00000000c102' where id = 'f3000000-0000-4000-8000-00000000c003'$sql$) <> 1 then
    raise exception 'FAIL E4: editor could not move a deal to a won stage';
  end if;
end $$;
select pg_temp.act_as_postgres();
do $$
begin
  if (select status from public.deals where id = 'f3000000-0000-4000-8000-00000000c003') <> 'won'
     or (select closed_at from public.deals where id = 'f3000000-0000-4000-8000-00000000c003') is null then
    raise exception 'FAIL E5: moving a deal to a won stage did not set status and closed_at';
  end if;
  if (select created_by from public.companies where id = 'f1000000-0000-4000-8000-00000000c004') <> 'c0000000-0000-4000-8000-00000000c003' then
    raise exception 'FAIL E6: created_by was not set to the editor who created the company';
  end if;
end $$;

-- ----------------------------------------------------------------- A. admin (tenant owner, C)
select pg_temp.act_as('c0000000-0000-4000-8000-00000000c001');
update public.companies set archived_at = now() where id = 'f1000000-0000-4000-8000-00000000c004';
select pg_temp.act_as_postgres();
do $$
begin
  if (select archived_by from public.companies where id = 'f1000000-0000-4000-8000-00000000c004') <> 'c0000000-0000-4000-8000-00000000c001' then
    raise exception 'FAIL A1: archived_by was not set to the admin';
  end if;
end $$;

select pg_temp.act_as('c0000000-0000-4000-8000-00000000c001');
update public.companies set archived_at = null where id = 'f1000000-0000-4000-8000-00000000c004';
select pg_temp.act_as_postgres();
do $$
begin
  if (select archived_at is not null or archived_by is not null from public.companies where id = 'f1000000-0000-4000-8000-00000000c004') then
    raise exception 'FAIL A2: admin restore did not clear archived fields';
  end if;
end $$;

select pg_temp.act_as('c0000000-0000-4000-8000-00000000c001');
insert into public.clients (id, tenant_id, workspace_id, company_id, status) values
  ('f2000000-0000-4000-8000-00000000c003', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c004', 'onboarding');
select pg_temp.expect_denied('A3 admin hard-deletes a company that a client depends on',
  $sql$delete from public.companies where id = 'f1000000-0000-4000-8000-00000000c002'$sql$);
select pg_temp.expect_denied('A4 admin client points at a company in another workspace',
  $sql$insert into public.clients (tenant_id, workspace_id, company_id) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'f1000000-0000-4000-8000-00000000c201')$sql$);
do $$
begin
  if pg_temp.affected($sql$delete from public.companies where id = 'f1000000-0000-4000-8000-00000000c003'$sql$) <> 1 then
    raise exception 'FAIL A5: admin could not hard-delete an unreferenced company';
  end if;
end $$;
do $$
begin
  if pg_temp.affected($sql$update public.deals set stage_id = 'e1000000-0000-4000-8000-00000000c103' where id = 'f3000000-0000-4000-8000-00000000c003'$sql$) <> 1 then
    raise exception 'FAIL A6: admin could not move a deal to a lost stage';
  end if;
  if pg_temp.affected($sql$update public.deals set lost_reason = 'Budget' where id = 'f3000000-0000-4000-8000-00000000c003'$sql$) <> 1 then
    raise exception 'FAIL A7: admin could not record a lost reason';
  end if;
end $$;
select pg_temp.act_as_postgres();
do $$
begin
  if (select status from public.deals where id = 'f3000000-0000-4000-8000-00000000c003') <> 'lost' then
    raise exception 'FAIL A8: deal status did not follow the lost stage';
  end if;
  if not exists (select 1 from public.audit_logs where entity = 'companies' and tenant_id = 'c1000000-0000-4000-8000-00000000000c' and action = 'update') then
    raise exception 'FAIL A9: no audit rows for company updates';
  end if;
end $$;
select pg_temp.act_as('c0000000-0000-4000-8000-00000000c001');
do $$
begin
  if pg_temp.affected($sql$update public.clients set archived_at = now() where id = 'f2000000-0000-4000-8000-00000000c001'$sql$) <> 1 then
    raise exception 'FAIL A10: admin could not archive a client';
  end if;
  if pg_temp.affected($sql$delete from public.deals where id = 'f3000000-0000-4000-8000-00000000c002'$sql$) <> 1 then
    raise exception 'FAIL A11: admin could not delete a deal';
  end if;
end $$;
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- T. tenant isolation (owner D)
select pg_temp.act_as('d0000000-0000-4000-8000-00000000d001');
do $$
begin
  if (select count(*) from public.companies where tenant_id = 'c1000000-0000-4000-8000-00000000000c') <> 0
     or (select count(*) from public.clients where tenant_id = 'c1000000-0000-4000-8000-00000000000c') <> 0
     or (select count(*) from public.deals where tenant_id = 'c1000000-0000-4000-8000-00000000000c') <> 0 then
    raise exception 'FAIL T1: tenant D can read tenant C rows';
  end if;
end $$;
do $$
begin
  if pg_temp.affected($sql$update public.companies set name = 'Cross tenant' where tenant_id = 'c1000000-0000-4000-8000-00000000000c'$sql$) <> 0 then
    raise exception 'FAIL T2: tenant D updated tenant C rows';
  end if;
end $$;
select pg_temp.expect_denied('T3 tenant D inserts into tenant C',
  $sql$insert into public.companies (tenant_id, workspace_id, name) values
       ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'Injected')$sql$);
insert into public.companies (id, tenant_id, workspace_id, name) values
  ('f1000000-0000-4000-8000-00000000d002', 'd1000000-0000-4000-8000-00000000000d', 'd2000000-0000-4000-8000-0000000000d1', 'D own company');
select pg_temp.act_as_postgres();

select pg_temp.act_as('c0000000-0000-4000-8000-00000000c001');
do $$
begin
  if (select count(*) from public.companies where tenant_id = 'd1000000-0000-4000-8000-00000000000d') <> 0 then
    raise exception 'FAIL T4: tenant C owner can read tenant D rows';
  end if;
end $$;
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- X. anon
select pg_temp.act_as_anon();
select pg_temp.expect_denied('X1 anon reads companies', 'select count(*) from public.companies');
select pg_temp.expect_denied('X2 anon reads clients', 'select count(*) from public.clients');
select pg_temp.expect_denied('X3 anon reads deals', 'select count(*) from public.deals');
select pg_temp.act_as_postgres();

select 'gtm completion checks passed' as result;
