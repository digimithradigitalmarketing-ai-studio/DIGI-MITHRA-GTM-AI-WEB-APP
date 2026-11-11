-- 0006b_state_snapshot.sql
-- Read-only. Prints one sorted line per object for the state that 0006b changes. run_local.sh path F takes this
-- snapshot before 0006b, after 0006b, and after 0006b_down, then compares them by category.
--
-- Categories (the first word of each line):
--   policy   every policy on companies, clients and deals
--   rls      RLS flag on companies, clients and deals
--   trigger  every non-internal trigger on companies, clients and deals
--   function the archive-guard, immutability, restore and status functions (md5 of the body, or 'absent')
--   column   every column of companies, clients and deals (name, type, nullability)
--   table    the ACL of EVERY table in public (aclexplode), so collateral grant changes are visible
select 'policy ' || tablename || ' ' || policyname || ' ' || cmd || ' ' || array_to_string(roles, ',')
       || ' qual=' || coalesce(qual, '') || ' check=' || coalesce(with_check, '') as line
  from pg_policies
 where schemaname = 'public' and tablename in ('companies', 'clients', 'deals')
union all
select 'rls ' || c.relname || ' ' || c.relrowsecurity::text || ' force=' || c.relforcerowsecurity::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname in ('companies', 'clients', 'deals')
union all
select 'trigger ' || c.relname || ' ' || t.tgname || ' ' || pg_get_triggerdef(t.oid)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname in ('companies', 'clients', 'deals') and not t.tgisinternal
union all
select 'function ' || f.fn || ' ' || coalesce((
         select md5(pg_get_functiondef(p.oid)) from pg_proc p
          where p.oid = to_regprocedure(f.fn)), 'absent')
  from (values ('app_private.guard_archive()'), ('app_private.guard_archived_immutable()'),
               ('app_private.sync_deal_status()'), ('public.restore_archived_record(text,uuid)')) as f(fn)
union all
select 'column ' || c.table_name || '.' || c.column_name || ' ' || c.data_type || ' null=' || c.is_nullable
  from information_schema.columns c
 where c.table_schema = 'public' and c.table_name in ('companies', 'clients', 'deals')
union all
select 'table ' || c.relname || ' ' || coalesce((
         select string_agg(case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end
                           || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end,
                           ',' order by case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end, a.privilege_type)
           from aclexplode(c.relacl) a), 'default')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relkind in ('r', 'p')
order by 1;
