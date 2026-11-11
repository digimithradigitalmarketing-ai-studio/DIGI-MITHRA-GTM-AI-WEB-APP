-- 41_legacy_node_regression.sql
-- Differential regression for every node type the 0007a engine already ran. Each scenario runs once
-- through app_private.run_workflow_legacy (the 0007a body, extracted from the migration by run_local.sh and
-- loaded in this transaction) and once through the new app_private.run_workflow. The steps, the run status
-- and the error text must match. Side effects are then checked on the new run.
--
-- Runs in ONE transaction that the runner ends with ROLLBACK. The conversations and messages tables are
-- created here because the local replica does not have the inbox schema. Production has them, and this
-- file mirrors only the columns the engine writes. Synthetic data only.

-- ----------------------------------------------------------------- helpers (temporary)
create function pg_temp.assert_ok(p_label text, p_ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(p_ok, false) then
    raise exception 'FAIL %', p_label using errcode = 'P0100';
  end if;
  raise notice 'ok: %', p_label;
end $$;

-- ----------------------------------------------------------------- fixtures
-- Minimal inbox tables, columns as written by the engine (0007a run_workflow).
-- 'if not exists': on the production-shaped surface (00b) these tables already exist with production's columns, which
-- are a superset of these, so the engine test runs against production's shape there.
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  contact_id uuid,
  priority text not null default 'normal'
);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  conversation_id uuid not null,
  direction text not null,
  body text not null,
  sender_name text,
  is_ai_draft boolean not null default false,
  created_at timestamptz not null default now()
);

insert into auth.users (id, aud, role) values ('d0000000-0000-4000-8000-00000000d001', 'authenticated', 'authenticated')
  on conflict do nothing;
insert into public.tenants (id, name, slug, kind) values
  ('d1000000-0000-4000-8000-00000000000d', 'Regression Tenant', 'regression-tenant', 'agency');
insert into public.workspaces (id, tenant_id, name, slug) values
  ('d2000000-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-00000000000d', 'Regression Workspace', 'regression-ws');
insert into public.pipeline_stages (id, tenant_id, workspace_id, name, "position") values
  ('d5000000-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-00000000000d', 'd2000000-0000-4000-8000-0000000000d1', 'New', 1);

-- ----------------------------------------------------------------- harness
create temp table pair_results (
  label text primary key,
  legacy_status text, new_status text,
  legacy_error text, new_error text,
  legacy_steps jsonb, new_steps jsonb);
create temp table pair_ids (
  label text not null, run_side text not null,
  contact_id uuid, conv_id uuid, run_id uuid,
  primary key (label, run_side));

-- Steps as comparable JSON. Ids that differ between two runs of the same scenario are removed.
create function pg_temp.steps_json(p_run uuid) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'pos', s.position, 'type', s.node_type, 'status', s.status,
           'output', coalesce(s.output, '{}'::jsonb) - 'lead_id' - 'task_id' - 'automation_key' - 'created')
         order by s.position), '[]'::jsonb)
    from public.workflow_steps s where s.run_id = p_run
$$;

-- Runs one scenario through both engines, each on its own contact and conversation, so the second run
-- does not see the first run's side effects.
create function pg_temp.run_pair(p_label text, p_definition jsonb, p_body text,
  p_extra jsonb default '{}', p_drop text[] default '{}') returns void language plpgsql as $$
declare
  tenant constant uuid := 'd1000000-0000-4000-8000-00000000000d';
  ws constant uuid := 'd2000000-0000-4000-8000-0000000000d1';
  wf uuid := gen_random_uuid();
  v_side text;
  c uuid;
  cv uuid;
  payload jsonb;
  r uuid;
