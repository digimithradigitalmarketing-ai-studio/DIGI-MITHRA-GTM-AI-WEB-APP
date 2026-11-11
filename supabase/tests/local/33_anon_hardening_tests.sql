-- 33_anon_hardening_tests.sql
-- Synthetic-only. Compatibility checks for supabase/reviews/0009_anon_hardening_proposed.sql. The
-- runner applies that script as a prelude inside this transaction, then ends with ROLLBACK, so the
-- replica is left unchanged.
--
-- The replica does not contain the production landing-page and web-chat functions, so a stand-in
-- SECURITY DEFINER function stands in for them. It proves the mechanism those functions depend on:
-- an anon caller can reach data through a definer function even after anon loses table privileges.

-- ----------------------------------------------------------------- helpers (temporary)
create function pg_temp.expect_denied(p_label text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when insufficient_privilege then
    null;
end $$;

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

-- ----------------------------------------------------------------- stand-in definer (owner)
create function public.anon_probe_definer() returns integer
language sql security definer set search_path = '' as $$
  select count(*)::integer from public.workspaces
$$;
grant execute on function public.anon_probe_definer() to anon;

-- ----------------------------------------------------------------- 1. no table privilege for anon
do $$
declare
  t record;
begin
  for t in
    select c.oid::regclass as rel, c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relname <> 'plans'
  loop
    if has_table_privilege('anon', t.rel, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then
      raise exception 'FAIL anon still holds privileges on %', t.rel using errcode = 'P0100';
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------- 2. anon is refused at the table
set local role anon;
select pg_temp.expect_denied('anon select workspaces', 'select count(*) from public.workspaces');
select pg_temp.expect_denied('anon insert workspaces', $$insert into public.workspaces (id) values (gen_random_uuid())$$);
select pg_temp.expect_denied('anon truncate workspaces', 'truncate public.workspaces');
select pg_temp.expect_denied('anon delete companies', 'delete from public.companies');
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- 3. definer path still works for anon
set local role anon;
do $$
declare n integer;
begin
  n := public.anon_probe_definer();
  if n is null then
    raise exception 'FAIL definer probe returned null' using errcode = 'P0100';
  end if;
end $$;
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- 4. authenticated is unchanged
do $$
begin
  if not has_table_privilege('authenticated', 'public.companies', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'FAIL authenticated lost companies privileges' using errcode = 'P0100';
  end if;
  if not has_table_privilege('authenticated', 'public.clients', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'FAIL authenticated lost clients privileges' using errcode = 'P0100';
  end if;
end $$;

-- The readiness check (migration 0008) still reports anon as holding nothing on clients.
select pg_temp.act_as('e0000000-0000-4000-8000-00000000e001');
do $$
begin
  if (public.clients_readiness() ->> 'anon_has_any_privilege')::boolean then
    raise exception 'FAIL readiness still reports anon privileges on clients' using errcode = 'P0100';
  end if;
end $$;
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- 5. plans keeps its one anon read
do $$
begin
  if to_regclass('public.plans') is null then
    raise notice 'SKIP plans: table not present on this replica';
  elsif not has_table_privilege('anon', 'public.plans', 'SELECT') then
    raise exception 'FAIL anon lost read access to plans' using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- 6. rls_auto_enable is not callable by anon
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is null then
    raise notice 'SKIP rls_auto_enable: not present on this replica';
  elsif has_function_privilege('anon', 'public.rls_auto_enable()', 'EXECUTE') then
    raise exception 'FAIL anon can still execute rls_auto_enable' using errcode = 'P0100';
  end if;
end $$;

drop function public.anon_probe_definer();
do $$ begin raise notice 'PASS 33_anon_hardening_tests'; end $$;
