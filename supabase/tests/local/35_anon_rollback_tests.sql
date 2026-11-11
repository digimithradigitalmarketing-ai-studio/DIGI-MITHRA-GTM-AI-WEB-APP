-- 35_anon_rollback_tests.sql
-- Synthetic-only. Checks the selective rollback of 0009. The runner builds the prelude as:
--   0009_anon_hardening_proposed.sql, then set_config('gtm.restore_anon_tables', 'public.leads', true),
--   then set_config('gtm.restore_anon_privileges', 'SELECT', true), then 0009_anon_hardening_rollback.sql.
-- So by the time this file runs, the hardening is applied and exactly one grant has been restored.
-- The runner ends the transaction with ROLLBACK.

-- Only the named table and privilege came back.
do $$
begin
  if not has_table_privilege('anon', 'public.leads', 'SELECT') then
    raise exception 'FAIL requested restore did not return anon SELECT on public.leads' using errcode = 'P0100';
  end if;
  if has_table_privilege('anon', 'public.leads', 'INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'FAIL rollback restored more than the requested privilege on public.leads' using errcode = 'P0100';
  end if;
  if has_table_privilege('anon', 'public.workspaces', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') then
    raise exception 'FAIL rollback restored anon privileges on a table that was not named' using errcode = 'P0100';
  end if;
end $$;

-- The default privileges are not restored, so future tables stay closed for anon.
do $$
begin
  if exists (
    select 1
      from pg_default_acl d
      join pg_namespace n on n.oid = d.defaclnamespace
      cross join lateral aclexplode(d.defaclacl) a
     where n.nspname = 'public' and d.defaclobjtype = 'r'
       and a.grantee = (select oid from pg_roles where rolname = 'anon')
       and pg_get_userbyid(d.defaclrole) = 'postgres'
  ) then
    raise exception 'FAIL rollback restored the postgres default table privileges for anon' using errcode = 'P0100';
  end if;
end $$;

-- rls_auto_enable is still closed for PUBLIC and anon.
do $$
begin
  if has_function_privilege('anon', 'public.rls_auto_enable()', 'EXECUTE') then
    raise exception 'FAIL rollback re-opened rls_auto_enable for anon' using errcode = 'P0100';
  end if;
  if exists (
    select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
     where p.oid = to_regprocedure('public.rls_auto_enable()') and a.grantee = 0
  ) then
    raise exception 'FAIL rollback re-opened rls_auto_enable for PUBLIC' using errcode = 'P0100';
  end if;
end $$;

-- plans keeps exactly its one intentional read, with no TRUNCATE.
do $$
begin
  if not has_table_privilege('anon', 'public.plans', 'SELECT') then
    raise exception 'FAIL plans lost anon SELECT' using errcode = 'P0100';
  end if;
  if has_table_privilege('anon', 'public.plans', 'TRUNCATE') then
    raise exception 'FAIL anon can TRUNCATE plans after rollback' using errcode = 'P0100';
  end if;
end $$;

-- The baseline record is still there, so the operator can see what was closed and restore more later.
do $$
begin
  if not exists (select 1 from app_private.gtm_0009_anon_baseline where kind = 'table' and object = 'public.leads') then
    raise exception 'FAIL baseline record for public.leads is missing' using errcode = 'P0100';
  end if;
end $$;

do $$ begin raise notice 'PASS 35_anon_rollback_tests'; end $$;