begin
  insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, status, definition)
  values (wf, tenant, ws, 'Scenario ' || p_label, 'manual', 'draft', p_definition);

  foreach v_side in array array['legacy', 'new'] loop
    c := gen_random_uuid();
    cv := gen_random_uuid();
    insert into public.contacts (id, tenant_id, workspace_id, name, tags) values (c, tenant, ws, 'Asha', '{}');
    insert into public.conversations (id, tenant_id, workspace_id, contact_id) values (cv, tenant, ws, c);
    insert into pair_ids (label, run_side, contact_id, conv_id) values (p_label, v_side, c, cv);

    payload := (jsonb_build_object('name', 'Asha', 'body', p_body, 'channel', 'whatsapp',
                                   'contact_id', c, 'conversation_id', cv) || p_extra) - p_drop;
    if v_side = 'legacy' then
      r := app_private.run_workflow_legacy(wf, payload, 'legacy-' || p_label);
    else
      r := app_private.run_workflow(wf, payload, 'new-' || p_label);
    end if;
    if r is null then raise exception 'scenario % produced no run', p_label; end if;
    update pair_ids set run_id = r where label = p_label and run_side = v_side;
  end loop;

  insert into pair_results (label, legacy_status, new_status, legacy_error, new_error, legacy_steps, new_steps)
  select p_label, l.status, n.status, l.error, n.error, pg_temp.steps_json(l.id), pg_temp.steps_json(n.id)
    from public.workflow_runs l, public.workflow_runs n
   where l.id = (select run_id from pair_ids where label = p_label and run_side = 'legacy')
     and n.id = (select run_id from pair_ids where label = p_label and run_side = 'new');
end
$$;

-- ----------------------------------------------------------------- scenarios
-- condition: contains (comma list, case-insensitive), equals, not_contains, default field, skip path
select pg_temp.run_pair('L1', '{"nodes":[{"type":"condition","config":{"field":"body","operator":"contains","value":"price, quote"}},{"type":"add_tag","config":{"tag":"pricing"}},{"type":"end"}]}', 'Can I get a QUOTE?');
select pg_temp.run_pair('L2', '{"nodes":[{"type":"condition","config":{"field":"body","operator":"contains","value":"price, quote"}},{"type":"add_tag","config":{"tag":"pricing"}},{"type":"end"}]}', 'hello there');
select pg_temp.run_pair('L3', '{"nodes":[{"type":"condition","config":{"field":"body","operator":"equals","value":"hi"}},{"type":"end"}]}', 'HI');
select pg_temp.run_pair('L4', '{"nodes":[{"type":"condition","config":{"field":"body","operator":"not_contains","value":"spam"}},{"type":"end"}]}', 'great product');
select pg_temp.run_pair('L15', '{"nodes":[{"type":"condition","config":{"operator":"contains","value":"pricing"}},{"type":"end"}]}', 'pricing question');
-- set_priority: explicit value, and the 'high' default when the config has none
select pg_temp.run_pair('L5', '{"nodes":[{"type":"set_priority","config":{"priority":"urgent"}},{"type":"end"}]}', 'help');
select pg_temp.run_pair('L6', '{"nodes":[{"type":"set_priority","config":{}},{"type":"end"}]}', 'help');
-- notify and wait: recorded steps, no side effect beyond the notification
select pg_temp.run_pair('L7', '{"nodes":[{"type":"notify","config":{"title":"New {{name}}","body":"Reply pending"}},{"type":"end"}]}', 'help');
select pg_temp.run_pair('L10', '{"nodes":[{"type":"wait","config":{"minutes":5}},{"type":"end"}]}', 'help');
-- ai_draft: a draft message on the conversation, and a skip when there is no conversation
select pg_temp.run_pair('L8', '{"nodes":[{"type":"ai_draft","config":{"template":"Hi {{name}}, from the team"}},{"type":"end"}]}', 'help');
select pg_temp.run_pair('L9', '{"nodes":[{"type":"ai_draft","config":{}},{"type":"end"}]}', 'help', '{}', array['conversation_id']);
-- approval: the run waits for a person
select pg_temp.run_pair('L11', '{"nodes":[{"type":"approval"},{"type":"end"}]}', 'refund request');
-- create_lead passes its lead id on; the next node still runs against the contact
select pg_temp.run_pair('L12', '{"nodes":[{"type":"create_lead","config":{"title":"Enquiry: {{name}}","value_inr":5000}},{"type":"add_tag","config":{"tag":"lead"}},{"type":"end"}]}', 'help');
-- a run-time failure: the payload's conversation id is not a uuid, so set_priority fails and the run is failed
select pg_temp.run_pair('L13', '{"nodes":[{"type":"set_priority","config":{"priority":"urgent"}},{"type":"end"}]}', 'help', '{"conversation_id":"not-a-uuid"}');
-- end stops the walk: the node after it never runs
select pg_temp.run_pair('L14', '{"nodes":[{"type":"end"},{"type":"add_tag","config":{"tag":"never"}}]}', 'help');

