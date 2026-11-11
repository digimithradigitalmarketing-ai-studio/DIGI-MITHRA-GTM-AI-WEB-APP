-- 40_automation_engine_tests.sql
-- Phase 5 automation engine. Synthetic data only. Runs inside ONE transaction that the runner
-- ends with ROLLBACK, so nothing persists. Each check calls pg_temp.assert_ok, which raises
-- FAIL, so psql stops with a non-zero exit.
--
-- Fixtures:
--   Tenant A: owner a001 (admin in A). Workspace A1: manager a002, editor a003, viewer a004.
--             Workspace A2: no workflow members.
--   Tenant B: owner b001 (admin in B only). Workspace B1.
--
-- Expected denials use these SQLSTATEs:
--   42501  RLS, or require_ws_role refusing the caller
--   23503  composite foreign key (a workspace that belongs to another tenant)
--   22023  definition validator, or a refused retry
--   P0002  run not found
--   23505  duplicate automation key (the database safeguard)

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

create function pg_temp.assert_ok(p_label text, p_ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then
    raise exception 'FAIL %', p_label using errcode = 'P0100';
  end if;
  raise notice 'ok: %', p_label;
end $$;

-- Passes only if the statement fails with exactly p_state. Its own failure uses P0100, which
-- the handler then reports as a mismatch.
create function pg_temp.expect_sqlstate(p_label text, p_state text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception when others then
  if sqlstate <> p_state then
    raise exception 'FAIL %: expected SQLSTATE %, got % (%)', p_label, p_state, sqlstate, sqlerrm using errcode = 'P0100';
  end if;
  raise notice 'ok: % (denied with %)', p_label, p_state;
end $$;

-- Returns the number of rows a DML statement touched. Use it for updates and deletes, where
-- RLS filters rows silently instead of raising an error.
create function pg_temp.affected(p_sql text) returns bigint language plpgsql as $$
declare n bigint;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end $$;

-- Captured run ids, readable by every test role so the denial checks can name a real run.
create temp table ids (k text primary key, v uuid);
grant select, insert on ids to public;

-- ----------------------------------------------------------------- 0. fixtures (owner)
select pg_temp.act_as_postgres();

insert into auth.users (id, aud, role) values
  ('a0000000-0000-4000-8000-00000000a001', 'authenticated', 'authenticated'),  -- owner A
  ('a0000000-0000-4000-8000-00000000a002', 'authenticated', 'authenticated'),  -- manager A1
  ('a0000000-0000-4000-8000-00000000a003', 'authenticated', 'authenticated'),  -- editor A1
  ('a0000000-0000-4000-8000-00000000a004', 'authenticated', 'authenticated'),  -- viewer A1
  ('b0000000-0000-4000-8000-00000000b001', 'authenticated', 'authenticated');  -- owner B

insert into public.tenants (id, name, slug, kind) values
  ('a1000000-0000-4000-8000-00000000000a', 'Tenant A', 'tenant-a-automation', 'agency'),
  ('b1000000-0000-4000-8000-00000000000b', 'Tenant B', 'tenant-b-automation', 'agency');

insert into public.workspaces (id, tenant_id, name, slug) values
  ('a2000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a', 'A1', 'a1-automation'),
  ('a2000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a', 'A2', 'a2-automation'),
  ('b2000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-00000000000b', 'B1', 'b1-automation');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-00000000a001', 'owner'),
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-00000000a002', 'viewer'),
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-00000000a003', 'viewer'),
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-00000000a004', 'viewer'),
  ('b1000000-0000-4000-8000-00000000000b', 'b0000000-0000-4000-8000-00000000b001', 'owner');

insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values
  ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000a002', 'manager'),
  ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000a003', 'editor'),
  ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-00000000a004', 'viewer');

insert into public.pipeline_stages (id, tenant_id, workspace_id, name, "position", is_won, is_lost) values
  ('e2000000-0000-4000-8000-00000000a101', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Open A1', 1, false, false),
  ('e2000000-0000-4000-8000-00000000b101', 'b1000000-0000-4000-8000-00000000000b', 'b2000000-0000-4000-8000-0000000000b1', 'Open B1', 1, false, false);

-- W1: the live follow-up workflow. One create_task node, then end.
-- W3: a draft with two nodes. Node 2 is valid to save but fails at run time on purpose: set_priority
-- casts the payload's conversation_id, and the T3 run passes a value that is not a uuid.
-- WB: tenant B's own workflow, used to show that B can still run its own workflows.
-- Without public.conversations, 0007's save-time check refuses the W3 draft (R3). The fixture is inserted with that
-- check off, as suite 42 does; the run-time refusal is what this suite exercises, and the check is back on afterwards.
alter table public.workflows disable trigger trg_validate_definition;
insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, status, definition) values
  ('a3000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'Lead follow-up', 'lead_created', 'active',
   '{"nodes":[{"type":"create_task","config":{"title":"Follow up with {{name}}","due_in_hours":24,"priority":"high"}},{"type":"end"}]}'),
  ('a3000000-0000-4000-8000-0000000000a3', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'Two-step follow-up', 'lead_created', 'draft',
   '{"nodes":[{"type":"create_task","config":{"title":"Call {{name}}","due_in_hours":24}},{"type":"set_priority","config":{"priority":"high"}},{"type":"end"}]}'),
  ('b3000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-00000000000b', 'b2000000-0000-4000-8000-0000000000b1',
   'Tenant B follow-up', 'lead_created', 'active',
   '{"nodes":[{"type":"create_task","config":{"title":"B follow up"}},{"type":"end"}]}');
alter table public.workflows enable trigger trg_validate_definition;

-- ----------------------------------------------------------------- P. privileges and shape
select pg_temp.assert_ok('P1 anon has no privileges on the workflow tables',
  not (has_table_privilege('anon', 'public.workflows', 'select')
    or has_table_privilege('anon', 'public.workflow_runs', 'select')
    or has_table_privilege('anon', 'public.workflow_steps', 'select')
    or has_table_privilege('anon', 'public.workflow_versions', 'select')));
select pg_temp.assert_ok('P2 anon cannot execute retry_workflow_run',
  not has_function_privilege('anon', 'public.retry_workflow_run(uuid)', 'execute'));
select pg_temp.assert_ok('P2b anon cannot execute the manual run or cancel controls',
  not has_function_privilege('anon', 'public.run_workflow_test(uuid, jsonb)', 'execute')
  and not has_function_privilege('anon', 'public.cancel_workflow_run(uuid)', 'execute'));
select pg_temp.assert_ok('P3 authenticated can execute retry_workflow_run',
  has_function_privilege('authenticated', 'public.retry_workflow_run(uuid)', 'execute'));
select pg_temp.assert_ok('P4 workflow tables have row level security enabled',
  (select bool_and(relrowsecurity) from pg_class
    where oid in ('public.workflows'::regclass, 'public.workflow_runs'::regclass,
                  'public.workflow_steps'::regclass, 'public.workflow_versions'::regclass)));
select pg_temp.assert_ok('P5 the automation key uniqueness index exists',
  to_regclass('public.tasks_automation_key_uniq') is not null);
select pg_temp.assert_ok('P6 the one-retry-per-run unique index exists',
  to_regclass('public.workflow_runs_one_retry_uniq') is not null);
-- Matches production's ACL for the two run controls: authenticated and service_role, nothing else.
select pg_temp.assert_ok('P7 service_role can execute the run controls and retry',
  has_function_privilege('service_role', 'public.run_workflow_test(uuid, jsonb)', 'execute')
  and has_function_privilege('service_role', 'public.cancel_workflow_run(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.retry_workflow_run(uuid)', 'execute'));
select pg_temp.assert_ok('P8 no PUBLIC or anon execute on the run controls or retry',
  not exists (
    select 1 from pg_proc p,
         lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     where p.oid in ('public.run_workflow_test(uuid, jsonb)'::regprocedure,
                     'public.cancel_workflow_run(uuid)'::regprocedure,
                     'public.retry_workflow_run(uuid)'::regprocedure)
       and (a.grantee = 0 or pg_get_userbyid(a.grantee) = 'anon')));

-- ----------------------------------------------------------------- 1. one lead event, one task
-- The lead trigger fires the active workflow. Its create_task node makes one follow-up task.
insert into public.leads (id, tenant_id, workspace_id, stage_id, title, value_inr, source) values
  ('a4000000-0000-4000-8000-00000000a001', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'e2000000-0000-4000-8000-00000000a101', 'Lead one', 0, 'web');

select pg_temp.assert_ok('T1a one lead event creates exactly one follow-up task',
  (select count(*) from public.tasks where lead_id = 'a4000000-0000-4000-8000-00000000a001') = 1);
select pg_temp.assert_ok('T1b the run is recorded once under the lead dedupe key',
  (select count(*) from public.workflow_runs
    where workflow_id = 'a3000000-0000-4000-8000-0000000000a1'
      and dedupe_key = 'lead_a4000000-0000-4000-8000-00000000a001' and status = 'completed') = 1);
select pg_temp.assert_ok('T1c the task carries its automation key',
  (select count(*) from public.tasks
    where automation_key = 'wf:a3000000-0000-4000-8000-0000000000a1:evt:a4000000-0000-4000-8000-00000000a001:node:1') = 1);
-- {{name}} renders the first word of the lead name, as render_template does for every workflow.
select pg_temp.assert_ok('T1d the task title is rendered and the priority and due date are applied',
  (select count(*) from public.tasks
    where lead_id = 'a4000000-0000-4000-8000-00000000a001'
      and title = 'Follow up with Lead' and priority = 'high' and status = 'open'
      and due_at between now() + interval '23 hours' and now() + interval '25 hours') = 1);

-- ----------------------------------------------------------------- 2. replays do not duplicate
select pg_temp.assert_ok('T2a replaying the same lead dedupe key returns no run',
  app_private.run_workflow('a3000000-0000-4000-8000-0000000000a1'::uuid,
    jsonb_build_object('lead_id', 'a4000000-0000-4000-8000-00000000a001', 'name', 'Lead one'),
    'lead_a4000000-0000-4000-8000-00000000a001') is null);

select app_private.run_workflow('a3000000-0000-4000-8000-0000000000a1'::uuid,
  jsonb_build_object('lead_id', 'a4000000-0000-4000-8000-00000000a001', 'name', 'Lead one'),
  'replay_' || gen_random_uuid()::text);

select pg_temp.assert_ok('T2b a replay under a new run key still leaves one task',
  (select count(*) from public.tasks where lead_id = 'a4000000-0000-4000-8000-00000000a001') = 1);
select pg_temp.assert_ok('T2c the replayed step reports that it created nothing',
  (select count(*) from public.workflow_steps s
     join public.workflow_runs r on r.id = s.run_id
    where r.dedupe_key like 'replay_%' and s.node_type = 'create_task'
      and s.output->>'created' = 'false') = 1);

select pg_temp.expect_sqlstate('T2d the database rejects a second task with the same automation key', '23505', $q$
  insert into public.tasks (tenant_id, workspace_id, title, priority, status, lead_id, automation_key)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Duplicate', 'normal', 'open',
          'a4000000-0000-4000-8000-00000000a001',
          'wf:a3000000-0000-4000-8000-0000000000a1:evt:a4000000-0000-4000-8000-00000000a001:node:1')
$q$);

-- ----------------------------------------------------------------- 3. failed run, safe retry
-- L2 fires W1 as well, so every check below filters on W3's own automation key prefix.
insert into public.leads (id, tenant_id, workspace_id, stage_id, title, value_inr, source) values
  ('a4000000-0000-4000-8000-00000000a002', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'e2000000-0000-4000-8000-00000000a101', 'Lead two', 0, 'web');

-- The manager runs the draft manually. Node 1 creates its task, then node 2 fails.
select pg_temp.act_as(
  'a0000000-0000-4000-8000-00000000a002');
select public.run_workflow_test('a3000000-0000-4000-8000-0000000000a3'::uuid,
  jsonb_build_object('lead_id', 'a4000000-0000-4000-8000-00000000a002', 'name', 'Lead two',
                     'conversation_id', 'not-a-uuid'));

select pg_temp.act_as_postgres();
insert into ids select 'failed_w3', id from public.workflow_runs
 where workflow_id = 'a3000000-0000-4000-8000-0000000000a3' and status = 'failed';

select pg_temp.assert_ok('T3a the failed run keeps its error text',
  (select count(*) from public.workflow_runs r join ids on ids.k = 'failed_w3' and r.id = ids.v
    where r.status = 'failed' and r.error is not null) = 1);
select pg_temp.assert_ok('T3b the failed step is logged',
  (select count(*) from public.workflow_steps s join ids on ids.k = 'failed_w3' and s.run_id = ids.v
    where s.status = 'failed') = 1);
select pg_temp.assert_ok('T3c the failed attempt left only node 1 task behind',
  (select count(*) from public.tasks
    where automation_key like 'wf:a3000000-0000-4000-8000-0000000000a3:evt:a4000000-0000-4000-8000-00000000a002:%') = 1);

-- The manager corrects the definition, then retries the failed run.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.assert_ok('T3d the manager can correct the broken definition',
  pg_temp.affected($q$
    update public.workflows
       set definition = '{"nodes":[{"type":"create_task","config":{"title":"Call {{name}}","due_in_hours":24}},{"type":"create_task","config":{"title":"Second touch","due_in_hours":24}},{"type":"end"}]}'::jsonb
     where id = 'a3000000-0000-4000-8000-0000000000a3'
  $q$) = 1);

select public.retry_workflow_run((select v from ids where k = 'failed_w3'));

select pg_temp.act_as_postgres();
insert into ids select 'retry_w3', id from public.workflow_runs
 where retry_of = (select v from ids where k = 'failed_w3');

select pg_temp.assert_ok('T3e the retry is a new completed run linked to the failed one with attempt 2',
  (select count(*) from public.workflow_runs r join ids on ids.k = 'retry_w3' and r.id = ids.v
    where r.retry_of = (select v from ids where k = 'failed_w3') and r.status = 'completed' and r.attempt = 2) = 1);
select pg_temp.assert_ok('T3f the retry creates node 2 and does not duplicate node 1',
  (select count(*) from public.tasks
    where automation_key like 'wf:a3000000-0000-4000-8000-0000000000a3:evt:a4000000-0000-4000-8000-00000000a002:%') = 2);
select pg_temp.assert_ok('T3g the retry reports that node 1 created nothing',
  (select count(*) from public.workflow_steps s join ids on ids.k = 'retry_w3' and s.run_id = ids.v
    where s.node_type = 'create_task' and s.position = 1 and s.output->>'created' = 'false') = 1);
select pg_temp.assert_ok('T3h the failed run is kept as history',
  (select count(*) from public.workflow_runs r join ids on ids.k = 'failed_w3' and r.id = ids.v
    where r.status = 'failed') = 1);

-- Refusals. A second retry is blocked while a successful retry exists.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.expect_sqlstate('R1 a failed run with a successful retry cannot be retried again', '22023',
  $q$select public.retry_workflow_run((select v from pg_temp.ids where k = 'failed_w3'))$q$);
select pg_temp.expect_sqlstate('R2 a completed run cannot be retried', '22023', $q$
  select public.retry_workflow_run((select id from public.workflow_runs
    where workflow_id = 'a3000000-0000-4000-8000-0000000000a1' and dedupe_key = 'lead_a4000000-0000-4000-8000-00000000a001'))
$q$);
select pg_temp.expect_sqlstate('R3 an unknown run is reported as not found', 'P0002',
  $q$select public.retry_workflow_run('00000000-0000-4000-8000-0000000000ff'::uuid)$q$);

-- Concurrency backstop. Even if a second child row is written directly, the unique index refuses it.
select pg_temp.act_as_postgres();
select pg_temp.expect_sqlstate('R3b a second retry row for the same run violates the unique index', '23505', $q$
  insert into public.workflow_runs (tenant_id, workspace_id, workflow_id, version, trigger_payload, dedupe_key, status, retry_of, attempt)
  select tenant_id, workspace_id, workflow_id, version, trigger_payload, 'dup-child-r3b', 'failed', id, 2
    from public.workflow_runs where id = (select v from pg_temp.ids where k = 'failed_w3')
$q$);

-- ----------------------------------------------------------------- 3b. retry of a retry
-- The first retry (retry_w3) fails. The owner marks it failed, as a real failure would leave it.
select pg_temp.assert_ok('T3i the first retry can be marked failed for the retry-of-retry check',
  pg_temp.affected($q$
    update public.workflow_runs set status = 'failed', error = 'simulated failure', finished_at = now()
     where id = (select v from pg_temp.ids where k = 'retry_w3')
  $q$) = 1);

select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select public.retry_workflow_run((select v from ids where k = 'retry_w3'));

select pg_temp.act_as_postgres();
insert into ids select 'retry2_w3', id from public.workflow_runs
 where retry_of = (select v from ids where k = 'retry_w3');

select pg_temp.assert_ok('T3j the retry of a retry is attempt 3 and links to the failed retry',
  (select count(*) from public.workflow_runs r join ids on ids.k = 'retry2_w3' and r.id = ids.v
    where r.retry_of = (select v from ids where k = 'retry_w3') and r.attempt = 3 and r.status = 'completed') = 1);
select pg_temp.assert_ok('T3k the second retry creates no duplicate task',
  (select count(*) from public.tasks
    where automation_key like 'wf:a3000000-0000-4000-8000-0000000000a3:evt:a4000000-0000-4000-8000-00000000a002:%') = 2);

select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.expect_sqlstate('R4 a run that already has a retry cannot be retried again, even if it failed', '22023',
  $q$select public.retry_workflow_run((select v from pg_temp.ids where k = 'retry_w3'))$q$);
select pg_temp.expect_sqlstate('R5 a completed retry cannot be retried', '22023',
  $q$select public.retry_workflow_run((select v from pg_temp.ids where k = 'retry2_w3'))$q$);
select pg_temp.expect_sqlstate('R6 the original failed run is still refused after the chain grew', '22023',
  $q$select public.retry_workflow_run((select v from pg_temp.ids where k = 'failed_w3'))$q$);
select pg_temp.act_as_postgres();

-- ----------------------------------------------------------------- 4. tenant isolation (tenant B)
select pg_temp.act_as('b0000000-0000-4000-8000-00000000b001');
select pg_temp.assert_ok('T4a tenant B cannot see tenant A workflows',
  (select count(*) from public.workflows where tenant_id = 'a1000000-0000-4000-8000-00000000000a') = 0);
select pg_temp.assert_ok('T4b tenant B cannot see tenant A workflow runs',
  (select count(*) from public.workflow_runs where tenant_id = 'a1000000-0000-4000-8000-00000000000a') = 0);
select pg_temp.assert_ok('T4c tenant B cannot see tenant A workflow steps',
  (select count(*) from public.workflow_steps where tenant_id = 'a1000000-0000-4000-8000-00000000000a') = 0);
select pg_temp.assert_ok('T4d tenant B cannot see tenant A workflow versions',
  (select count(*) from public.workflow_versions where tenant_id = 'a1000000-0000-4000-8000-00000000000a') = 0);
select pg_temp.expect_sqlstate('T4e tenant B cannot create a workflow in tenant A', '42501', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Hijack', 'lead_created', 'draft', '{"nodes":[]}')
$q$);
select pg_temp.expect_sqlstate('T4f tenant B cannot attach a workflow to tenant A workspace under its own tenant', '23503', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('b1000000-0000-4000-8000-00000000000b', 'a2000000-0000-4000-8000-0000000000a1', 'Hijack', 'lead_created', 'draft', '{"nodes":[]}')
$q$);
select pg_temp.assert_ok('T4g tenant B cannot change a tenant A workflow',
  pg_temp.affected($q$update public.workflows set name = 'Hijack' where id = 'a3000000-0000-4000-8000-0000000000a1'$q$) = 0);
select pg_temp.assert_ok('T4h tenant B cannot delete a tenant A workflow',
  pg_temp.affected($q$delete from public.workflows where id = 'a3000000-0000-4000-8000-0000000000a1'$q$) = 0);
select pg_temp.expect_sqlstate('T4i tenant B cannot run a tenant A workflow manually', '42501',
  $q$select public.run_workflow_test('a3000000-0000-4000-8000-0000000000a1'::uuid, '{}'::jsonb)$q$);
select pg_temp.expect_sqlstate('T4j tenant B cannot retry a tenant A run', '42501',
  $q$select public.retry_workflow_run((select v from pg_temp.ids where k = 'failed_w3'))$q$);
select public.run_workflow_test('b3000000-0000-4000-8000-0000000000b1'::uuid, '{"name":"B manual"}'::jsonb);
select pg_temp.assert_ok('T4k tenant B can still run its own workflow',
  (select count(*) from public.workflow_runs where workflow_id = 'b3000000-0000-4000-8000-0000000000b1') = 1);

select pg_temp.act_as_postgres();
select pg_temp.assert_ok('T4l tenant A workflow is unchanged after tenant B attempts',
  (select count(*) from public.workflows
    where id = 'a3000000-0000-4000-8000-0000000000a1' and name = 'Lead follow-up' and status = 'active') = 1);

-- ----------------------------------------------------------------- 5. unauthorized roles
-- Editor and viewer in A1. Neither may create or change workflows, run them, or retry them.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a003');
select pg_temp.expect_sqlstate('T5a an editor cannot create a workflow', '42501', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Editor build', 'lead_created', 'draft', '{"nodes":[{"type":"end"}]}')
$q$);
select pg_temp.assert_ok('T5b an editor cannot pause a workflow',
  pg_temp.affected($q$update public.workflows set status = 'paused' where id = 'a3000000-0000-4000-8000-0000000000a1'$q$) = 0);
select pg_temp.expect_sqlstate('T5c an editor cannot run a workflow manually', '42501',
  $q$select public.run_workflow_test('a3000000-0000-4000-8000-0000000000a1'::uuid, '{}'::jsonb)$q$);
select pg_temp.expect_sqlstate('T5d an editor cannot retry a failed run', '42501',
  $q$select public.retry_workflow_run((select v from pg_temp.ids where k = 'failed_w3'))$q$);

select pg_temp.act_as('a0000000-0000-4000-8000-00000000a004');
select pg_temp.expect_sqlstate('T5e a viewer cannot create a workflow', '42501', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Viewer build', 'lead_created', 'draft', '{"nodes":[{"type":"end"}]}')
$q$);
select pg_temp.assert_ok('T5f a viewer cannot edit a workflow',
  pg_temp.affected($q$update public.workflows set name = 'Viewer edit' where id = 'a3000000-0000-4000-8000-0000000000a1'$q$) = 0);
select pg_temp.expect_sqlstate('T5g a viewer cannot run a workflow manually', '42501',
  $q$select public.run_workflow_test('a3000000-0000-4000-8000-0000000000a1'::uuid, '{}'::jsonb)$q$);

-- ----------------------------------------------------------------- 6. pause, resume, run history
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.assert_ok('T6a the manager can pause a workflow',
  pg_temp.affected($q$update public.workflows set status = 'paused' where id = 'a3000000-0000-4000-8000-0000000000a1'$q$) = 1);

-- A paused workflow must not fire on new leads. The editor creates the lead, as the CRM would.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a003');
insert into public.leads (id, tenant_id, workspace_id, stage_id, title, value_inr, source) values
  ('a4000000-0000-4000-8000-00000000a003', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'e2000000-0000-4000-8000-00000000a101', 'Lead three', 0, 'web');

select pg_temp.act_as_postgres();
select pg_temp.assert_ok('T6b a paused workflow creates no task for a new lead',
  (select count(*) from public.tasks where lead_id = 'a4000000-0000-4000-8000-00000000a003') = 0);
select pg_temp.assert_ok('T6c a paused workflow records no run for a new lead',
  (select count(*) from public.workflow_runs where dedupe_key = 'lead_a4000000-0000-4000-8000-00000000a003') = 0);

select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.assert_ok('T6d the manager can resume a workflow',
  pg_temp.affected($q$update public.workflows set status = 'active' where id = 'a3000000-0000-4000-8000-0000000000a1'$q$) = 1);

select pg_temp.act_as('a0000000-0000-4000-8000-00000000a003');
insert into public.leads (id, tenant_id, workspace_id, stage_id, title, value_inr, source) values
  ('a4000000-0000-4000-8000-00000000a004', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'e2000000-0000-4000-8000-00000000a101', 'Lead four', 0, 'web');

select pg_temp.act_as_postgres();
select pg_temp.assert_ok('T6e after resume a new lead creates exactly one task',
  (select count(*) from public.tasks where lead_id = 'a4000000-0000-4000-8000-00000000a004') = 1);

-- ----------------------------------------------------------------- 7. manual run controls
-- Lead five already has its follow-up from the trigger. A manual run for it must not add a second.
insert into public.leads (id, tenant_id, workspace_id, stage_id, title, value_inr, source) values
  ('a4000000-0000-4000-8000-00000000a005', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'e2000000-0000-4000-8000-00000000a101', 'Lead five', 0, 'web');

select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.assert_ok('T7a the manager can run a workflow manually',
  (select public.run_workflow_test('a3000000-0000-4000-8000-0000000000a1'::uuid,
     jsonb_build_object('lead_id', 'a4000000-0000-4000-8000-00000000a005', 'name', 'Lead five')) is not null));

select pg_temp.act_as_postgres();
select pg_temp.assert_ok('T7b a manual run does not duplicate the lead follow-up task',
  (select count(*) from public.tasks where lead_id = 'a4000000-0000-4000-8000-00000000a005') = 1);
select pg_temp.assert_ok('T7c the manual run is recorded with its payload',
  (select count(*) from public.workflow_runs
    where dedupe_key like 'manual_%' and trigger_payload->>'lead_id' = 'a4000000-0000-4000-8000-00000000a005') = 1);

-- ----------------------------------------------------------------- 8. definition validator
select pg_temp.expect_sqlstate('V1 an unknown node type is rejected at write time', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft', '{"nodes":[{"type":"send_email"}]}')
$q$);
select pg_temp.expect_sqlstate('V2 a node without a type is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft', '{"nodes":[{"config":{}}]}')
$q$);
select pg_temp.expect_sqlstate('V3 a definition without a nodes array is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft', '{}')
$q$);
select pg_temp.expect_sqlstate('V4 an edit that adds an unknown node type is rejected', '22023', $q$
  update public.workflows set definition = '{"nodes":[{"type":"delete_all"}]}' where id = 'a3000000-0000-4000-8000-0000000000a1'
$q$);
select pg_temp.assert_ok('V5 the rejected edit left the live definition unchanged',
  (select count(*) from public.workflows
    where id = 'a3000000-0000-4000-8000-0000000000a1'
      and definition->'nodes'->0->>'type' = 'create_task') = 1);

