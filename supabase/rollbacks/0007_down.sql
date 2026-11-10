-- 0007_down.sql
-- Rollback for 0007_gtm_automation_engine.sql. Requires separate approval and a verified backup.
-- It refuses to run while automation tasks or retry runs exist, so it cannot silently destroy data.
--
-- It restores the run_workflow body from 0007a (copied verbatim from lines 231-352 of that file),
-- the privilege state from before 0007, and drops the Phase 5 objects. It never drops a baseline
-- object from 0007a: the live workflow engine depends on those.
--
-- Run:  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/rollbacks/0007_down.sql

-- ---------------------------------------------------------------------------
-- 1. Restore the pre-0007 run_workflow (the 0007a body, without the create_task branch)
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
  node jsonb;
  cfg jsonb;
  i integer := 0;
  fieldval text;
  matched boolean;
  v_stage uuid;
  v_lead uuid;
  v_text text;
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
-- 2. Guards: refuse rather than destroy data that depends on the Phase 5 objects
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from public.tasks where automation_key is not null) then
    raise exception 'rollback refused: automation tasks exist; archive or delete them first' using errcode = '22023';
  end if;
  if exists (select 1 from public.workflow_runs where retry_of is not null or attempt <> 1) then
    raise exception 'rollback refused: retry runs exist; archive them first' using errcode = '22023';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Drop the Phase 5 objects
-- ---------------------------------------------------------------------------
drop function if exists public.retry_workflow_run(uuid);
drop trigger if exists trg_validate_definition on public.workflows;
drop function if exists app_private.validate_workflow_definition();
drop index if exists public.tasks_automation_key_uniq;
alter table public.tasks drop column if exists automation_key;
drop index if exists public.workflow_runs_retry_of_idx;
alter table public.workflow_runs drop column if exists retry_of, drop column if exists attempt;

-- ---------------------------------------------------------------------------
-- 4. Restore the privileges from before 0007 (Supabase default grants to anon and PUBLIC)
-- ---------------------------------------------------------------------------
grant all on public.workflows, public.workflow_versions, public.workflow_runs,
             public.workflow_steps, public.notifications to anon;
grant execute on function public.run_workflow_test(uuid, jsonb), public.cancel_workflow_run(uuid) to public, anon;
