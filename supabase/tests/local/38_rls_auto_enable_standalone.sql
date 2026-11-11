-- 38_rls_auto_enable_standalone.sql
-- Checks the standalone change in fixtures/0009_step4_only.sql: PUBLIC and anon lose EXECUTE on rls_auto_enable,
-- and the ensure_rls event trigger still enables RLS on a new public table. Run after that fixture (path H).
-- A control without the fixture must fail the first check.
do $$
declare
  v_fail text[] := '{}';
  v_proc oid := to_regprocedure('public.rls_auto_enable()');
begin
  if v_proc is null then
    raise exception 'public.rls_auto_enable() does not exist: the check did not run';
  end if;

  if exists (select 1 from aclexplode((select proacl from pg_proc where oid = v_proc)) a
              where a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    v_fail := array_append(v_fail, 'PUBLIC still has EXECUTE on rls_auto_enable');
  end if;
  if has_function_privilege('anon', v_proc, 'EXECUTE') then
    v_fail := array_append(v_fail, 'anon still has EXECUTE on rls_auto_enable');
  end if;

  -- The event trigger must still run and enable RLS on a new public table (created as the owner, as a migration would).
  execute 'create table public.gtm_0009_step4_probe (id integer)';
  if not (select relrowsecurity from pg_class where oid = 'public.gtm_0009_step4_probe'::regclass) then
    v_fail := array_append(v_fail, 'ensure_rls did not enable RLS on a new public table');
  end if;
  execute 'drop table public.gtm_0009_step4_probe';

  if array_length(v_fail, 1) is not null then
    raise exception '38 rls_auto_enable checks failed (%): %', array_length(v_fail, 1), array_to_string(v_fail, '; ');
  end if;
  raise notice '38 rls_auto_enable standalone checks passed';
end $$;