-- Malformed node configuration is refused at save time, with the node named in the message.
select pg_temp.act_as_postgres();
select pg_temp.expect_sqlstate('V6 a text due_in_hours is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"create_task","config":{"due_in_hours":"soon"}}]}')
$q$);
select pg_temp.expect_sqlstate('V7 a config that is not an object is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"create_task","config":"24h"}]}')
$q$);
select pg_temp.expect_sqlstate('V8 an add_tag node without a tag is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"add_tag","config":{"tag":"   "}}]}')
$q$);
select pg_temp.expect_sqlstate('V9 due_in_hours of zero is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"create_task","config":{"due_in_hours":0}}]}')
$q$);
select pg_temp.expect_sqlstate('V10 due_in_hours above 720 is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"create_task","config":{"due_in_hours":721}}]}')
$q$);
select pg_temp.expect_sqlstate('V11 a fractional due_in_hours is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"create_task","config":{"due_in_hours":1.5}}]}')
$q$);
select pg_temp.expect_sqlstate('V12 an unknown priority is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"set_priority","config":{"priority":"critical"}}]}')
$q$);
select pg_temp.expect_sqlstate('V13 an unknown condition operator is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":[{"type":"condition","config":{"operator":"starts_with","value":"x"}}]}')
$q$);
select pg_temp.expect_sqlstate('V14 a node that is not an object is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          '{"nodes":["end"]}')
$q$);
select pg_temp.expect_sqlstate('V15 a description over 500 characters is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          jsonb_build_object('nodes', jsonb_build_array(jsonb_build_object('type', 'create_task',
            'config', jsonb_build_object('description', repeat('x', 501))))))
