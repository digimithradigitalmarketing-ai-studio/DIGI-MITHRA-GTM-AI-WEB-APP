-- 0007a_gtm_workflow_baseline.sql
-- BASELINE, NOT NEW BEHAVIOUR. Records the workflow engine that already exists on the live
-- project, so the repository can reproduce it. The live objects were read from the catalog on
-- 2026-11-10 (pg_get_functiondef, pg_get_constraintdef, pg_policies, pg_trigger, information_schema).
--
-- On the live project this file changes nothing:
--   * every table, index, policy and trigger is guarded by an existence check, and
--   * every function is the exact definition the live catalog returns, so create or replace
--     writes identical text.
-- On a fresh database it recreates the engine that migration 0007 extends.
--
-- There is no rollback for this file. Dropping these objects would drop live workflow data.
-- Migration 0007 is the additive change, and it has its own rollback.

-- ---------------------------------------------------------------------------
-- Notifications (used by app_private.notify_workspace)
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  user_id uuid not null,
  title text not null,
  body text,
  link text,
  read_at timestamptz,
  created_at timestamptz default now() not null,
  constraint notifications_pkey primary key (id),
  constraint notifications_tenant_id_fkey foreign key (tenant_id) references public.tenants (id) on delete cascade,
  constraint notifications_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade
);
create index if not exists notifications_user_id_read_at_idx on public.notifications (user_id, read_at);
alter table public.notifications enable row level security;

-- ---------------------------------------------------------------------------
-- Workflow tables
-- ---------------------------------------------------------------------------
create table if not exists public.workflows (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  name text not null,
  description text,
  trigger_type text not null,
  status text default 'draft' not null,
  version integer default 1 not null,
  definition jsonb default '{"nodes": []}'::jsonb not null,
  created_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint workflows_pkey primary key (id),
  constraint workflows_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint workflows_status_check check (status = any (array['draft'::text, 'active'::text, 'paused'::text])),
  constraint workflows_trigger_type_check check (trigger_type = any (array['message_received'::text, 'lead_created'::text, 'manual'::text])),
  constraint workflows_created_by_fkey foreign key (created_by) references auth.users (id) on delete set null,
  constraint workflows_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade
);

create table if not exists public.workflow_versions (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  workflow_id uuid not null,
  version integer not null,
  definition jsonb not null,
  created_by uuid,
  created_at timestamptz default now() not null,
  constraint workflow_versions_pkey primary key (id),
  constraint workflow_versions_workflow_id_version_key unique (workflow_id, version),
  constraint workflow_versions_tenant_id_workspace_id_workflow_id_fkey foreign key (tenant_id, workspace_id, workflow_id)
    references public.workflows (tenant_id, workspace_id, id) on delete cascade
);

create table if not exists public.workflow_runs (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  workflow_id uuid not null,
  version integer not null,
  status text default 'running' not null,
  trigger_payload jsonb default '{}'::jsonb not null,
  dedupe_key text,
  error text,
  started_at timestamptz default now() not null,
  finished_at timestamptz,
  constraint workflow_runs_pkey primary key (id),
  constraint workflow_runs_workflow_id_dedupe_key_key unique (workflow_id, dedupe_key),
  constraint workflow_runs_status_check check (status = any (array['running'::text, 'completed'::text, 'skipped'::text, 'failed'::text, 'waiting_approval'::text, 'cancelled'::text])),
  constraint workflow_runs_tenant_id_workspace_id_workflow_id_fkey foreign key (tenant_id, workspace_id, workflow_id)
    references public.workflows (tenant_id, workspace_id, id) on delete cascade
);

create table if not exists public.workflow_steps (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  run_id uuid not null,
  position integer not null,
  node_type text not null,
  status text not null,
  output jsonb,
  created_at timestamptz default now() not null,
  constraint workflow_steps_pkey primary key (id),
  constraint workflow_steps_status_check check (status = any (array['completed'::text, 'skipped'::text, 'failed'::text])),
  constraint workflow_steps_run_id_fkey foreign key (run_id) references public.workflow_runs (id) on delete cascade,
  constraint workflow_steps_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade
);

alter table public.workflows enable row level security;
alter table public.workflow_versions enable row level security;
alter table public.workflow_runs enable row level security;
alter table public.workflow_steps enable row level security;

