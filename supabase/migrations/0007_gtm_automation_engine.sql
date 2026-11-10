-- 0007_gtm_automation_engine.sql
-- Phase 5. Additive apart from one function replacement, which is documented below.
-- Requires 0007a_gtm_workflow_baseline.sql (the workflow engine it extends).
--
-- What this adds to the existing engine:
--   1. A create_task node. Each eligible lead event creates at most one follow-up task per node.
--   2. An idempotency key on tasks, with a partial unique index as the database safeguard.
--   3. Retry linkage on workflow_runs (retry_of, attempt). A retry is a new run, so the history
--      of the failed run is kept.
--   4. public.retry_workflow_run(run): retries only failed runs. A run has at most one retry, enforced
--      by a row lock and a unique index on retry_of. Retry the latest failed attempt, not the original.
--   5. A definition check on workflows. It rejects unknown node types and malformed nodes at write
--      time. Before this, an unknown type only failed at run time.
--
-- Replaced: app_private.run_workflow. The only changes are the new create_task branch and the
-- event key used for idempotency. Every other branch is identical to the 0007a baseline.
--
--   6. Privileges. anon loses access to the workflow tables and to the run controls. Supabase's default
--      privileges grant anon every new public table, and RLS is the only thing stopping it today.
--
-- Not applied to production. Requires a verified backup and separate approval.
-- Rollback: supabase/rollbacks/0007_down.sql.

-- ---------------------------------------------------------------------------
-- 0. Privileges. authenticated keeps its grants, and every read and write still goes through RLS.
-- ---------------------------------------------------------------------------
revoke all on public.workflows, public.workflow_versions, public.workflow_runs,
              public.workflow_steps, public.notifications from anon;
