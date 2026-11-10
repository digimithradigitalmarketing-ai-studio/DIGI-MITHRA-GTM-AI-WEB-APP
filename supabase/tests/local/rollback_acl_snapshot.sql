-- rollback_acl_snapshot.sql
-- Prints the privilege and shape state that 0007_down.sql must restore. Used by run_local.sh to diff
-- the state before 0007 against the state after 0007 followed by the rollback. Read only.
-- ACL entries are compared sorted, so the order in which Postgres lists grantees does not matter.
select 'table ' || c.relname || ' ' || coalesce((
         select string_agg(pg_get_userbyid(a.grantee) || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
                           || '/' || pg_get_userbyid(a.grantor), ',' order by pg_get_userbyid(a.grantee), a.privilege_type)
           from aclexplode(c.relacl) a), 'default') as line
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and c.relname in ('workflows', 'workflow_versions', 'workflow_runs', 'workflow_steps', 'notifications')
union all
select 'function ' || p.oid::regprocedure::text || ' ' || coalesce((
         select string_agg(pg_get_userbyid(a.grantee) || '=' || a.privilege_type || case when a.is_grantable then '*' else '' end
                           || '/' || pg_get_userbyid(a.grantor), ',' order by pg_get_userbyid(a.grantee), a.privilege_type)
           from aclexplode(p.proacl) a), 'default')
  from pg_proc p
 where p.oid in ('public.run_workflow_test(uuid,jsonb)'::regprocedure,
                 'public.cancel_workflow_run(uuid)'::regprocedure,
                 'app_private.run_workflow(uuid,jsonb,text)'::regprocedure)
union all
select 'run_workflow body md5 ' || md5(pg_get_functiondef('app_private.run_workflow(uuid,jsonb,text)'::regprocedure))
union all
select 'retry function ' || coalesce(to_regprocedure('public.retry_workflow_run(uuid)')::text, 'absent')
union all
select 'column ' || table_name || '.' || column_name
  from information_schema.columns
 where table_schema = 'public'
   and ((table_name = 'workflow_runs' and column_name in ('retry_of', 'attempt'))
     or (table_name = 'tasks' and column_name = 'automation_key'))
union all
select 'index ' || indexname
  from pg_indexes
 where schemaname = 'public'
   and indexname in ('workflow_runs_one_retry_uniq', 'workflow_runs_retry_of_idx', 'tasks_automation_key_uniq')
union all
select 'trigger ' || tgname
  from pg_trigger
 where tgrelid = 'public.workflows'::regclass and not tgisinternal
order by 1;
