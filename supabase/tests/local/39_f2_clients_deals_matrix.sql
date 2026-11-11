-- 39_f2_clients_deals_matrix.sql
-- F2 role matrix for clients, deals and companies. Synthetic data only. Runs inside ONE transaction that the
-- runner ends with ROLLBACK, so nothing persists. Requires 0006b to be applied (paths B, E and F after 0006b).
--
-- Expectations come from the 0006b policy definitions. Section 1 checks the policy text itself, so a changed
-- policy fails here before any behaviour is tested:
--   read              any workspace role, or a tenant owner or admin (app_private.ws_role is not null)
--   clients write    owner or admin only (insert, update, delete)
--   deals write      owner, admin, manager, editor (insert, update); owner or admin only (delete)
--   companies write  owner, admin, manager, editor (insert, update); owner or admin only (delete)
--   archive          owner or admin only. guard_archive raises 42501 for a manager or editor who passes RLS.
--
-- Each denial is checked at the database by its mechanism:
--   * a refused INSERT, or a row that fails WITH CHECK, raises 42501;
--   * a filtered UPDATE or DELETE affects zero rows (no error);
--   * a trigger refusal keeps its own SQLSTATE (sync_deal_status raises P0001; a composite foreign key raises 23503).
-- A test never passes because a button is hidden. Each role runs as the authenticated role with its own JWT.

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

-- The statement must be refused with exactly p_code. Any other outcome, including success, is a failure.
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

-- A filtered UPDATE or DELETE must touch zero rows.
create function pg_temp.expect_zero(p_label text, p_sql text) returns void language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FAIL %: % rows changed', p_label, n using errcode = 'P0100'; end if;
end $$;

-- An allowed write must touch exactly one row.
create function pg_temp.expect_one(p_label text, p_sql text) returns void language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'FAIL %: expected 1 row, got %', p_label, n using errcode = 'P0100'; end if;
end $$;

-- A count must equal the expected value.
create function pg_temp.expect_count(p_label text, p_sql text, p_expected bigint) returns void language plpgsql as $$
declare n bigint;
begin
  execute p_sql into n;
  if n is distinct from p_expected then
    raise exception 'FAIL %: expected %, got %', p_label, p_expected, n using errcode = 'P0100';
  end if;
end $$;

-- Policy text. Qual and check are joined, so one search covers both expressions. A missing policy is a failure,
-- never a NULL that would make a later check pass silently.
create function pg_temp.policy_text(p_table text, p_policy text) returns text language plpgsql stable as $$
declare v text;
begin
  select coalesce(qual, '') || ' ' || coalesce(with_check, '') into v
    from pg_policies where schemaname = 'public' and tablename = p_table and policyname = p_policy;
  if v is null then
    raise exception 'FAIL: policy %.% is missing', p_table, p_policy using errcode = 'P0100';
  end if;
  return v;
end $$;

-- ----------------------------------------------------------------- 1. policy shape (derived from 0006b)
select pg_temp.act_as_postgres();
do $$
declare
  t text;
  n int;
  txt text;