$q$);
select pg_temp.expect_sqlstate('V16 more than 25 nodes is rejected', '22023', $q$
  insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Bad', 'lead_created', 'draft',
          jsonb_build_object('nodes', (select jsonb_agg(jsonb_build_object('type', 'wait')) from generate_series(1, 26))))
$q$);
select pg_temp.assert_ok('V17 the boundary values are accepted (720 hours, urgent, a 25-node limit)',
  pg_temp.affected($q$
    insert into public.workflows (tenant_id, workspace_id, name, trigger_type, status, definition)
    values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Edge', 'lead_created', 'draft',
            '{"nodes":[{"type":"create_task","config":{"due_in_hours":720,"priority":"urgent","title":"Edge"}},{"type":"add_tag","config":{"tag":"vip"}},{"type":"end"}]}')
  $q$) = 1);

-- A status-only change never re-validates the definition. A row that predates the check (planted here with
-- the trigger off, as a migration or a restore could leave it) can still be paused, but any new
-- definition for it must pass.
select pg_temp.act_as_postgres();
alter table public.workflows disable trigger trg_validate_definition;
insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, status, definition) values
  ('a3000000-0000-4000-8000-0000000000e1', 'a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'Legacy', 'lead_created', 'active', '{"nodes":[{"type":"add_tag","config":{}}]}');
alter table public.workflows enable trigger trg_validate_definition;
select pg_temp.assert_ok('V18 a legacy invalid row can still be paused (status-only edit)',
  pg_temp.affected($q$ update public.workflows set status = 'paused' where id = 'a3000000-0000-4000-8000-0000000000e1' $q$) = 1);
select pg_temp.expect_sqlstate('V19 an edit to a legacy row must pass the check', '22023', $q$
  update public.workflows set definition = '{"nodes":[{"type":"add_tag","config":{}}]}' where id = 'a3000000-0000-4000-8000-0000000000e1'
$q$);

-- ----------------------------------------------------------------- 9. existing CRM still works
-- An editor creates a lead and manual tasks through the normal CRM path.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a003');
select pg_temp.assert_ok('C1 an editor can still create a lead',
  pg_temp.affected($q$
    insert into public.leads (id, tenant_id, workspace_id, stage_id, title, value_inr, source)
    values ('a4000000-0000-4000-8000-00000000a006', 'a1000000-0000-4000-8000-00000000000a',
            'a2000000-0000-4000-8000-0000000000a1', 'e2000000-0000-4000-8000-00000000a101', 'CRM lead', 0, 'web')
  $q$) = 1);
select pg_temp.assert_ok('C2 an editor can create a manual task without an automation key',
  pg_temp.affected($q$
    insert into public.tasks (tenant_id, workspace_id, title, priority, status, lead_id)
    values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
            'Call back', 'normal', 'open', 'a4000000-0000-4000-8000-00000000a006')
  $q$) = 1);
