-- 42_workflow_dependency_guard.sql (R3)
-- Run where public.conversations and public.messages are ABSENT (path C: base schema, 0007a and 0007 applied).
-- Synthetic data only, inside one transaction the runner ends with ROLLBACK.
--
-- Checks the dependency guard added in 0007:
--   * saving a workflow with set_priority or ai_draft is refused (22023) when the inbox table it writes is absent;
--   * a run that reaches such a node records a failed run with a named error, and the failing node writes nothing;
--   * an ai_draft node with no conversation in the payload does not need the table, so the run completes.
-- Validation is switched off for the run tests only, so the runtime guard is reached. It is switched back on afterwards.

create function pg_temp.expect_error_msg(p_label text, p_sql text, p_code text, p_needle text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when others then
    if sqlstate = 'P0100' then raise; end if;
    if sqlstate <> p_code or position(p_needle in sqlerrm) = 0 then
      raise exception 'FAIL %: expected % containing [%], got % (%)', p_label, p_code, p_needle, sqlstate, sqlerrm using errcode = 'P0100';
    end if;
end $$;

-- Precondition: the inbox tables must be absent, or this suite tests the wrong thing.
do $$
begin
  if to_regclass('public.conversations') is not null or to_regclass('public.messages') is not null then
    raise exception 'FAIL 42: this suite must run where public.conversations and public.messages are absent';
  end if;
end $$;

insert into public.tenants (id, name, slug, kind) values ('d1000000-0000-4000-8000-0000000000a0', 'WF Tenant', 'wf-tenant', 'agency');
insert into public.workspaces (id, tenant_id, name, slug) values ('d2000000-0000-4000-8000-0000000000a1', 'd1000000-0000-4000-8000-0000000000a0', 'WF1', 'wf1');

-- 1. Save-time refusal (validation is on).
select pg_temp.expect_error_msg('save a set_priority workflow without conversations',
  $q$insert into public.workflows (tenant_id, workspace_id, name, trigger_type, definition)
     values ('d1000000-0000-4000-8000-0000000000a0', 'd2000000-0000-4000-8000-0000000000a1', 'sp', 'manual',
             '{"nodes":[{"type":"set_priority","config":{"priority":"high"}}]}')$q$,
  '22023', 'node 1 (set_priority) needs public.conversations');
select pg_temp.expect_error_msg('save an ai_draft workflow without messages',
  $q$insert into public.workflows (tenant_id, workspace_id, name, trigger_type, definition)
     values ('d1000000-0000-4000-8000-0000000000a0', 'd2000000-0000-4000-8000-0000000000a1', 'ai', 'manual',
             '{"nodes":[{"type":"ai_draft","config":{}}]}')$q$,
  '22023', 'node 1 (ai_draft) needs public.messages');
-- A workflow that uses neither table saves normally.
insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, definition) values
  ('d3000000-0000-4000-8000-0000000000a1', 'd1000000-0000-4000-8000-0000000000a0', 'd2000000-0000-4000-8000-0000000000a1', 'tag only', 'manual',
   '{"nodes":[{"type":"add_tag","config":{"tag":"vip"}}]}');

-- 2. Runtime guard. Switch validation off for these fixtures only, so the node is reached at run time.
alter table public.workflows disable trigger trg_validate_definition;
insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, definition) values
  ('d3000000-0000-4000-8000-0000000000a2', 'd1000000-0000-4000-8000-0000000000a0', 'd2000000-0000-4000-8000-0000000000a1', 'sp run', 'manual',
   '{"nodes":[{"type":"add_tag","config":{"tag":"before"}},{"type":"set_priority","config":{"priority":"high"}}]}'),
  ('d3000000-0000-4000-8000-0000000000a3', 'd1000000-0000-4000-8000-0000000000a0', 'd2000000-0000-4000-8000-0000000000a1', 'ai run', 'manual',
   '{"nodes":[{"type":"ai_draft","config":{}}]}');
alter table public.workflows enable trigger trg_validate_definition;

do $$
declare
  v_run uuid;
  v_status text;
  v_err text;
begin
  -- set_priority with no inbox table: the run fails with the named error, and the failing node writes nothing.
  v_run := app_private.run_workflow('d3000000-0000-4000-8000-0000000000a2', '{}'::jsonb, 'd-sp-1');
  select status, error into v_status, v_err from public.workflow_runs where id = v_run;
  if v_status is distinct from 'failed' or position('this automation step needs public.conversations' in coalesce(v_err, '')) = 0 then
    raise exception 'FAIL 42: set_priority run: expected failed with a named error, got % (%)', v_status, v_err using errcode = 'P0100';
  end if;
  if exists (select 1 from public.workflow_steps where run_id = v_run and node_type = 'set_priority' and status = 'completed') then
    raise exception 'FAIL 42: the set_priority node is recorded as completed without its table' using errcode = 'P0100';
  end if;
  if not exists (select 1 from public.workflow_steps where run_id = v_run and node_type = 'set_priority' and status = 'failed') then
    raise exception 'FAIL 42: the set_priority failure is not recorded as a failed step' using errcode = 'P0100';
  end if;

  -- ai_draft with a conversation in the payload: the run fails with the named error for messages.
  v_run := app_private.run_workflow('d3000000-0000-4000-8000-0000000000a3',
             jsonb_build_object('conversation_id', gen_random_uuid()::text), 'd-ai-1');
  select status, error into v_status, v_err from public.workflow_runs where id = v_run;
  if v_status is distinct from 'failed' or position('this automation step needs public.messages' in coalesce(v_err, '')) = 0 then
    raise exception 'FAIL 42: ai_draft run: expected failed with a named error, got % (%)', v_status, v_err using errcode = 'P0100';
  end if;

  -- ai_draft with no conversation in the payload: the messages table is not used, so the run completes (step skipped).
  v_run := app_private.run_workflow('d3000000-0000-4000-8000-0000000000a3', '{}'::jsonb, 'd-ai-2');
  select status into v_status from public.workflow_runs where id = v_run;
  if v_status is distinct from 'completed' then
    raise exception 'FAIL 42: ai_draft without a conversation should complete, got %', v_status using errcode = 'P0100';
  end if;
end $$;

do $$ begin raise notice 'PASS 42_workflow_dependency_guard'; end $$;
