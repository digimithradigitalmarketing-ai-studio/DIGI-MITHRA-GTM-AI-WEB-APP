-- 32_clients_readiness_tests.sql
-- Synthetic-only. Checks public.clients_readiness() (migration 0008).
--
-- Cases: ready (fixture matches production policies), missing policy for each command, RLS disabled,
-- missing table, revoked authenticated grant, anon holding a privilege, anon denied EXECUTE,
-- and an unauthorized user who sees zero rows while the readiness flags stay ready (the reason the app
-- also checks membership).
--
-- Each failure case runs inside a savepoint that is rolled back, so the fixture is restored between
-- cases. The runner wraps the whole file in one transaction and ends it with ROLLBACK.

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

-- A statement must be refused with insufficient_privilege (42501). Anything else is a failure.
create function pg_temp.expect_denied(p_label text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when insufficient_privilege then
    null;
end $$;

-- Asserts one readiness flag. The flag is read through the function, not from the catalog directly.
create function pg_temp.expect_flag(p_label text, p_flag text, p_value boolean) returns void language plpgsql as $$
declare v boolean;
begin
  v := (public.clients_readiness() ->> p_flag)::boolean;
  if v is distinct from p_value then
    raise exception 'FAIL %: % = %, expected %', p_label, p_flag, v, p_value using errcode = 'P0100';
  end if;
end $$;

-- Asserts the ready state: required flags true, every hole flag false (mirrors the TypeScript evaluator).
create function pg_temp.expect_all_ready(p_label text) returns void language plpgsql as $$
declare
  r jsonb := public.clients_readiness();
  k text;
  n integer;
  must_be_false text[] := array['anon_has_any_privilege', 'anon_or_public_policy', 'public_execute', 'anon_execute'];
begin
  for k in select jsonb_object_keys(r) loop
    if k = any (must_be_false) then
      if (r ->> k)::boolean then
        raise exception 'FAIL %: % is true', p_label, k using errcode = 'P0100';
      end if;
    elsif not (r ->> k)::boolean then
      raise exception 'FAIL %: % is false', p_label, k using errcode = 'P0100';
    end if;
  end loop;
  select count(*) into n from jsonb_object_keys(r);
  if n <> 15 then
    raise exception 'FAIL %: expected 15 flags, got %', p_label, n using errcode = 'P0100';
  end if;
end $$;

-- Drops every clients policy for one command. Runs as the owner, inside a savepoint.
create function pg_temp.drop_clients_policies(p_cmd text) returns void language plpgsql as $$
declare n text;
begin
  for n in select policyname from pg_policies where schemaname = 'public' and tablename = 'clients' and cmd = p_cmd loop
    execute format('drop policy %I on public.clients', n);
  end loop;
end $$;

-- ----------------------------------------------------------------- fixtures (owner)
-- The tests below run against the replica state the earlier suites set up. Nothing new is inserted.

-- Ready: a workspace member sees every flag true, and the anon role holds nothing on clients.
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e001');
select pg_temp.expect_all_ready('ready as member');

-- The function is executable by authenticated and not by anon or PUBLIC.
do $$
begin
  if not has_function_privilege('authenticated', 'public.clients_readiness()', 'EXECUTE') then
    raise exception 'FAIL authenticated cannot execute clients_readiness' using errcode = 'P0100';
  end if;
  if has_function_privilege('anon', 'public.clients_readiness()', 'EXECUTE') then
    raise exception 'FAIL anon can execute clients_readiness' using errcode = 'P0100';
  end if;
  if exists (
    select 1 from pg_proc p, aclexplode(p.proacl) a
     where p.oid = 'public.clients_readiness()'::regprocedure and a.grantee = 0
  ) then
    raise exception 'FAIL PUBLIC can execute clients_readiness' using errcode = 'P0100';
  end if;
end $$;

-- anon is refused at the EXECUTE check, so it cannot even learn the flags.
select pg_temp.act_as_postgres();
set local role anon;
select pg_temp.expect_denied('anon executes clients_readiness', 'select public.clients_readiness()');
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- missing policies (savepoints)
savepoint missing_select;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('SELECT');
select pg_temp.expect_flag('missing select policy', 'policy_select', false);
rollback to savepoint missing_select;

savepoint missing_insert;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('INSERT');
select pg_temp.expect_flag('missing insert policy', 'policy_insert', false);
rollback to savepoint missing_insert;

savepoint missing_update;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('UPDATE');
select pg_temp.expect_flag('missing update policy', 'policy_update', false);
rollback to savepoint missing_update;

savepoint missing_delete;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('DELETE');
select pg_temp.expect_flag('missing delete policy', 'policy_delete', false);
rollback to savepoint missing_delete;

-- A policy that exists but does not use the workspace-role helper does not count. Replace the insert
-- policy with an open one for authenticated and expect the flag to stay false.
savepoint open_insert_policy;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('INSERT');
create policy clients_insert_open on public.clients for insert to authenticated with check (true);
select pg_temp.expect_flag('open insert policy does not count', 'policy_insert', false);
rollback to savepoint open_insert_policy;

-- ----------------------------------------------------------------- RLS, table and grants (savepoints)
savepoint rls_disabled;
select pg_temp.act_as_postgres();
alter table public.clients disable row level security;
select pg_temp.expect_flag('rls disabled', 'rls_enabled', false);
rollback to savepoint rls_disabled;

savepoint table_missing;
select pg_temp.act_as_postgres();
alter table public.clients rename to clients_renamed_for_test;
select pg_temp.expect_flag('table missing', 'table_exists', false);
select pg_temp.expect_flag('table missing rls', 'rls_enabled', false);
rollback to savepoint table_missing;

savepoint grant_revoked;
select pg_temp.act_as_postgres();
revoke insert on public.clients from authenticated;
select pg_temp.expect_flag('revoked insert grant', 'grant_insert', false);
rollback to savepoint grant_revoked;

savepoint anon_privilege;
select pg_temp.act_as_postgres();
grant select on public.clients to anon;
select pg_temp.expect_flag('anon holds select on clients', 'anon_has_any_privilege', true);
rollback to savepoint anon_privilege;

-- ----------------------------------------------------------------- policy identity (savepoints)
-- A correct-looking policy under another name does not count: the check is by exact name.
savepoint renamed_insert_policy;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('INSERT');
create policy clients_insert_renamed on public.clients for insert to authenticated
  with check (app_private.ws_role(tenant_id, workspace_id) = any (array['admin']::text[]));
select pg_temp.expect_flag('renamed insert policy does not count', 'policy_insert', false);
rollback to savepoint renamed_insert_policy;

-- An ALL policy named like the update policy does not count: the check is by exact command.
savepoint all_update_policy;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('UPDATE');
create policy clients_update on public.clients for all to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) is not null);
select pg_temp.expect_flag('ALL policy does not count as update', 'policy_update', false);
rollback to savepoint all_update_policy;