-- Functions carry a default EXECUTE grant to PUBLIC, so revoke from PUBLIC as well, then grant back.
-- The grant list matches production's ACL: authenticated and service_role, never PUBLIC or anon.
revoke all on function public.run_workflow_test(uuid, jsonb) from public, anon;
revoke all on function public.cancel_workflow_run(uuid) from public, anon;
grant execute on function public.run_workflow_test(uuid, jsonb) to authenticated, service_role;
grant execute on function public.cancel_workflow_run(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1. Idempotency key on tasks. Null for tasks created by people, so existing rows are unaffected.
-- ---------------------------------------------------------------------------
alter table public.tasks add column if not exists automation_key text;

create unique index if not exists tasks_automation_key_uniq
  on public.tasks (tenant_id, workspace_id, automation_key)
  where automation_key is not null;

-- ---------------------------------------------------------------------------
-- 2. Retry linkage on runs
-- ---------------------------------------------------------------------------
alter table public.workflow_runs
  add column if not exists retry_of uuid references public.workflow_runs (id) on delete set null,
  add column if not exists attempt integer not null default 1;

-- At most one retry per run. This is the database guarantee behind retry_workflow_run's row lock:
-- even if a second retry got past the lock, its insert would fail here and roll back with it.
drop index if exists public.workflow_runs_retry_of_idx;
create unique index if not exists workflow_runs_one_retry_uniq
  on public.workflow_runs (retry_of)
  where retry_of is not null;

-- ---------------------------------------------------------------------------
-- 3. Definition check. Structure and per-node config, so a bad definition fails at save time, not at run
--    time. It mirrors src/lib/automations/definition.ts (validateDefinition). Keep the two in step.
--    It runs only when the definition changes, so a status-only edit never re-validates old rows.
-- ---------------------------------------------------------------------------
create or replace function app_private.check_node_field(
  p_pos integer, p_type text, p_cfg jsonb, p_key text, p_kind text, p_required boolean,
  p_min integer, p_max integer, p_allowed text[] default null)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v jsonb := p_cfg -> p_key;
  s text;
  num numeric;
begin
  if v is null or jsonb_typeof(v) = 'null' then
    if p_required then
      raise exception 'node % (%): config.% is required', p_pos, p_type, p_key using errcode = '22023';
    end if;
    return;
  end if;

  if p_kind = 'text' then
    if jsonb_typeof(v) <> 'string' then
      raise exception 'node % (%): config.% must be text', p_pos, p_type, p_key using errcode = '22023';
    end if;
    s := v #>> '{}';
    if p_required and btrim(s) = '' then
      raise exception 'node % (%): config.% cannot be empty', p_pos, p_type, p_key using errcode = '22023';
    end if;
    if char_length(s) > p_max then
      raise exception 'node % (%): config.% is longer than % characters', p_pos, p_type, p_key, p_max
        using errcode = '22023';
    end if;
    if p_allowed is not null and not (s = any (p_allowed)) then
      raise exception 'node % (%): config.% must be one of: %', p_pos, p_type, p_key,
        array_to_string(p_allowed, ', ') using errcode = '22023';
    end if;
  elsif p_kind = 'int' then
    if jsonb_typeof(v) <> 'number' then
      raise exception 'node % (%): config.% must be a whole number', p_pos, p_type, p_key using errcode = '22023';
    end if;
    num := (v #>> '{}')::numeric;
    if num <> trunc(num) or num < p_min or num > p_max then
      raise exception 'node % (%): config.% must be a whole number from % to %', p_pos, p_type, p_key,
        p_min, p_max using errcode = '22023';
    end if;
  end if;
end
$$;

create or replace function app_private.validate_workflow_definition()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  node jsonb;
  ntype text;
  cfg jsonb;
  n integer := 0;
  allowed constant text[] := array[
    'condition', 'create_lead', 'add_tag', 'set_priority', 'notify',
    'ai_draft', 'wait', 'approval', 'end', 'create_task'];
  priorities constant text[] := array['low', 'normal', 'high', 'urgent'];
  operators constant text[] := array['contains', 'equals', 'not_contains'];
begin
  if jsonb_typeof(new.definition) is distinct from 'object'
     or jsonb_typeof(new.definition -> 'nodes') is distinct from 'array' then
    raise exception 'workflow definition must be an object with a nodes array' using errcode = '22023';
  end if;
  if jsonb_array_length(new.definition -> 'nodes') > 25 then
    raise exception 'a workflow can have at most 25 nodes' using errcode = '22023';
  end if;

  for node in select * from jsonb_array_elements(new.definition -> 'nodes') loop
    n := n + 1;
    if jsonb_typeof(node) is distinct from 'object' then
      raise exception 'node % must be an object', n using errcode = '22023';
    end if;
    ntype := node ->> 'type';
    if ntype is null or not (ntype = any (allowed)) then
      raise exception 'unknown workflow node type: % (node %)', coalesce(ntype, '(none)'), n using errcode = '22023';
    end if;

    -- config is optional. When present it must be an object, and each key the engine reads is checked.
    cfg := node -> 'config';
    if cfg is null or jsonb_typeof(cfg) = 'null' then
      cfg := '{}'::jsonb;
    elsif jsonb_typeof(cfg) <> 'object' then
      raise exception 'node % (%): config must be an object', n, ntype using errcode = '22023';
    end if;

    case ntype
      when 'condition' then
        perform app_private.check_node_field(n, ntype, cfg, 'field', 'text', false, 0, 40);
        perform app_private.check_node_field(n, ntype, cfg, 'operator', 'text', false, 0, 20, operators);
        perform app_private.check_node_field(n, ntype, cfg, 'value', 'text', false, 0, 200);
      when 'create_lead' then
        perform app_private.check_node_field(n, ntype, cfg, 'title', 'text', false, 0, 120);
        perform app_private.check_node_field(n, ntype, cfg, 'value_inr', 'int', false, 0, 10000000);
      when 'create_task' then
        perform app_private.check_node_field(n, ntype, cfg, 'title', 'text', false, 0, 120);
        perform app_private.check_node_field(n, ntype, cfg, 'description', 'text', false, 0, 500);
        perform app_private.check_node_field(n, ntype, cfg, 'due_in_hours', 'int', false, 1, 720);
        perform app_private.check_node_field(n, ntype, cfg, 'priority', 'text', false, 0, 20, priorities);
      when 'add_tag' then
        perform app_private.check_node_field(n, ntype, cfg, 'tag', 'text', true, 1, 40);
      when 'set_priority' then
        perform app_private.check_node_field(n, ntype, cfg, 'priority', 'text', false, 0, 20, priorities);
      when 'notify' then
        perform app_private.check_node_field(n, ntype, cfg, 'title', 'text', false, 0, 120);
        perform app_private.check_node_field(n, ntype, cfg, 'body', 'text', false, 0, 500);
      when 'ai_draft' then
        perform app_private.check_node_field(n, ntype, cfg, 'template', 'text', false, 0, 500);
      when 'wait' then
        perform app_private.check_node_field(n, ntype, cfg, 'minutes', 'int', false, 0, 43200);
      else
        null;  -- approval and end take no config
    end case;
  end loop;
  return new;
end
$$;

drop trigger if exists trg_validate_definition on public.workflows;
create trigger trg_validate_definition
  before insert or update of definition on public.workflows
  for each row execute function app_private.validate_workflow_definition();

-- ---------------------------------------------------------------------------
-- 4. run_workflow with the create_task node. This is a full replacement of the 0007a version.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_private.run_workflow(p_workflow uuid, p_payload jsonb, p_dedupe text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  wf public.workflows;
  v_run uuid;
  v_event text;
  node jsonb;
  cfg jsonb;
  i integer := 0;
  fieldval text;
  matched boolean;
  v_stage uuid;
  v_lead uuid;
  v_text text;
  v_key text;
  v_task uuid;
  v_rows integer;
  final text := 'completed';
begin
  select * into wf from public.workflows where id = p_workflow;
  if not found then return null; end if;
  insert into public.workflow_runs (tenant_id, workspace_id, workflow_id, version, trigger_payload, dedupe_key)
  values (wf.tenant_id, wf.workspace_id, wf.id, wf.version, p_payload, p_dedupe)
  on conflict (workflow_id, dedupe_key) do nothing
  returning id into v_run;
  if v_run is null then return null; end if;
  perform set_config('app.in_workflow', 'on', true);

  -- The event identity is stable across retries and replays. It is the lead, when there is one.
  -- Otherwise it is the run itself (manual runs).
  v_event := coalesce(nullif(p_payload->>'event_id', ''), nullif(p_payload->>'lead_id', ''), v_run::text);

  for node in select * from jsonb_array_elements(coalesce(wf.definition->'nodes', '[]'::jsonb)) loop
    i := i + 1;
    cfg := coalesce(node->'config', '{}'::jsonb);
    begin
      case node->>'type'
      when 'condition' then
        fieldval := lower(coalesce(p_payload->>(coalesce(cfg->>'field', 'body')), ''));
        matched := case coalesce(cfg->>'operator', 'contains')
          when 'equals' then fieldval = lower(coalesce(cfg->>'value', ''))
          when 'not_contains' then not exists (select 1 from unnest(string_to_array(lower(coalesce(cfg->>'value','')), ',')) k where trim(k) <> '' and fieldval like '%' || trim(k) || '%')
          else exists (select 1 from unnest(string_to_array(lower(coalesce(cfg->>'value','')), ',')) k where trim(k) <> '' and fieldval like '%' || trim(k) || '%')
        end;
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'condition', case when matched then 'completed' else 'skipped' end,
                jsonb_build_object('matched', matched, 'field', cfg->>'field', 'value', cfg->>'value'));
        if not matched then final := 'skipped'; exit; end if;

      when 'create_lead' then
        select id into v_stage from public.pipeline_stages where workspace_id = wf.workspace_id order by position limit 1;
        insert into public.leads (tenant_id, workspace_id, contact_id, stage_id, title, source, value_inr)
        values (wf.tenant_id, wf.workspace_id, (p_payload->>'contact_id')::uuid, v_stage,
          coalesce(nullif(app_private.render_template(cfg->>'title', p_payload, wf.workspace_id), ''), 'Enquiry from ' || coalesce(p_payload->>'name', 'contact')),
          coalesce(p_payload->>'channel', 'automation'), coalesce((cfg->>'value_inr')::int, 0))
        returning id into v_lead;
        p_payload := p_payload || jsonb_build_object('lead_id', v_lead);
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'create_lead', 'completed', jsonb_build_object('lead_id', v_lead));

      when 'create_task' then
        -- One task per (workflow, event, node). The unique index makes a replay or a retry a no-op.
        v_key := 'wf:' || wf.id::text || ':evt:' || v_event || ':node:' || i::text;
        insert into public.tasks (tenant_id, workspace_id, title, description, due_at, priority, status,
                                  lead_id, contact_id, automation_key)
        values (
          wf.tenant_id, wf.workspace_id,
          coalesce(nullif(app_private.render_template(cfg->>'title', p_payload, wf.workspace_id), ''),
                   'Follow up with ' || coalesce(p_payload->>'name', 'lead')),
          nullif(app_private.render_template(cfg->>'description', p_payload, wf.workspace_id), ''),
          now() + make_interval(hours => coalesce((cfg->>'due_in_hours')::int, 24)),
          coalesce(cfg->>'priority', 'normal'),
          'open',
          nullif(p_payload->>'lead_id', '')::uuid,
          nullif(p_payload->>'contact_id', '')::uuid,
          v_key)
        on conflict (tenant_id, workspace_id, automation_key) where automation_key is not null do nothing;
        get diagnostics v_rows = row_count;
        select id into v_task from public.tasks
         where tenant_id = wf.tenant_id and workspace_id = wf.workspace_id and automation_key = v_key;
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'create_task', 'completed',
                jsonb_build_object('task_id', v_task, 'automation_key', v_key, 'created', v_rows = 1));

      when 'add_tag' then
        update public.contacts set tags = array(select distinct unnest(tags || array[cfg->>'tag']))
        where id = (p_payload->>'contact_id')::uuid and workspace_id = wf.workspace_id;
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'add_tag', 'completed', jsonb_build_object('tag', cfg->>'tag'));

      when 'set_priority' then
        update public.conversations set priority = coalesce(cfg->>'priority', 'high')
        where id = (p_payload->>'conversation_id')::uuid and workspace_id = wf.workspace_id;
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'set_priority', 'completed', jsonb_build_object('priority', cfg->>'priority'));

      when 'notify' then
        perform app_private.notify_workspace(wf.tenant_id, wf.workspace_id,
          coalesce(nullif(app_private.render_template(cfg->>'title', p_payload, wf.workspace_id), ''), 'Automation: ' || wf.name),
          app_private.render_template(coalesce(cfg->>'body', p_payload->>'body'), p_payload, wf.workspace_id),
          case when p_payload ? 'conversation_id' then '/app/inbox?c=' || (p_payload->>'conversation_id') else '/app/automations' end);
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'notify', 'completed', jsonb_build_object('title', cfg->>'title'));

      when 'ai_draft' then
        if p_payload ? 'conversation_id' then
          v_text := app_private.render_template(coalesce(cfg->>'template',
            'Hi {{name}}, thanks for reaching out to {{business}}! Our team will get back to you shortly.'), p_payload, wf.workspace_id);
          insert into public.messages (tenant_id, workspace_id, conversation_id, direction, body, sender_name, is_ai_draft)
          values (wf.tenant_id, wf.workspace_id, (p_payload->>'conversation_id')::uuid, 'outbound', v_text, 'AI draft', true);
          insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
          values (wf.tenant_id, wf.workspace_id, v_run, i, 'ai_draft', 'completed', jsonb_build_object('draft', v_text, 'needs_review', true));
        else
          insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
          values (wf.tenant_id, wf.workspace_id, v_run, i, 'ai_draft', 'skipped', jsonb_build_object('reason', 'no conversation'));
        end if;

      when 'wait' then
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'wait', 'completed',
                jsonb_build_object('minutes', cfg->>'minutes', 'note', 'Delays are recorded; durable timers need the background worker'));

      when 'approval' then
        perform app_private.notify_workspace(wf.tenant_id, wf.workspace_id, 'Automation needs approval: ' || wf.name,
          left(p_payload->>'body', 120), '/app/automations', array['admin','manager','approver']);
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'approval', 'completed', jsonb_build_object('waiting', true));
        final := 'waiting_approval'; exit;

      when 'end' then
        insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status)
        values (wf.tenant_id, wf.workspace_id, v_run, i, 'end', 'completed');
        exit;

      else
        raise exception 'Unknown node type %', node->>'type';
      end case;
    exception when others then
      insert into public.workflow_steps (tenant_id, workspace_id, run_id, position, node_type, status, output)
      values (wf.tenant_id, wf.workspace_id, v_run, i, coalesce(node->>'type', '?'), 'failed', jsonb_build_object('error', sqlerrm));
      update public.workflow_runs set status = 'failed', error = sqlerrm, finished_at = now() where id = v_run;
      perform set_config('app.in_workflow', 'off', true);
      return v_run;
    end;
  end loop;

  update public.workflow_runs set status = final, finished_at = now() where id = v_run;
  perform set_config('app.in_workflow', 'off', true);
  return v_run;