-- ---------------------------------------------------------------------------
-- Policies (created only if missing). Writes to runs, steps and versions happen only inside
-- security definer functions, so those tables have no insert, update or delete policy.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'notif_read') then
    create policy notif_read on public.notifications for select to authenticated using (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'notif_update') then
    create policy notif_update on public.notifications for update to authenticated
      using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'notifications' and policyname = 'notif_delete') then
    create policy notif_delete on public.notifications for delete to authenticated using (user_id = (select auth.uid()));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflows' and policyname = 'workflows_read') then
    create policy workflows_read on public.workflows for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflows' and policyname = 'workflows_insert') then
    create policy workflows_insert on public.workflows for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflows' and policyname = 'workflows_update') then
    create policy workflows_update on public.workflows for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager}'::text[]))
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflows' and policyname = 'workflows_delete') then
    create policy workflows_delete on public.workflows for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager}'::text[]));
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflow_versions' and policyname = 'workflow_versions_read') then
    create policy workflow_versions_read on public.workflow_versions for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflow_runs' and policyname = 'workflow_runs_read') then
    create policy workflow_runs_read on public.workflow_runs for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'workflow_steps' and policyname = 'workflow_steps_read') then
    create policy workflow_steps_read on public.workflow_steps for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Functions. Exact live definitions, so create or replace is a no-op on the live project.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app_private.require_ws_role(p_tenant uuid, p_workspace uuid, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if (select auth.uid()) is null then raise exception 'Not signed in' using errcode = '28000'; end if;
  if coalesce(app_private.ws_role(p_tenant, p_workspace), '') <> all (p_roles) then
    raise exception 'You do not have permission for this action' using errcode = '42501';
  end if;
end $function$;

CREATE OR REPLACE FUNCTION app_private.render_template(p_tpl text, p_payload jsonb, p_workspace uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select replace(replace(replace(coalesce(p_tpl, ''),
    '{{name}}', coalesce(split_part(p_payload->>'name', ' ', 1), 'there')),
    '{{business}}', coalesce((select name from public.workspaces where id = p_workspace), '')),
    '{{channel}}', coalesce(p_payload->>'channel', ''));
$function$;

CREATE OR REPLACE FUNCTION app_private.notify_workspace(p_tenant uuid, p_workspace uuid, p_title text, p_body text, p_link text, p_roles text[] DEFAULT ARRAY['admin'::text, 'manager'::text, 'editor'::text, 'support'::text, 'approver'::text])
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into public.notifications (tenant_id, user_id, title, body, link)
  select distinct p_tenant, u.user_id, p_title, p_body, p_link from (
    select tm.user_id from public.tenant_members tm
      where tm.tenant_id = p_tenant and tm.role in ('owner','admin') and 'admin' = any(p_roles)
    union
    select wm.user_id from public.workspace_members wm
      where wm.workspace_id = p_workspace and wm.role = any(p_roles)
  ) u;
$function$;

CREATE OR REPLACE FUNCTION app_private.store_workflow_version()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.workflow_versions (tenant_id, workspace_id, workflow_id, version, definition, created_by)
  values (new.tenant_id, new.workspace_id, new.id, new.version, new.definition, (select auth.uid()))
  on conflict (workflow_id, version) do nothing;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION app_private.version_workflow()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE' and new.definition is not distinct from old.definition then return new; end if;
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  return new;
end $function$;

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

CREATE OR REPLACE FUNCTION app_private.on_lead()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare w record;
begin
  if current_setting('app.in_workflow', true) = 'on' then return new; end if;
  for w in select id from public.workflows where workspace_id = new.workspace_id
           and status = 'active' and trigger_type = 'lead_created' loop
    perform app_private.run_workflow(w.id, jsonb_build_object('lead_id', new.id, 'name', new.title,
      'body', coalesce(new.notes, new.title), 'contact_id', new.contact_id, 'channel', new.source), 'lead_' || new.id);
  end loop;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.cancel_workflow_run(p_run uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare r public.workflow_runs;
begin
  select * into r from public.workflow_runs where id = p_run;
  perform app_private.require_ws_role(r.tenant_id, r.workspace_id, array['admin','manager']);
  update public.workflow_runs set status = 'cancelled', finished_at = now()
  where id = p_run and status in ('running','waiting_approval');
end $function$;

CREATE OR REPLACE FUNCTION public.run_workflow_test(p_workflow uuid, p_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare wf public.workflows;
begin
  select * into wf from public.workflows where id = p_workflow;
  if not found then raise exception 'Workflow not found'; end if;
  perform app_private.require_ws_role(wf.tenant_id, wf.workspace_id, array['admin','manager']);
  return app_private.run_workflow(p_workflow, coalesce(p_payload, '{}'::jsonb), 'manual_' || gen_random_uuid());
end $function$;

-- ---------------------------------------------------------------------------
-- Triggers (created only if missing on that table)
-- ---------------------------------------------------------------------------
do $$
declare
  spec record;
begin
  for spec in
    select * from (values
      ('workflows',          'trg_created_by',     'before insert',                    'app_private.set_created_by'),
      ('workflows',          'trg_updated',        'before update',                    'app_private.set_updated_at'),
      ('workflows',          'trg_version',        'before update',                    'app_private.version_workflow'),
      ('workflows',          'trg_store_version',  'after insert or update',           'app_private.store_workflow_version'),
      ('workflows',          'trg_audit',          'after insert or update or delete', 'app_private.audit'),
      ('leads',              'trg_on_lead',        'after insert',                     'app_private.on_lead')
    ) as v(tbl, name, timing, fn)
  loop
    if not exists (
      select 1 from pg_trigger
       where tgname = spec.name
         and tgrelid = format('public.%I', spec.tbl)::regclass
    ) then
      execute format(
        'create trigger %I %s on public.%I for each row execute function %s()',
        spec.name, spec.timing, spec.tbl, spec.fn);
    end if;
  end loop;
end $$;