begin
  -- Anonymous holds no privilege on the three tables (0006b revokes it).
  foreach t in array array['clients', 'deals', 'companies'] loop
    if has_table_privilege('anon', 'public.' || t, 'SELECT') or has_table_privilege('anon', 'public.' || t, 'INSERT')
       or has_table_privilege('anon', 'public.' || t, 'UPDATE') or has_table_privilege('anon', 'public.' || t, 'DELETE') then
      raise exception 'FAIL 1: anon holds a privilege on %', t using errcode = 'P0100';
    end if;
  end loop;

  -- Exactly four policies per table (read, insert, update, delete); no extra permissive policy can widen access.
  foreach t in array array['clients', 'deals', 'companies'] loop
    select count(*) into n from pg_policies where schemaname = 'public' and tablename = t;
    if n <> 4 then raise exception 'FAIL 1: % has % policies, expected 4', t, n using errcode = 'P0100'; end if;
  end loop;

  -- clients: admin only for insert, update and delete. Manager, editor and the others must not appear.
  txt := pg_temp.policy_text('clients', 'clients_insert');
  if position('''admin''' in txt) = 0 or position('manager' in txt) > 0 or position('editor' in txt) > 0 then
    raise exception 'FAIL 1: clients_insert is not admin-only: %', txt using errcode = 'P0100';
  end if;
  txt := pg_temp.policy_text('clients', 'clients_update');
  if position('''admin''' in txt) = 0 or position('manager' in txt) > 0 or position('editor' in txt) > 0 then
    raise exception 'FAIL 1: clients_update is not admin-only: %', txt using errcode = 'P0100';
  end if;
  txt := pg_temp.policy_text('clients', 'clients_delete');
  if position('''admin''' in txt) = 0 or position('manager' in txt) > 0 then
    raise exception 'FAIL 1: clients_delete is not admin-only: %', txt using errcode = 'P0100';
  end if;

  -- deals and companies: insert and update allow admin, manager and editor; delete is admin only.
  foreach t in array array['deals', 'companies'] loop
    txt := pg_temp.policy_text(t, t || '_insert');
    if position('manager' in txt) = 0 or position('editor' in txt) = 0 or position('viewer' in txt) > 0 or position('support' in txt) > 0 then
      raise exception 'FAIL 1: %_insert write set is wrong: %', t, txt using errcode = 'P0100';
    end if;
    txt := pg_temp.policy_text(t, t || '_update');
    if position('manager' in txt) = 0 or position('editor' in txt) = 0 or position('viewer' in txt) > 0 or position('support' in txt) > 0 then
      raise exception 'FAIL 1: %_update write set is wrong: %', t, txt using errcode = 'P0100';
    end if;
    txt := pg_temp.policy_text(t, t || '_delete');
    if position('manager' in txt) > 0 or position('editor' in txt) > 0 or position('''admin''' in txt) = 0 then
      raise exception 'FAIL 1: %_delete is not admin-only: %', t, txt using errcode = 'P0100';
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------- 2. fixtures (postgres, bypasses RLS)
-- Tenant T has workspaces T1 and T2. Tenant B is a separate tenant with workspace B1.
-- Users: owner and admin (tenant owner/admin, so admin in every workspace of T), manager, editor, support,
-- analyst, viewer (workspace roles in T1), t2mgr (manager in T2 only), outsider (no membership), badmin (admin of tenant B).
create temp table f2_users (label text primary key, uid uuid not null) on commit drop;
insert into f2_users values
  ('owner',    'b0000000-0000-4000-8000-000000000001'),
  ('admin',    'b0000000-0000-4000-8000-000000000002'),
  ('manager',  'b0000000-0000-4000-8000-000000000003'),
  ('editor',   'b0000000-0000-4000-8000-000000000004'),
  ('support',  'b0000000-0000-4000-8000-000000000005'),
  ('analyst',  'b0000000-0000-4000-8000-000000000006'),
  ('viewer',   'b0000000-0000-4000-8000-000000000007'),
  ('outsider', 'b0000000-0000-4000-8000-000000000008'),
  ('badmin',   'b0000000-0000-4000-8000-000000000009'),
  ('t2mgr',    'b0000000-0000-4000-8000-000000000010'),
  -- Manager in T1, viewer in T2. Can read the T2 stage, so a move into T2 reaches the RLS check (not the stage check).
  ('multi',    'b0000000-0000-4000-8000-000000000011');

insert into auth.users (id, aud, role)
  select uid, 'authenticated', 'authenticated' from f2_users;

insert into public.tenants (id, name, slug, kind) values
  ('b1000000-0000-4000-8000-0000000000a0', 'Matrix T', 'matrix-t', 'agency'),
  ('b1000000-0000-4000-8000-0000000000b0', 'Matrix B', 'matrix-b', 'agency');

insert into public.workspaces (id, tenant_id, name, slug) values
  ('b2000000-0000-4000-8000-0000000000a1', 'b1000000-0000-4000-8000-0000000000a0', 'T1', 't1'),
  ('b2000000-0000-4000-8000-0000000000a2', 'b1000000-0000-4000-8000-0000000000a0', 'T2', 't2'),
  ('b2000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-0000000000b0', 'B1', 'b1');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000001', 'owner'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000002', 'admin'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000003', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000004', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000005', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000006', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000007', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000010', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b0000000-0000-4000-8000-000000000011', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000b0', 'b0000000-0000-4000-8000-000000000009', 'admin');

insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-000000000003', 'manager'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-000000000004', 'editor'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-000000000005', 'support'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-000000000006', 'analyst'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-000000000007', 'viewer'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a2', 'b0000000-0000-4000-8000-000000000010', 'manager'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-000000000011', 'manager'),
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a2', 'b0000000-0000-4000-8000-000000000011', 'viewer');