end $function$;

-- ---------------------------------------------------------------------------
-- 5. Retry. Creates a new run linked to the failed one. Idempotent tasks make the retry safe.
-- ---------------------------------------------------------------------------
create or replace function public.retry_workflow_run(p_run uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.workflow_runs;
  v_child public.workflow_runs;
  v_new uuid;
begin
  -- Two retries of the same run race here. The row lock makes the second wait until the first commits.
  -- Once it has the lock, its statements see the first retry, so it is refused below. The unique index
  -- on retry_of is the backstop if any other path tries to add a second child.
  select * into r from public.workflow_runs where id = p_run for update;
  if not found then
    raise exception 'Run not found' using errcode = 'P0002';
  end if;
  perform app_private.require_ws_role(r.tenant_id, r.workspace_id, array['admin','manager']);
  if r.status <> 'failed' then
    raise exception 'Only failed runs can be retried; this run is %', r.status using errcode = '22023';
  end if;
  -- A run that already has a retry is not retried again. Retry the latest failed attempt by its own id.
  select * into v_child from public.workflow_runs where retry_of = r.id limit 1;
  if found then
    raise exception 'This run was already retried as run % (status %). Retry that run instead if it failed.',
      v_child.id, v_child.status using errcode = '22023';
  end if;

  v_new := app_private.run_workflow(r.workflow_id, r.trigger_payload,
            'retry_' || r.id::text || '_' || gen_random_uuid()::text);
  if v_new is null then
    raise exception 'The retry could not be recorded' using errcode = 'P0001';
  end if;
  update public.workflow_runs set retry_of = r.id, attempt = r.attempt + 1 where id = v_new;
  return v_new;
end
$$;

revoke all on function public.retry_workflow_run(uuid) from public, anon;
grant execute on function public.retry_workflow_run(uuid) to authenticated, service_role;
