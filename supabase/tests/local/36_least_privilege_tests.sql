-- 36_least_privilege_tests.sql
-- Checks the 0010 least-privilege change. Run AFTER supabase/reviews/0010_gtm_least_privilege_proposed.sql
-- (expected to fail before it, which is the control). Wrapped in begin/rollback by run_local.sh.
-- Uses has_table_privilege() for effective privileges, and aclexplode() to see PUBLIC grants that
-- has_table_privilege() does not report for the PUBLIC pseudo-role.

do $$
declare
  t record;
  p_app text[] := array['public.companies', 'public.clients', 'public.deals', 'public.contacts',
                        'public.leads', 'public.campaigns', 'public.landing_pages', 'public.plans'];
  v_table text;
  v_priv text;
  v_fail text[] := '{}';
  v_n integer := 0;
  v_probe_truncate boolean;
begin
  -- 1. No public table grants TRUNCATE to PUBLIC, anon or authenticated (effective, and by ACL entry).
  for t in
    select c.oid, c.relname
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    v_n := v_n + 1;
    if has_table_privilege('anon', t.oid, 'TRUNCATE') then
      v_fail := array_append(v_fail, format('anon can TRUNCATE %s', t.relname));
    end if;
    if has_table_privilege('authenticated', t.oid, 'TRUNCATE') then
      v_fail := array_append(v_fail, format('authenticated can TRUNCATE %s', t.relname));
    end if;
    if exists (
      select 1 from aclexplode((select relacl from pg_class where oid = t.oid)) a
       where a.grantee = 0 and a.privilege_type = 'TRUNCATE'
    ) then
      v_fail := array_append(v_fail, format('PUBLIC holds TRUNCATE on %s', t.relname));
    end if;
  end loop;
  if v_n = 0 then
    v_fail := array_append(v_fail, 'no tables found in public: the check did not run');
  end if;

  -- 2. plans: anon keeps its one intended read, and loses TRUNCATE (the reason this file exists).
  if to_regclass('public.plans') is not null then
    if not has_table_privilege('anon', 'public.plans', 'SELECT') then
      v_fail := array_append(v_fail, 'anon lost SELECT on plans (intended public read)');
    end if;
    if has_table_privilege('anon', 'public.plans', 'TRUNCATE') then
      v_fail := array_append(v_fail, 'anon can TRUNCATE plans');
    end if;
  end if;

  -- 3. Preserved: the app's tables keep SELECT, INSERT, UPDATE and DELETE for authenticated.
  --    RLS still decides the rows; this checks only that the table grants were not removed.
  foreach v_table in array p_app loop
    if to_regclass(v_table) is null then
      continue;
    end if;
    foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if not has_table_privilege('authenticated', v_table, v_priv) then
        v_fail := array_append(v_fail, format('authenticated lost %s on %s', v_priv, v_table));
      end if;
    end loop;
  end loop;

  -- 4. Default ACL: a new table created by postgres does not inherit TRUNCATE for anon or authenticated.
  execute 'create table public.gtm_0010_probe (id int primary key)';
  v_probe_truncate := has_table_privilege('anon', 'public.gtm_0010_probe', 'TRUNCATE')
                   or has_table_privilege('authenticated', 'public.gtm_0010_probe', 'TRUNCATE');
  execute 'drop table public.gtm_0010_probe';
  if v_probe_truncate then
    v_fail := array_append(v_fail, 'a new postgres-owned public table inherits TRUNCATE for anon or authenticated');
  end if;

  if array_length(v_fail, 1) is not null then
    raise exception '0010 least-privilege checks failed (%): %', array_length(v_fail, 1), array_to_string(v_fail, '; ');
  end if;
  raise notice '0010 least-privilege checks passed (% tables)', v_n;
end $$;
