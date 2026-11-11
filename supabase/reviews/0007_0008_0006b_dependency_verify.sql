-- 0007_0008_0006b_dependency_verify.sql
-- READ-ONLY dependency verification. Catalog reads only. Safe to run against production.
-- Generated from the migration SQL by reading each file's creates and references (see DEPLOYMENT_PLAN.md, section 'Dependencies').
-- Each row says whether an object a migration needs is present. Expected results differ by database:
--   production-shaped replica (path E, after its baseline and the migrations): every row PRESENT.
--   fresh repo replay (path B): every row PRESENT except public.conversations and public.messages. No repo migration creates
--     them; they exist only in the production baseline. 0007a and 0007 reference them inside run_workflow's WhatsApp branches.
--     Recorded as a reproducibility gap in DEPLOYMENT_PLAN.md (not a blocker for the rows above).
--   production today: the 0004b, 0006b, 0007a, 0007 and 0008 rows are MISSING (see SECURITY_READINESS_REPORT.md).
-- Required order: 0004b before 0006b (drifted production tables have no archived_at; 0006b's preflight now refuses, R4).
--   0007a before 0007 (0007 extends run_workflow and workflows created there). 0008 needs only clients and ws_role.
--
-- Revised 2026-11-12 (R1 to R4). New rows:
--   R1 (archive): trg_archive_immutable on companies, clients, deals; app_private.guard_archived_immutable();
--       public.restore_archived_record(text,uuid); app_private.archive_restore_grant. All are created by 0006b.
--   R3 (inbox): the columns that set_priority (conversations) and ai_draft (messages) write. Production has them
--       (catalog read 2026-11-12). The fresh replay does not, so the two table rows stay MISSING there, by design.
--   R4 (preflight): the 0004 unique keys and the 0004b active-row indexes that 0006b's preflight checks; the
--       0007a unique index on workflow_runs (workflow_id, dedupe_key) that 0007's preflight checks; app_private.require_relation.
-- Production, observed by running this probe read-only on 2026-11-12 (project siyxkombexmowlggxlrb, begin read only):
--   PRESENT: conversations and messages column sets (R3); companies/clients/deals unique constraints (0004); the
--     workflow_runs (workflow_id, dedupe_key) unique index (0007a); run_workflow; run_workflow_test; cancel_workflow_run;
--     require_ws_role; ws_role; audit; set_created_by; set_updated_at; notify_workspace; render_template; on_lead.
--   MISSING: every R1 row (archived_at/archived_by on companies, clients, deals; guard_archive; sync_deal_status;
--     guard_archived_immutable; restore_archived_record; archive_restore_grant; the trg_archive_immutable and
--     trg_guard_archive, trg_audit, trg_created_by, trg_updated triggers); require_relation; the 0004b *_scope_active_idx
--     indexes; the clients and deals policies; 0007 items (tasks.automation_key, workflow_runs.retry_of/attempt,
--     validate_workflow_definition, the trg_validate_definition trigger, the two 0007 unique indexes); the 0008
--     clients_readiness function; retry_workflow_run. So 0004b, 0006b, 0007 and 0008 are not applied to production.
begin read only;
with checks(grp, item, ok) as (values
  ('columns', 'companies.archived_at', exists(select 1 from information_schema.columns where table_schema='public' and table_name='companies' and column_name='archived_at')),
  ('columns', 'companies.archived_by', exists(select 1 from information_schema.columns where table_schema='public' and table_name='companies' and column_name='archived_by')),
  ('columns', 'clients.archived_at', exists(select 1 from information_schema.columns where table_schema='public' and table_name='clients' and column_name='archived_at')),
  ('columns', 'clients.archived_by', exists(select 1 from information_schema.columns where table_schema='public' and table_name='clients' and column_name='archived_by')),
  ('columns', 'deals.archived_at', exists(select 1 from information_schema.columns where table_schema='public' and table_name='deals' and column_name='archived_at')),
  ('columns', 'deals.archived_by', exists(select 1 from information_schema.columns where table_schema='public' and table_name='deals' and column_name='archived_by')),
  ('functions', 'app_private.guard_archive()', to_regprocedure('app_private.guard_archive()') is not null),
  ('functions', 'app_private.sync_deal_status()', to_regprocedure('app_private.sync_deal_status()') is not null),
  ('triggers', 'companies.trg_created_by', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='companies' and t.tgname='trg_created_by' and not t.tgisinternal)),
  ('triggers', 'companies.trg_updated', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='companies' and t.tgname='trg_updated' and not t.tgisinternal)),
  ('triggers', 'companies.trg_guard_archive', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='companies' and t.tgname='trg_guard_archive' and not t.tgisinternal)),
  ('triggers', 'companies.trg_audit', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='companies' and t.tgname='trg_audit' and not t.tgisinternal)),
  ('triggers', 'clients.trg_created_by', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='clients' and t.tgname='trg_created_by' and not t.tgisinternal)),
  ('triggers', 'clients.trg_updated', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='clients' and t.tgname='trg_updated' and not t.tgisinternal)),
  ('triggers', 'clients.trg_guard_archive', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='clients' and t.tgname='trg_guard_archive' and not t.tgisinternal)),
  ('triggers', 'clients.trg_audit', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='clients' and t.tgname='trg_audit' and not t.tgisinternal)),
  ('triggers', 'deals.trg_created_by', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='deals' and t.tgname='trg_created_by' and not t.tgisinternal)),
  ('triggers', 'deals.trg_updated', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='deals' and t.tgname='trg_updated' and not t.tgisinternal)),
  ('triggers', 'deals.trg_guard_archive', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='deals' and t.tgname='trg_guard_archive' and not t.tgisinternal)),
  ('triggers', 'deals.trg_audit', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='deals' and t.tgname='trg_audit' and not t.tgisinternal)),
  ('triggers', 'deals.trg_deal_status', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='deals' and t.tgname='trg_deal_status' and not t.tgisinternal)),
  ('triggers', 'companies.trg_archive_immutable', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='companies' and t.tgname='trg_archive_immutable' and not t.tgisinternal)),
  ('triggers', 'clients.trg_archive_immutable', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='clients' and t.tgname='trg_archive_immutable' and not t.tgisinternal)),
  ('triggers', 'deals.trg_archive_immutable', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='deals' and t.tgname='trg_archive_immutable' and not t.tgisinternal)),
  ('constraints', 'companies_tenant_id_workspace_id_id_key', exists(select 1 from pg_constraint where conname='companies_tenant_id_workspace_id_id_key')),
  ('constraints', 'clients_tenant_id_workspace_id_id_key', exists(select 1 from pg_constraint where conname='clients_tenant_id_workspace_id_id_key')),
  ('constraints', 'deals_tenant_id_workspace_id_id_key', exists(select 1 from pg_constraint where conname='deals_tenant_id_workspace_id_id_key')),
  ('indexes', 'companies_scope_active_idx', to_regclass('public.companies_scope_active_idx') is not null),
  ('indexes', 'clients_scope_active_idx', to_regclass('public.clients_scope_active_idx') is not null),
  ('indexes', 'deals_scope_active_idx', to_regclass('public.deals_scope_active_idx') is not null),
  ('rls', 'companies RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.companies')), false)),
  ('policies', 'companies.companies_read', exists(select 1 from pg_policies where schemaname='public' and tablename='companies' and policyname='companies_read')),
  ('policies', 'companies.companies_insert', exists(select 1 from pg_policies where schemaname='public' and tablename='companies' and policyname='companies_insert')),
  ('policies', 'companies.companies_update', exists(select 1 from pg_policies where schemaname='public' and tablename='companies' and policyname='companies_update')),
  ('policies', 'companies.companies_delete', exists(select 1 from pg_policies where schemaname='public' and tablename='companies' and policyname='companies_delete')),
  ('rls', 'clients RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.clients')), false)),
  ('policies', 'clients.clients_read', exists(select 1 from pg_policies where schemaname='public' and tablename='clients' and policyname='clients_read')),
  ('policies', 'clients.clients_insert', exists(select 1 from pg_policies where schemaname='public' and tablename='clients' and policyname='clients_insert')),
  ('policies', 'clients.clients_update', exists(select 1 from pg_policies where schemaname='public' and tablename='clients' and policyname='clients_update')),
  ('policies', 'clients.clients_delete', exists(select 1 from pg_policies where schemaname='public' and tablename='clients' and policyname='clients_delete')),
  ('rls', 'deals RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.deals')), false)),
  ('policies', 'deals.deals_read', exists(select 1 from pg_policies where schemaname='public' and tablename='deals' and policyname='deals_read')),
  ('policies', 'deals.deals_insert', exists(select 1 from pg_policies where schemaname='public' and tablename='deals' and policyname='deals_insert')),
  ('policies', 'deals.deals_update', exists(select 1 from pg_policies where schemaname='public' and tablename='deals' and policyname='deals_update')),
  ('policies', 'deals.deals_delete', exists(select 1 from pg_policies where schemaname='public' and tablename='deals' and policyname='deals_delete')),
  ('tables', 'public.notifications', to_regclass('public.notifications') is not null),
  ('tables', 'public.workflows', to_regclass('public.workflows') is not null),
  ('tables', 'public.workflow_versions', to_regclass('public.workflow_versions') is not null),
  ('tables', 'public.workflow_runs', to_regclass('public.workflow_runs') is not null),
  ('tables', 'public.workflow_steps', to_regclass('public.workflow_steps') is not null),
  ('rls', 'workflows RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.workflows')), false)),
  ('rls', 'workflow_versions RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.workflow_versions')), false)),
  ('rls', 'workflow_runs RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.workflow_runs')), false)),
  ('rls', 'workflow_steps RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.workflow_steps')), false)),
  ('rls', 'notifications RLS enabled', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.notifications')), false)),
  ('functions', 'app_private.require_ws_role(uuid,uuid,text[])', to_regprocedure('app_private.require_ws_role(uuid,uuid,text[])') is not null),
  ('functions', 'app_private.render_template(text,jsonb,uuid)', to_regprocedure('app_private.render_template(text,jsonb,uuid)') is not null),
  ('functions', 'app_private.notify_workspace(uuid,uuid,text,text,text,text[])', to_regprocedure('app_private.notify_workspace(uuid,uuid,text,text,text,text[])') is not null),
  ('functions', 'app_private.on_lead()', to_regprocedure('app_private.on_lead()') is not null),
  ('functions', 'app_private.run_workflow(uuid,jsonb,text)', to_regprocedure('app_private.run_workflow(uuid,jsonb,text)') is not null),
  ('functions', 'public.run_workflow_test(uuid,jsonb)', to_regprocedure('public.run_workflow_test(uuid,jsonb)') is not null),
  ('functions', 'public.cancel_workflow_run(uuid)', to_regprocedure('public.cancel_workflow_run(uuid)') is not null),
  ('columns', 'tasks.automation_key', exists(select 1 from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='automation_key')),
  ('columns', 'workflow_runs.retry_of', exists(select 1 from information_schema.columns where table_schema='public' and table_name='workflow_runs' and column_name='retry_of')),
  ('columns', 'workflow_runs.attempt', exists(select 1 from information_schema.columns where table_schema='public' and table_name='workflow_runs' and column_name='attempt')),
  ('indexes', 'tasks_automation_key_uniq', to_regclass('public.tasks_automation_key_uniq') is not null),
  ('indexes', 'workflow_runs_one_retry_uniq', to_regclass('public.workflow_runs_one_retry_uniq') is not null),
  ('functions', 'app_private.validate_workflow_definition()', to_regprocedure('app_private.validate_workflow_definition()') is not null),
  ('triggers', 'workflows.trg_validate_definition', exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relname='workflows' and t.tgname='trg_validate_definition' and not t.tgisinternal)),
  ('functions', 'public.retry_workflow_run(uuid)', to_regprocedure('public.retry_workflow_run(uuid)') is not null),
  ('tables', 'public.clients', to_regclass('public.clients') is not null),
  ('functions', 'public.clients_readiness()', to_regprocedure('public.clients_readiness()') is not null),
  ('tables', 'public.tenants', to_regclass('public.tenants') is not null),
  ('tables', 'public.workspaces', to_regclass('public.workspaces') is not null),
  ('tables', 'public.tenant_members', to_regclass('public.tenant_members') is not null),
  ('tables', 'public.workspace_members', to_regclass('public.workspace_members') is not null),
  ('tables', 'public.pipeline_stages', to_regclass('public.pipeline_stages') is not null),
  ('tables', 'public.tasks', to_regclass('public.tasks') is not null),
  ('tables', 'public.leads', to_regclass('public.leads') is not null),
  ('tables', 'public.contacts', to_regclass('public.contacts') is not null),
  ('tables', 'public.messages', to_regclass('public.messages') is not null),
  ('tables', 'public.conversations', to_regclass('public.conversations') is not null),
  ('columns', 'conversations: id, tenant_id, workspace_id, priority (set_priority)', (select count(*) = 4 from information_schema.columns where table_schema='public' and table_name='conversations' and column_name in ('id','tenant_id','workspace_id','priority'))),
  ('columns', 'messages: id, tenant_id, workspace_id, conversation_id, direction, body, sender_name, is_ai_draft (ai_draft)', (select count(*) = 8 from information_schema.columns where table_schema='public' and table_name='messages' and column_name in ('id','tenant_id','workspace_id','conversation_id','direction','body','sender_name','is_ai_draft'))),
  ('functions', 'app_private.ws_role(uuid,uuid)', to_regprocedure('app_private.ws_role(uuid,uuid)') is not null),
  ('functions', 'app_private.audit()', to_regprocedure('app_private.audit()') is not null),
  ('functions', 'app_private.set_created_by()', to_regprocedure('app_private.set_created_by()') is not null),
  ('functions', 'app_private.set_updated_at()', to_regprocedure('app_private.set_updated_at()') is not null),
  ('functions', 'app_private.guard_archived_immutable()', to_regprocedure('app_private.guard_archived_immutable()') is not null),
  ('functions', 'public.restore_archived_record(text,uuid)', to_regprocedure('public.restore_archived_record(text,uuid)') is not null),
  ('tables', 'app_private.archive_restore_grant', to_regclass('app_private.archive_restore_grant') is not null),
  ('functions', 'app_private.require_relation(text)', to_regprocedure('app_private.require_relation(text)') is not null),
  ('indexes', 'workflow_runs unique (workflow_id, dedupe_key) (0007a)', exists(select 1 from pg_indexes where schemaname='public' and tablename='workflow_runs' and indexdef ilike 'CREATE UNIQUE INDEX%(workflow_id, dedupe_key)%')),
  ('rpc grants', 'restore_archived_record authenticated EXECUTE', to_regprocedure('public.restore_archived_record(text,uuid)') is not null and has_function_privilege('authenticated','public.restore_archived_record(text,uuid)','EXECUTE')),
  ('rpc grants', 'restore_archived_record anon has no EXECUTE', to_regprocedure('public.restore_archived_record(text,uuid)') is not null and not has_function_privilege('anon','public.restore_archived_record(text,uuid)','EXECUTE')),
  ('rpc grants', 'retry_workflow_run authenticated EXECUTE', to_regprocedure('public.retry_workflow_run(uuid)') is not null and has_function_privilege('authenticated','public.retry_workflow_run(uuid)','EXECUTE')),
  ('rpc grants', 'retry_workflow_run anon has no EXECUTE', to_regprocedure('public.retry_workflow_run(uuid)') is not null and not has_function_privilege('anon','public.retry_workflow_run(uuid)','EXECUTE')),
  ('rpc grants', 'clients_readiness authenticated EXECUTE', to_regprocedure('public.clients_readiness()') is not null and has_function_privilege('authenticated','public.clients_readiness()','EXECUTE')),
  ('rpc grants', 'clients_readiness anon has no EXECUTE', to_regprocedure('public.clients_readiness()') is not null and not has_function_privilege('anon','public.clients_readiness()','EXECUTE'))
)
select grp, item, case when ok then 'PRESENT' else 'MISSING' end as status from checks order by grp, item;
rollback;