select pg_temp.assert_ok('C3 a second manual task on the same lead is also allowed',
  pg_temp.affected($q$
    insert into public.tasks (tenant_id, workspace_id, title, priority, status, lead_id)
    values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
            'Send proposal', 'normal', 'open', 'a4000000-0000-4000-8000-00000000a006')
  $q$) = 1);

select pg_temp.act_as_postgres();
select pg_temp.assert_ok('C4 the CRM lead still received its automation task',
  (select count(*) from public.tasks
    where lead_id = 'a4000000-0000-4000-8000-00000000a006' and automation_key is not null) = 1);
select pg_temp.assert_ok('C5 the manual tasks are not counted as automation tasks',
  (select count(*) from public.tasks
    where lead_id = 'a4000000-0000-4000-8000-00000000a006' and automation_key is null) = 2);

-- Final check: the run history is readable to the manager who owns the workspace.
select pg_temp.act_as('a0000000-0000-4000-8000-00000000a002');
select pg_temp.assert_ok('H1 the manager can read run history for the workspace',
  (select count(*) from public.workflow_runs where workflow_id = 'a3000000-0000-4000-8000-0000000000a1') >= 1);

-- H2. The H3 exclusion in gtm_scope_rls.sql leaves these five tables out of the scope fingerprint. This
-- check pins their own policies instead. The value below is production's fingerprint, read-only, before
-- any Phase 5 migration. If a policy here changes, this fails, and the change needs its own review.
select pg_temp.assert_ok('H2 the five workflow and notification tables keep production policies (fingerprint dbaa7dda)',
  (select count(*) from pg_policies where schemaname = 'public'
     and tablename in ('workflows', 'workflow_versions', 'workflow_runs', 'workflow_steps', 'notifications')) = 10
  and (select md5(coalesce(string_agg(tablename || '|' || policyname || '|' || cmd || '|' || roles::text || '|' ||
        coalesce(qual, '') || '|' || coalesce(with_check, ''), E'\n' order by tablename, policyname), ''))
       from pg_policies where schemaname = 'public'
         and tablename in ('workflows', 'workflow_versions', 'workflow_runs', 'workflow_steps', 'notifications'))
      = 'dbaa7dda3908b3091076590c8d6d2b93');

select pg_temp.act_as_postgres();