insert into public.pipeline_stages (id, tenant_id, workspace_id, name, "position", is_won, is_lost) values
  ('b5000000-0000-4000-8000-0000000000a1', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Open T1', 1, false, false),
  ('b5000000-0000-4000-8000-0000000000a2', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a2', 'Open T2', 1, false, false),
  -- A stage in tenant B. The move into tenant B needs it, so the stage trigger passes and the RLS check is what refuses.
  ('b5000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-0000000000b0', 'b2000000-0000-4000-8000-0000000000b1', 'Open B1', 1, false, false);

-- Shared rows. k1 has client c1 and deal d1. k2 has client c2 and deal d2. k5 has no client. d3 is the shared
-- delete target. d4 and k6 live in T2 and are used by the cross-workspace checks.
insert into public.companies (id, tenant_id, workspace_id, name) values
  ('b6000000-0000-4000-8000-0000000000a1', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Shared K1'),
  ('b6000000-0000-4000-8000-0000000000a2', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Shared K2'),
  ('b6000000-0000-4000-8000-0000000000a5', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Shared K5'),
  ('b6000000-0000-4000-8000-0000000000a6', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a2', 'T2 K6');

insert into public.clients (id, tenant_id, workspace_id, company_id, status) values
  ('b7000000-0000-4000-8000-0000000000a1', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b6000000-0000-4000-8000-0000000000a1', 'active'),
  ('b7000000-0000-4000-8000-0000000000a2', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'b6000000-0000-4000-8000-0000000000a2', 'active'),
  ('b7000000-0000-4000-8000-0000000000a4', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a2', 'b6000000-0000-4000-8000-0000000000a6', 'active');

insert into public.deals (id, tenant_id, workspace_id, title, stage_id, company_id) values
  ('b8000000-0000-4000-8000-0000000000a1', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Shared deal d1', 'b5000000-0000-4000-8000-0000000000a1', 'b6000000-0000-4000-8000-0000000000a1'),
  ('b8000000-0000-4000-8000-0000000000a2', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Shared deal d2', 'b5000000-0000-4000-8000-0000000000a1', 'b6000000-0000-4000-8000-0000000000a2'),
  ('b8000000-0000-4000-8000-0000000000a3', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Shared deal d3', 'b5000000-0000-4000-8000-0000000000a1', null),
  ('b8000000-0000-4000-8000-0000000000a4', 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a2', 'T2 deal d4', 'b5000000-0000-4000-8000-0000000000a2', null);


-- ----------------------------------------------------------------- 3. READ matrix (before any write)
-- Expected counts come from the policy: any workspace role or tenant owner/admin can read. Tenant owners and admins
-- read every workspace of their tenant. A workspace-only role reads only its own workspace.
-- Counts are taken before any per-role companies are added, so the T1 company totals are the shared three.
create temp table f2_read (label text primary key, t1_co bigint, t1_cl bigint, t1_de bigint, t2_co bigint, t2_cl bigint, t2_de bigint) on commit drop;
insert into f2_read values
  ('owner',    3, 2, 3, 1, 1, 1),
  ('admin',    3, 2, 3, 1, 1, 1),
  ('manager',  3, 2, 3, 0, 0, 0),
  ('editor',   3, 2, 3, 0, 0, 0),
  ('support',  3, 2, 3, 0, 0, 0),
  ('analyst',  3, 2, 3, 0, 0, 0),
  ('viewer',   3, 2, 3, 0, 0, 0),
  ('outsider', 0, 0, 0, 0, 0, 0),
  ('badmin',   0, 0, 0, 0, 0, 0),
  ('t2mgr',    0, 0, 0, 1, 1, 1),
  ('multi',    3, 2, 3, 1, 1, 1);

select pg_temp.act_as_postgres();
do $$
declare r record;
begin
  for r in select f.label, u.uid, f.t1_co, f.t1_cl, f.t1_de, f.t2_co, f.t2_cl, f.t2_de
             from f2_read f join f2_users u using (label) loop
    perform pg_temp.act_as(r.uid);
    perform pg_temp.expect_count(r.label || ' reads T1 companies', $q$select count(*) from public.companies where tenant_id = 'b1000000-0000-4000-8000-0000000000a0' and workspace_id = 'b2000000-0000-4000-8000-0000000000a1'$q$, r.t1_co);
    perform pg_temp.expect_count(r.label || ' reads T1 clients',   $q$select count(*) from public.clients   where tenant_id = 'b1000000-0000-4000-8000-0000000000a0' and workspace_id = 'b2000000-0000-4000-8000-0000000000a1'$q$, r.t1_cl);
    perform pg_temp.expect_count(r.label || ' reads T1 deals',     $q$select count(*) from public.deals     where tenant_id = 'b1000000-0000-4000-8000-0000000000a0' and workspace_id = 'b2000000-0000-4000-8000-0000000000a1'$q$, r.t1_de);
    perform pg_temp.expect_count(r.label || ' reads T2 companies', $q$select count(*) from public.companies where tenant_id = 'b1000000-0000-4000-8000-0000000000a0' and workspace_id = 'b2000000-0000-4000-8000-0000000000a2'$q$, r.t2_co);
    perform pg_temp.expect_count(r.label || ' reads T2 clients',   $q$select count(*) from public.clients   where tenant_id = 'b1000000-0000-4000-8000-0000000000a0' and workspace_id = 'b2000000-0000-4000-8000-0000000000a2'$q$, r.t2_cl);
    perform pg_temp.expect_count(r.label || ' reads T2 deals',     $q$select count(*) from public.deals     where tenant_id = 'b1000000-0000-4000-8000-0000000000a0' and workspace_id = 'b2000000-0000-4000-8000-0000000000a2'$q$, r.t2_de);
  end loop;
  -- Tenant B's admin reads nothing from tenant T, whatever the workspace filter says.
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000009');
  perform pg_temp.expect_count('badmin reads tenant T rows by id', $q$select count(*) from public.deals where tenant_id = 'b1000000-0000-4000-8000-0000000000a0'$q$, 0);
end $$;

-- One company per label, created after the read counts so they do not change them. Each role's own client insert
-- uses a company no other role touches.
select pg_temp.act_as_postgres();
create temp table f2_co (label text primary key, company_id uuid not null) on commit drop;
insert into f2_co
  select label, gen_random_uuid() from f2_users where label in ('owner', 'admin', 'manager', 'editor', 'support', 'analyst', 'viewer', 'outsider', 'badmin', 't2mgr');
insert into public.companies (id, tenant_id, workspace_id, name)
  select f.company_id, 'b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'Co ' || f.label
    from f2_co f;

-- The matrix loops run as authenticated and read these temp tables, so the role needs select on them.
grant select on f2_users, f2_co to authenticated;

-- ----------------------------------------------------------------- 4. per-role write matrix (expected from policy)
-- One row per role: the allowed and denied operation for each table. Clients are admin-only; deals and companies
-- are owner, admin, manager, editor for insert and update; delete is owner or admin only.
create temp table f2_matrix (
  label text primary key,
  c_ins boolean, c_upd boolean, c_del boolean,
  d_ins boolean, d_upd boolean, d_del boolean,
  co_ins boolean, co_upd boolean, co_del boolean
) on commit drop;
insert into f2_matrix values
  ('owner',    true,  true,  true,  true,  true,  true,  true,  true,  true),
  ('admin',    true,  true,  true,  true,  true,  true,  true,  true,  true),
  ('manager',  false, false, false, true,  true,  false, true,  true,  false),
  ('editor',   false, false, false, true,  true,  false, true,  true,  false),
  ('support',  false, false, false, false, false, false, false, false, false),
  ('analyst',  false, false, false, false, false, false, false, false, false),
  ('viewer',   false, false, false, false, false, false, false, false, false),
  ('outsider', false, false, false, false, false, false, false, false, false),
  ('badmin',   false, false, false, false, false, false, false, false, false),
  ('t2mgr',    false, false, false, false, false, false, false, false, false);

-- Inserts. An allowed insert must add one row. A refused insert must raise 42501 (WITH CHECK).
-- The client insert uses the role's own company. Denied attempts use it too, so a success would be visible.
select pg_temp.act_as_postgres();
do $$
declare r record; co uuid;
begin
  for r in select m.*, u.uid from f2_matrix m join f2_users u using (label) loop
    perform pg_temp.act_as(r.uid);
    select company_id into co from f2_co where label = r.label;

    if r.c_ins then
      perform pg_temp.expect_one(r.label || ' client insert', format($q$insert into public.clients (tenant_id, workspace_id, company_id, status) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', %L, 'active')$q$, co));
    else
      perform pg_temp.expect_error(r.label || ' client insert', format($q$insert into public.clients (tenant_id, workspace_id, company_id, status) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', %L, 'active')$q$, co), '42501');
    end if;

    -- A non-member cannot read the stage, so sync_deal_status refuses first (P0001). That is still a denial, and it is
    -- recorded as observed. A workspace member who cannot write is refused by RLS (42501).
    if r.d_ins then
      perform pg_temp.expect_one(r.label || ' deal insert', format($q$insert into public.deals (tenant_id, workspace_id, title, stage_id) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'ins-%s', 'b5000000-0000-4000-8000-0000000000a1')$q$, r.label));
    elsif r.label in ('outsider', 'badmin', 't2mgr') then
      perform pg_temp.expect_error(r.label || ' deal insert (stage not visible)', format($q$insert into public.deals (tenant_id, workspace_id, title, stage_id) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'ins-%s', 'b5000000-0000-4000-8000-0000000000a1')$q$, r.label), 'P0001');
    else
      perform pg_temp.expect_error(r.label || ' deal insert', format($q$insert into public.deals (tenant_id, workspace_id, title, stage_id) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'ins-%s', 'b5000000-0000-4000-8000-0000000000a1')$q$, r.label), '42501');
    end if;

    if r.co_ins then
      perform pg_temp.expect_one(r.label || ' company insert', format($q$insert into public.companies (tenant_id, workspace_id, name) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'co-ins-%s')$q$, r.label));
    else
      perform pg_temp.expect_error(r.label || ' company insert', format($q$insert into public.companies (tenant_id, workspace_id, name) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'co-ins-%s')$q$, r.label), '42501');
    end if;
  end loop;
end $$;

-- Updates. Allowed roles change the row they created above. Denied roles target a shared row, and must touch zero rows.
select pg_temp.act_as_postgres();
do $$
declare r record;
begin
  for r in select m.*, u.uid from f2_matrix m join f2_users u using (label) loop
    perform pg_temp.act_as(r.uid);

    if r.c_upd then
      perform pg_temp.expect_one(r.label || ' client update', format($q$update public.clients set services = 'by %s' where company_id = (select company_id from f2_co where label = %L)$q$, r.label, r.label));
    else
      perform pg_temp.expect_zero(r.label || ' client update (shared)', $q$update public.clients set services = 'hijack' where id = 'b7000000-0000-4000-8000-0000000000a1'$q$);
    end if;

    if r.d_upd then
      perform pg_temp.expect_one(r.label || ' deal update', format($q$update public.deals set title = 'upd-%s' where title = 'ins-%s'$q$, r.label, r.label));
    else
      perform pg_temp.expect_zero(r.label || ' deal update (shared)', $q$update public.deals set title = 'hijack' where id = 'b8000000-0000-4000-8000-0000000000a1'$q$);
    end if;

    if r.co_upd then
      perform pg_temp.expect_one(r.label || ' company update', format($q$update public.companies set name = 'upd-%s' where name = 'co-ins-%s'$q$, r.label, r.label));
    else
      perform pg_temp.expect_zero(r.label || ' company update (shared)', $q$update public.companies set name = 'hijack' where id = 'b6000000-0000-4000-8000-0000000000a5'$q$);
    end if;
  end loop;
end $$;

-- Deletes. Allowed roles delete a row they own (created by postgres just before, so the attempt is not against a shared row).
-- Denied roles target a shared row and must touch zero rows. The shared rows are never deleted by an allowed role.
select pg_temp.act_as_postgres();
do $$
declare r record;
begin
  -- Owned rows for the roles that may delete, created as postgres.
  insert into public.deals (tenant_id, workspace_id, title, stage_id) values
    ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'del-owner', 'b5000000-0000-4000-8000-0000000000a1'),
    ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'del-admin', 'b5000000-0000-4000-8000-0000000000a1');
  insert into public.companies (tenant_id, workspace_id, name) values
    ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'cdel-owner'),
    ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'cdel-admin');

  for r in select m.*, u.uid from f2_matrix m join f2_users u using (label) loop
    perform pg_temp.act_as(r.uid);

    if r.c_del then
      -- Clients: the role's own client row (created in the insert pass). Allowed for owner and admin.
      perform pg_temp.expect_one(r.label || ' client delete', format($q$delete from public.clients where company_id = (select company_id from f2_co where label = %L)$q$, r.label));
    else
      perform pg_temp.expect_zero(r.label || ' client delete (shared)', $q$delete from public.clients where id = 'b7000000-0000-4000-8000-0000000000a2'$q$);
    end if;

    if r.d_del then
      perform pg_temp.expect_one(r.label || ' deal delete', format($q$delete from public.deals where title = 'del-%s'$q$, r.label));
    else
      perform pg_temp.expect_zero(r.label || ' deal delete (shared)', $q$delete from public.deals where id = 'b8000000-0000-4000-8000-0000000000a3'$q$);
    end if;

    if r.co_del then
      perform pg_temp.expect_one(r.label || ' company delete', format($q$delete from public.companies where name = 'cdel-%s'$q$, r.label));
    else
      perform pg_temp.expect_zero(r.label || ' company delete (shared)', $q$delete from public.companies where id = 'b6000000-0000-4000-8000-0000000000a5'$q$);
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------- 5. archive matrix (guard and RLS)
-- Companies and deals: manager and editor pass RLS for update, so the guard refuses them with 42501. Other roles fail
-- RLS and touch zero rows. Clients: manager and editor fail RLS and touch zero rows.
select pg_temp.act_as_postgres();
do $$
declare r record;
begin
  for r in select f.label, f.uid from f2_users f where f.label in ('manager', 'editor') loop
    perform pg_temp.act_as(r.uid);
    perform pg_temp.expect_error(r.label || ' archives company (guard)', $q$update public.companies set archived_at = now() where id = 'b6000000-0000-4000-8000-0000000000a1'$q$, '42501');
    perform pg_temp.expect_error(r.label || ' archives deal (guard)',     $q$update public.deals set archived_at = now() where id = 'b8000000-0000-4000-8000-0000000000a2'$q$, '42501');
    perform pg_temp.expect_zero(r.label || ' archives client (RLS)',     $q$update public.clients set archived_at = now() where id = 'b7000000-0000-4000-8000-0000000000a2'$q$);
    -- Archive by insert: a manager or editor who passes the insert policy is still refused by the guard.
    perform pg_temp.expect_error(r.label || ' inserts an archived deal (guard)',
      $q$insert into public.deals (tenant_id, workspace_id, title, stage_id, archived_at) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'arc-denied', 'b5000000-0000-4000-8000-0000000000a1', now())$q$, '42501');
  end loop;

  for r in select f.label, f.uid from f2_users f where f.label in ('support', 'analyst', 'viewer', 'outsider', 'badmin', 't2mgr') loop
    perform pg_temp.act_as(r.uid);
    perform pg_temp.expect_zero(r.label || ' archives company (RLS)', $q$update public.companies set archived_at = now() where id = 'b6000000-0000-4000-8000-0000000000a1'$q$);
    perform pg_temp.expect_zero(r.label || ' archives deal (RLS)',     $q$update public.deals set archived_at = now() where id = 'b8000000-0000-4000-8000-0000000000a2'$q$);
    perform pg_temp.expect_zero(r.label || ' archives client (RLS)',   $q$update public.clients set archived_at = now() where id = 'b7000000-0000-4000-8000-0000000000a2'$q$);
  end loop;

  -- Owner archives, admin restores. Both are admin under ws_role.
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000001');
  perform pg_temp.expect_one('owner archives company', $q$update public.companies set archived_at = now() where id = 'b6000000-0000-4000-8000-0000000000a1'$q$);
  perform pg_temp.expect_one('owner archives client',  $q$update public.clients set archived_at = now() where id = 'b7000000-0000-4000-8000-0000000000a2'$q$);
  perform pg_temp.expect_one('owner archives deal',    $q$update public.deals set archived_at = now() where id = 'b8000000-0000-4000-8000-0000000000a2'$q$);

  -- Observed, not a requirement: an editor may still edit a record that is archived (the guard only checks archived_at).
  -- This is recorded so a change to it is noticed. It is an owner decision whether this should be refused.
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000004');
  perform pg_temp.expect_one('editor edits an archived deal (observed)', $q$update public.deals set title = 'edit-archived' where id = 'b8000000-0000-4000-8000-0000000000a2'$q$);

  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000002');
  perform pg_temp.expect_one('admin restores company', $q$update public.companies set archived_at = null where id = 'b6000000-0000-4000-8000-0000000000a1'$q$);
  perform pg_temp.expect_one('admin restores client',  $q$update public.clients set archived_at = null where id = 'b7000000-0000-4000-8000-0000000000a2'$q$);
  perform pg_temp.expect_one('admin restores deal',    $q$update public.deals set archived_at = null where id = 'b8000000-0000-4000-8000-0000000000a2'$q$);
  perform pg_temp.expect_one('admin archives and restores a new deal',
    $q$insert into public.deals (tenant_id, workspace_id, title, stage_id, archived_at) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'arc-admin', 'b5000000-0000-4000-8000-0000000000a1', now())$q$);
end $$;

-- archived_by must be the caller who archived, and null after restore.
select pg_temp.act_as_postgres();
do $$
begin
  if (select archived_by from public.deals where title = 'arc-admin') is distinct from 'b0000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'FAIL 5: an admin insert of an archived deal did not record archived_by' using errcode = 'P0100';
  end if;
  if (select archived_by from public.deals where id = 'b8000000-0000-4000-8000-0000000000a2') is not null then
    raise exception 'FAIL 5: a restored deal still records archived_by' using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- 6. tenant and workspace changes
-- Moving a row needs a role in BOTH the old and the new workspace. Refused moves are 42501 (WITH CHECK).
select pg_temp.act_as_postgres();
-- A deal with no company, used only as the move target. d1 has a company, so the composite key (tenant, workspace,
-- company) refuses to move it to another workspace; that refusal is asserted separately below.
insert into public.deals (tenant_id, workspace_id, title, stage_id) values
  ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000a1', 'move-target', 'b5000000-0000-4000-8000-0000000000a1');
do $$
begin
  if (select workspace_id from public.deals where id = 'b8000000-0000-4000-8000-0000000000a1') <> 'b2000000-0000-4000-8000-0000000000a1' then
    raise exception 'FAIL 6: setup: d1 is not in T1' using errcode = 'P0100';
  end if;
end $$;

select pg_temp.act_as_postgres();
do $$
begin
  -- Editor has no role in T2 and cannot read the T2 stage, so the stage check refuses the move first (P0001).
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000004');
  perform pg_temp.expect_error('editor moves a deal to T2 (T2 stage not visible)',
    $q$update public.deals set workspace_id = 'b2000000-0000-4000-8000-0000000000a2', stage_id = 'b5000000-0000-4000-8000-0000000000a2' where title = 'move-target'$q$, 'P0001');

  -- The multi user manages T1 and only views T2. It can read the T2 stage, so the move reaches WITH CHECK and fails (42501).
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000011');
  perform pg_temp.expect_error('multi moves a T1 deal to T2 where it is only a viewer (RLS WITH CHECK)',
    $q$update public.deals set workspace_id = 'b2000000-0000-4000-8000-0000000000a2', stage_id = 'b5000000-0000-4000-8000-0000000000a2' where title = 'move-target'$q$, '42501');

  -- T2 manager cannot read T1 stages, so moving a T2 deal into T1 is refused by the stage check (P0001).
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000010');
  perform pg_temp.expect_error('t2mgr moves a T2 deal into T1 (T1 stage not visible)',
    $q$update public.deals set workspace_id = 'b2000000-0000-4000-8000-0000000000a1', stage_id = 'b5000000-0000-4000-8000-0000000000a1' where id = 'b8000000-0000-4000-8000-0000000000a4'$q$, 'P0001');

  -- Manager cannot move a client at all (clients update is admin only, so the row is filtered out).
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000003');
  perform pg_temp.expect_zero('manager moves a client (RLS)',
    $q$update public.clients set workspace_id = 'b2000000-0000-4000-8000-0000000000a2' where id = 'b7000000-0000-4000-8000-0000000000a1'$q$);

  -- Owner has a role in both T1 and T2 (tenant owner), so the move is allowed, and moving back is allowed too.
  perform pg_temp.act_as('b0000000-0000-4000-8000-000000000001');
  -- d1 has company k1 in T1. The composite foreign key (tenant, workspace, company) refuses the move (23503),
  -- even though the owner passes RLS in both workspaces.
  perform pg_temp.expect_error('owner moves d1 (has company) to T2 (composite key)',
    $q$update public.deals set workspace_id = 'b2000000-0000-4000-8000-0000000000a2', stage_id = 'b5000000-0000-4000-8000-0000000000a2' where id = 'b8000000-0000-4000-8000-0000000000a1'$q$, '23503');
  perform pg_temp.expect_one('owner moves d1 to T2',
    $q$update public.deals set workspace_id = 'b2000000-0000-4000-8000-0000000000a2', stage_id = 'b5000000-0000-4000-8000-0000000000a2' where title = 'move-target'$q$);
  perform pg_temp.expect_one('owner moves d1 back to T1',
    $q$update public.deals set workspace_id = 'b2000000-0000-4000-8000-0000000000a1', stage_id = 'b5000000-0000-4000-8000-0000000000a1' where title = 'move-target'$q$);

  -- Tenant owner of T has no role in tenant B, so moving a T deal into tenant B fails WITH CHECK.
  -- The owner of T cannot read tenant B's stage, so the stage check refuses the move (P0001).
  perform pg_temp.expect_error('owner moves a deal into tenant B (tenant B stage not visible)',
    $q$update public.deals set tenant_id = 'b1000000-0000-4000-8000-0000000000b0', workspace_id = 'b2000000-0000-4000-8000-0000000000b1', stage_id = 'b5000000-0000-4000-8000-0000000000b1' where title = 'move-target'$q$, 'P0001');

  -- A row cannot be created with a tenant and workspace that do not belong together. The stage trigger runs
  -- first for a deal (P0001); a company has no stage, so the composite foreign key refuses it (23503).
  perform pg_temp.expect_error('owner inserts a deal with tenant T and B1 workspace (stage check)',
    $q$insert into public.deals (tenant_id, workspace_id, title, stage_id) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000b1', 'mismatch', 'b5000000-0000-4000-8000-0000000000a1')$q$, 'P0001');
  perform pg_temp.expect_error('owner inserts a company with tenant T and B1 workspace (composite key)',
    $q$insert into public.companies (tenant_id, workspace_id, name) values ('b1000000-0000-4000-8000-0000000000a0', 'b2000000-0000-4000-8000-0000000000b1', 'mismatch-co')$q$, '23503');
end $$;

-- ----------------------------------------------------------------- 7. audit log behaviour
-- Each successful write leaves one audit row with the caller as actor. Each refused write leaves none.
select pg_temp.act_as_postgres();
do $$
begin
  -- Owner's client update on its own company's client wrote an audit row.
  if not exists (select 1 from public.audit_logs a
                  where a.actor_id = 'b0000000-0000-4000-8000-000000000001' and a.entity = 'clients' and a.action = 'update') then
    raise exception 'FAIL 7: owner client update left no audit row' using errcode = 'P0100';
  end if;
  -- The archive by owner is recorded as an update of the deal with the owner as actor.
  if not exists (select 1 from public.audit_logs a
                  where a.actor_id = 'b0000000-0000-4000-8000-000000000001' and a.entity = 'deals'
                    and a.action = 'update' and a.entity_id = 'b8000000-0000-4000-8000-0000000000a2') then
    raise exception 'FAIL 7: owner archive of d2 left no audit row' using errcode = 'P0100';
  end if;
  -- Roles that never succeeded at a write leave no audit rows at all.
  if exists (select 1 from public.audit_logs a
              where a.actor_id in ('b0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000006',
                                   'b0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000008',
                                   'b0000000-0000-4000-8000-000000000009', 'b0000000-0000-4000-8000-000000000010')) then
    raise exception 'FAIL 7: a role with no write rights left an audit row' using errcode = 'P0100';
  end if;
  -- The editor's refused archive of company k1 left no audit row.
  if exists (select 1 from public.audit_logs a
              where a.actor_id = 'b0000000-0000-4000-8000-000000000004' and a.entity = 'companies'
                and a.entity_id = 'b6000000-0000-4000-8000-0000000000a1' and a.action = 'update') then
    raise exception 'FAIL 7: a refused archive by the editor left an audit row' using errcode = 'P0100';
  end if;
  -- An admin delete is audited with the admin as actor.
  if not exists (select 1 from public.audit_logs a
                  where a.actor_id = 'b0000000-0000-4000-8000-000000000002' and a.entity = 'deals' and a.action = 'delete') then
    raise exception 'FAIL 7: admin delete left no audit row' using errcode = 'P0100';
  end if;
end $$;

select pg_temp.act_as_postgres();
do $$ begin raise notice 'PASS 39_f2_clients_deals_matrix'; end $$;