-- A select policy granted to PUBLIC: wrong role set, and it counts as an anon/public policy.
savepoint public_select_policy;
select pg_temp.act_as_postgres();
select pg_temp.drop_clients_policies('SELECT');
create policy clients_read on public.clients for select to public
  using (app_private.ws_role(tenant_id, workspace_id) is not null);
select pg_temp.expect_flag('public-role select policy does not count', 'policy_select', false);
select pg_temp.expect_flag('public-role policy is reported', 'anon_or_public_policy', true);
rollback to savepoint public_select_policy;

-- A policy added for anon blocks readiness even when every required policy is present.
savepoint anon_policy;
select pg_temp.act_as_postgres();
create policy clients_anon_probe on public.clients for select to anon using (true);
select pg_temp.expect_flag('anon policy is reported', 'anon_or_public_policy', true);
rollback to savepoint anon_policy;

-- ----------------------------------------------------------------- function identity and EXECUTE (savepoints)
savepoint function_definer;
select pg_temp.act_as_postgres();
alter function public.clients_readiness() security definer;
select pg_temp.expect_flag('definer function is reported', 'function_security_invoker', false);
rollback to savepoint function_definer;

savepoint public_execute;
select pg_temp.act_as_postgres();
grant execute on function public.clients_readiness() to public;
select pg_temp.expect_flag('PUBLIC execute is reported', 'public_execute', true);
rollback to savepoint public_execute;

savepoint anon_execute;
select pg_temp.act_as_postgres();
grant execute on function public.clients_readiness() to anon;
select pg_temp.expect_flag('anon execute is reported', 'anon_execute', true);
rollback to savepoint anon_execute;

-- A TRUNCATE-only grant to anon is still a hole. The privilege list covers every table privilege.
savepoint anon_truncate_only;
select pg_temp.act_as_postgres();
grant truncate on public.clients to anon;
select pg_temp.expect_flag('anon truncate-only is reported', 'anon_has_any_privilege', true);
rollback to savepoint anon_truncate_only;

-- ----------------------------------------------------------------- empty and unauthorized data
-- The readiness flags do not depend on the user. A user with no workspace membership still sees the
-- module as ready, but reads zero rows. The app tells this apart with its membership check.
select pg_temp.act_as('e0000000-0000-4000-8000-0000000000ff');
select pg_temp.expect_all_ready('ready as non-member');
do $$
declare n bigint;
begin
  select count(*) into n from public.clients;
  if n <> 0 then
    raise exception 'FAIL non-member saw % client rows', n using errcode = 'P0100';
  end if;
end $$;

select pg_temp.act_as_postgres();
do $$ begin raise notice 'PASS 32_clients_readiness_tests'; end $$;