-- ----------------------------------------------------------------- checks
select pg_temp.assert_ok('LR0a all 15 legacy scenarios ran through both engines',
  (select count(*) from pair_results) = 15);
select pg_temp.assert_ok('LR0b the new engine produces the same steps, status and error as the legacy engine in every scenario',
  (select count(*) from pair_results
    where legacy_steps is distinct from new_steps
       or legacy_status is distinct from new_status
       or legacy_error is distinct from new_error) = 0);

select pg_temp.assert_ok('LR1 each scenario ends in the status its node path implies',
  (select count(*) from pair_results p
     join (values ('L1', 'completed'), ('L2', 'skipped'), ('L3', 'completed'), ('L4', 'completed'),
                  ('L5', 'completed'), ('L6', 'completed'), ('L7', 'completed'), ('L8', 'completed'),
                  ('L9', 'completed'), ('L10', 'completed'), ('L11', 'waiting_approval'), ('L12', 'completed'),
                  ('L13', 'failed'), ('L14', 'completed'), ('L15', 'completed')) e(label, status)
       on e.label = p.label and e.status = p.new_status) = 15);

select pg_temp.assert_ok('LR2 the failed scenario keeps the uuid error text from the engine',
  (select new_error like '%invalid input syntax for type uuid%' from pair_results where label = 'L13'));
select pg_temp.assert_ok('LR3 end stops the walk, so the node after it is not recorded',
  (select count(*) from pair_results p, jsonb_array_elements(p.new_steps) s
    where p.label = 'L14' and s->>'type' = 'add_tag') = 0);

-- Side effects, checked on the new engine's run (the legacy run is compared step by step above).
select pg_temp.assert_ok('LR4 add_tag adds the tag to the contact once the condition matches',
  (select 'pricing' = any (tags) from public.contacts
    where id = (select contact_id from pair_ids where label = 'L1' and run_side = 'new')));
select pg_temp.assert_ok('LR5 a skipped condition leaves the contact untouched',
  (select tags = '{}' from public.contacts
    where id = (select contact_id from pair_ids where label = 'L2' and run_side = 'new')));
select pg_temp.assert_ok('LR6 set_priority sets the conversation priority to the configured value',
  (select priority = 'urgent' from public.conversations
    where id = (select conv_id from pair_ids where label = 'L5' and run_side = 'new')));
select pg_temp.assert_ok('LR7 set_priority falls back to high when the config has none',
  (select priority = 'high' from public.conversations
    where id = (select conv_id from pair_ids where label = 'L6' and run_side = 'new')));
select pg_temp.assert_ok('LR8 ai_draft writes a rendered draft message marked as an AI draft',
  (select count(*) from public.messages
    where conversation_id = (select conv_id from pair_ids where label = 'L8' and run_side = 'new')
      and is_ai_draft and direction = 'outbound' and body = 'Hi Asha, from the team') = 1);
select pg_temp.assert_ok('LR9 ai_draft without a conversation writes no message',
  (select count(*) from public.messages where is_ai_draft and body like 'Hi Asha%'
     and conversation_id in (select conv_id from pair_ids where label = 'L9')) = 0);
-- Two leads: one from each engine's run of the scenario.
select pg_temp.assert_ok('LR10 create_lead writes one lead per engine, with the rendered title and value',
  (select count(*) from public.leads where title = 'Enquiry: Asha' and value_inr = 5000
     and tenant_id = 'd1000000-0000-4000-8000-00000000000d') = 2);
select pg_temp.assert_ok('LR11 the approval node notifies nobody when the workspace has no approvers',
  (select count(*) from public.notifications where tenant_id = 'd1000000-0000-4000-8000-00000000000d') = 0);
