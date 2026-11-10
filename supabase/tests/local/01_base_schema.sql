-- 01_base_schema.sql
-- Local replica of the pre-GTM objects that the GTM migrations (0002 to 0006b) depend on.
--
-- Reconstructed from read-only catalog introspection of the live project on
-- 2026-11-10 (table columns, constraints, indexes, policies, helper functions and the
-- triggers that are kept). It contains NO production data and is NOT a full dump.
--
-- Deliberately left out, because they are unrelated to the GTM work:
--   * the trg_on_lead trigger and the workflow engine it calls (run_workflow and the
--     workflow tables), the trg_quota triggers and enforce_quota, and trg_seed and
--     seed_workspace;
--   * every other module table (about 45 tables) and its policies;
--   * the digimithra schema from migration 0001.
--
-- Also left out are the GTM additions that migrations 0002, 0003 and 0005 create. Those
-- files are replayed on top of this base, so the replay is tested for real.

-- ---------------------------------------------------------------------------
-- Tables (pre-GTM shape)
-- ---------------------------------------------------------------------------

create table public.tenants (
  id uuid default gen_random_uuid() not null,
  name text not null,
  slug text not null,
  kind text default 'business' not null,
  created_by uuid,
  created_at timestamptz default now() not null,
  constraint tenants_pkey primary key (id),
  constraint tenants_slug_key unique (slug),
  constraint tenants_kind_check check (kind = any (array['business'::text, 'agency'::text])),
  constraint tenants_created_by_fkey foreign key (created_by) references auth.users (id) on delete set null
);

create table public.workspaces (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  name text not null,
  slug text not null,
  industry text,
  timezone text default 'Asia/Kolkata' not null,
  brand_settings jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null,
  chat_widget_key uuid default gen_random_uuid() not null,
  constraint workspaces_pkey primary key (id),
  constraint workspaces_tenant_id_id_key unique (tenant_id, id),
  constraint workspaces_tenant_id_slug_key unique (tenant_id, slug),
  constraint workspaces_tenant_id_fkey foreign key (tenant_id) references public.tenants (id) on delete cascade
);
create unique index workspaces_chat_widget_key on public.workspaces using btree (chat_widget_key);

create table public.tenant_members (
  tenant_id uuid not null,
  user_id uuid not null,
  role text not null,
  created_at timestamptz default now() not null,
  constraint tenant_members_pkey primary key (tenant_id, user_id),
  constraint tenant_members_role_check check (role = any (array['owner'::text, 'admin'::text, 'manager'::text, 'editor'::text, 'support'::text, 'analyst'::text, 'viewer'::text, 'approver'::text])),
  constraint tenant_members_tenant_id_fkey foreign key (tenant_id) references public.tenants (id) on delete cascade,
  constraint tenant_members_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade
);
create index tenant_members_user_id_idx on public.tenant_members using btree (user_id);

create table public.workspace_members (
  tenant_id uuid not null,
  workspace_id uuid not null,
  user_id uuid not null,
  role text not null,
  created_at timestamptz default now() not null,
  constraint workspace_members_pkey primary key (workspace_id, user_id),
  constraint workspace_members_role_check check (role = any (array['manager'::text, 'editor'::text, 'support'::text, 'analyst'::text, 'viewer'::text, 'approver'::text])),
  constraint workspace_members_tenant_id_user_id_fkey foreign key (tenant_id, user_id) references public.tenant_members (tenant_id, user_id) on delete cascade,
  constraint workspace_members_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade
);
create index workspace_members_user_id_idx on public.workspace_members using btree (user_id);

create table public.pipeline_stages (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  name text not null,
  "position" integer default 0 not null,
  color text default '#84cc16' not null,
  is_won boolean default false not null,
  is_lost boolean default false not null,
  constraint pipeline_stages_pkey primary key (id),
  constraint pipeline_stages_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint pipeline_stages_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade
);

create table public.campaigns (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  name text not null,
  goal text,
  status text default 'planned' not null,
  start_date date,
  end_date date,
  budget_inr integer,
  created_at timestamptz default now() not null,
  constraint campaigns_pkey primary key (id),
  constraint campaigns_status_check check (status = any (array['planned'::text, 'active'::text, 'completed'::text, 'paused'::text])),
  constraint campaigns_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade
);

create table public.contacts (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  name text not null,
  email text,
  phone text,
  handle text,
  source text,
  tags text[] default '{}'::text[] not null,
  marketing_consent boolean default false not null,
  notes text,
  created_at timestamptz default now() not null,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  constraint contacts_pkey primary key (id),
  constraint contacts_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint contacts_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade
);

create table public.landing_pages (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  slug text not null,
  title text not null,
  headline text default '' not null,
  subheadline text,
  body text,
  bullets text[] default '{}'::text[] not null,
  cta_label text default 'Send enquiry' not null,
  hero_image_url text,
  accent text default '#3b7a0c' not null,
  form_fields jsonb default '[{"name": "name", "type": "text", "label": "Full name", "required": true}, {"name": "phone", "type": "tel", "label": "Phone", "required": true}, {"name": "email", "type": "email", "label": "Email", "required": false}, {"name": "message", "type": "textarea", "label": "Message", "required": false}]'::jsonb not null,
  success_message text default 'Thank you! Our team will contact you shortly.' not null,
  consent_text text default 'I agree to be contacted about my enquiry.' not null,
  campaign_id uuid,
  status text default 'draft' not null,
  views integer default 0 not null,
  submissions integer default 0 not null,
  created_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  constraint landing_pages_pkey primary key (id),
  constraint landing_pages_slug_key unique (slug),
  constraint landing_pages_slug_check check (slug ~ '^[a-z0-9][a-z0-9-]{2,60}$'::text),
  constraint landing_pages_status_check check (status = any (array['draft'::text, 'published'::text, 'archived'::text])),
  constraint landing_pages_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade,
  constraint landing_pages_campaign_id_fkey foreign key (campaign_id) references public.campaigns (id) on delete set null,
  constraint landing_pages_created_by_fkey foreign key (created_by) references auth.users (id) on delete set null
);

create table public.leads (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  contact_id uuid,
  stage_id uuid,
  title text not null,
  value_inr integer default 0 not null,
  source text,
  event_date date,
  assigned_to uuid,
  notes text,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  landing_page_id uuid,
  campaign_id uuid,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  constraint leads_pkey primary key (id),
  constraint leads_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint leads_tenant_id_workspace_id_contact_id_fkey foreign key (tenant_id, workspace_id, contact_id) references public.contacts (tenant_id, workspace_id, id) on delete set null (contact_id),
  constraint leads_tenant_id_workspace_id_stage_id_fkey foreign key (tenant_id, workspace_id, stage_id) references public.pipeline_stages (tenant_id, workspace_id, id) on delete set null (stage_id),
  constraint leads_assigned_to_fkey foreign key (assigned_to) references auth.users (id) on delete set null,
  constraint leads_campaign_id_fkey foreign key (campaign_id) references public.campaigns (id) on delete set null,
  constraint leads_landing_page_id_fkey foreign key (landing_page_id) references public.landing_pages (id) on delete set null
);

create table public.tasks (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  title text not null,
  description text,
  due_at timestamptz,
  priority text default 'normal' not null,
  status text default 'open' not null,
  assigned_to uuid,
  lead_id uuid,
  contact_id uuid,
  created_by uuid,
  completed_at timestamptz,
  created_at timestamptz default now() not null,
  constraint tasks_pkey primary key (id),
  constraint tasks_priority_check check (priority = any (array['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])),
  constraint tasks_status_check check (status = any (array['open'::text, 'in_progress'::text, 'done'::text])),
  constraint tasks_tenant_id_workspace_id_fkey foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade,
  constraint tasks_assigned_to_fkey foreign key (assigned_to) references auth.users (id) on delete set null,
  constraint tasks_created_by_fkey foreign key (created_by) references auth.users (id) on delete set null,
  constraint tasks_contact_id_fkey foreign key (contact_id) references public.contacts (id) on delete set null,
  constraint tasks_lead_id_fkey foreign key (lead_id) references public.leads (id) on delete set null
);
create index tasks_workspace_id_status_due_at_idx on public.tasks using btree (workspace_id, status, due_at);

create table public.activities (
  id uuid default gen_random_uuid() not null,
  tenant_id uuid not null,
  workspace_id uuid not null,
  lead_id uuid,
  kind text default 'note' not null,
  body text not null,
  due_at timestamptz,
  done boolean default false not null,
  created_by uuid,
  created_at timestamptz default now() not null,
  constraint activities_pkey primary key (id),
  constraint activities_kind_check check (kind = any (array['note'::text, 'call'::text, 'email'::text, 'meeting'::text, 'task'::text, 'stage_change'::text, 'system'::text])),
  constraint activities_created_by_fkey foreign key (created_by) references auth.users (id) on delete set null,
  constraint activities_tenant_id_workspace_id_lead_id_fkey foreign key (tenant_id, workspace_id, lead_id) references public.leads (tenant_id, workspace_id, id) on delete cascade
);

create table public.audit_logs (
  id bigint generated always as identity not null,
  tenant_id uuid not null,
  workspace_id uuid,
  actor_id uuid,
  action text not null,
  entity text not null,
  entity_id text,
  meta jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null,
  constraint audit_logs_pkey primary key (id),
  constraint audit_logs_tenant_id_fkey foreign key (tenant_id) references public.tenants (id) on delete cascade
);
create index audit_logs_tenant_id_created_at_idx on public.audit_logs using btree (tenant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Helper functions (bodies copied from the live catalog)
-- ---------------------------------------------------------------------------

create or replace function app_private.ws_role(p_tenant uuid, p_workspace uuid)
returns text
language sql
stable security definer
set search_path to ''
as $function$
  select coalesce(
    (select 'admin' from public.tenant_members tm
      where tm.tenant_id = p_tenant and tm.user_id = (select auth.uid())
        and tm.role in ('owner','admin')),
    (select wm.role from public.workspace_members wm
      where wm.tenant_id = p_tenant and wm.workspace_id = p_workspace
        and wm.user_id = (select auth.uid())));
$function$;

create or replace function app_private.is_member(p_tenant uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists(select 1 from public.tenant_members tm
    where tm.tenant_id = p_tenant and tm.user_id = (select auth.uid()));
$function$;

create or replace function app_private.is_tenant_admin(p_tenant uuid)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists(select 1 from public.tenant_members tm
    where tm.tenant_id = p_tenant and tm.user_id = (select auth.uid())
      and tm.role in ('owner','admin'));
$function$;

create or replace function app_private.tenant_role(p_tenant uuid)
returns text
language sql
stable security definer
set search_path to ''
as $function$
  select tm.role from public.tenant_members tm
  where tm.tenant_id = p_tenant and tm.user_id = (select auth.uid());
$function$;

create or replace function app_private.audit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  rec jsonb := to_jsonb(coalesce(new, old));
begin
  if not exists (select 1 from public.tenants where id = (rec->>'tenant_id')::uuid) then
    return coalesce(new, old);
  end if;
  insert into public.audit_logs (tenant_id, workspace_id, actor_id, action, entity, entity_id, meta)
  values (
    (rec->>'tenant_id')::uuid,
    case when rec ? 'workspace_id' then (rec->>'workspace_id')::uuid end,
    (select auth.uid()),
    lower(tg_op), tg_table_name,
    coalesce(rec->>'id', rec->>'user_id'),
    jsonb_strip_nulls(jsonb_build_object(
      'status', rec->>'status', 'name', coalesce(rec->>'name', rec->>'title'), 'role', rec->>'role')));
  return coalesce(new, old);
end
$function$;

create or replace function app_private.set_created_by()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if (select auth.uid()) is not null then new.created_by := (select auth.uid()); end if;
  return new;
end
$function$;

create or replace function app_private.set_updated_at()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin new.updated_at := now(); return new; end
$function$;

-- Execute privileges as recorded on the live project: helpers are callable by
-- authenticated only (ws_role's live ACL is postgres and authenticated).
revoke execute on function app_private.ws_role(uuid, uuid), app_private.is_member(uuid),
  app_private.is_tenant_admin(uuid), app_private.tenant_role(uuid) from public, anon;
grant execute on function app_private.ws_role(uuid, uuid), app_private.is_member(uuid),
  app_private.is_tenant_admin(uuid), app_private.tenant_role(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers (subset kept; see header)
-- ---------------------------------------------------------------------------

create trigger trg_audit after insert or update or delete on public.leads
  for each row execute function app_private.audit();
create trigger trg_updated before update on public.leads
  for each row execute function app_private.set_updated_at();
create trigger trg_created_by before insert on public.tasks
  for each row execute function app_private.set_created_by();
create trigger trg_created_by before insert on public.activities
  for each row execute function app_private.set_created_by();
create trigger trg_created_by before insert on public.landing_pages
  for each row execute function app_private.set_created_by();
create trigger trg_updated before update on public.landing_pages
  for each row execute function app_private.set_updated_at();
create trigger trg_audit after insert or update or delete on public.tenant_members
  for each row execute function app_private.audit();
create trigger trg_audit after insert or update or delete on public.workspace_members
  for each row execute function app_private.audit();
create trigger trg_audit after insert or update or delete on public.workspaces
  for each row execute function app_private.audit();

-- ---------------------------------------------------------------------------
-- Row level security (pre-GTM policies, as on the live project)
-- ---------------------------------------------------------------------------

alter table public.tenants enable row level security;
alter table public.workspaces enable row level security;
alter table public.tenant_members enable row level security;
alter table public.workspace_members enable row level security;
alter table public.pipeline_stages enable row level security;
alter table public.campaigns enable row level security;
alter table public.contacts enable row level security;
alter table public.landing_pages enable row level security;
alter table public.leads enable row level security;
alter table public.tasks enable row level security;
alter table public.activities enable row level security;
alter table public.audit_logs enable row level security;

create policy tenants_read on public.tenants as permissive for select to authenticated using (app_private.is_member(id));
create policy tenants_update on public.tenants as permissive for update to authenticated using (app_private.is_tenant_admin(id)) with check (app_private.is_tenant_admin(id));
create policy tenants_owner_delete on public.tenants as permissive for delete to authenticated using (app_private.tenant_role(id) = 'owner'::text);

create policy tm_read on public.tenant_members as permissive for select to authenticated using (app_private.is_member(tenant_id));
create policy tm_update on public.tenant_members as permissive for update to authenticated using (((app_private.tenant_role(tenant_id) = 'owner'::text) AND (role <> 'owner'::text))) with check (((app_private.tenant_role(tenant_id) = 'owner'::text) AND (role <> 'owner'::text)));
create policy tm_delete on public.tenant_members as permissive for delete to authenticated using (((role <> 'owner'::text) AND (app_private.is_tenant_admin(tenant_id) OR (user_id = ( SELECT auth.uid() AS uid)))));

create policy wm_read on public.workspace_members as permissive for select to authenticated using (app_private.is_member(tenant_id));
create policy wm_write on public.workspace_members as permissive for all to authenticated using (app_private.is_tenant_admin(tenant_id)) with check (app_private.is_tenant_admin(tenant_id));

create policy ws_read on public.workspaces as permissive for select to authenticated using ((app_private.ws_role(tenant_id, id) IS NOT NULL));
create policy ws_insert on public.workspaces as permissive for insert to authenticated with check (app_private.is_tenant_admin(tenant_id));
create policy ws_update on public.workspaces as permissive for update to authenticated using ((app_private.ws_role(tenant_id, id) = ANY (ARRAY['admin'::text, 'manager'::text]))) with check ((app_private.ws_role(tenant_id, id) = ANY (ARRAY['admin'::text, 'manager'::text])));
create policy ws_delete on public.workspaces as permissive for delete to authenticated using (app_private.is_tenant_admin(tenant_id));

create policy pipeline_stages_read on public.pipeline_stages as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy pipeline_stages_insert on public.pipeline_stages as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[])));
create policy pipeline_stages_update on public.pipeline_stages as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[])));
create policy pipeline_stages_delete on public.pipeline_stages as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[])));

create policy campaigns_read on public.campaigns as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy campaigns_insert on public.campaigns as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
create policy campaigns_update on public.campaigns as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
create policy campaigns_delete on public.campaigns as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));

create policy contacts_read on public.contacts as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy contacts_insert on public.contacts as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy contacts_update on public.contacts as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy contacts_delete on public.contacts as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));

create policy landing_pages_read on public.landing_pages as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy landing_pages_insert on public.landing_pages as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
create policy landing_pages_update on public.landing_pages as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
create policy landing_pages_delete on public.landing_pages as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));

create policy leads_read on public.leads as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy leads_insert on public.leads as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy leads_update on public.leads as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy leads_delete on public.leads as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));

create policy tasks_read on public.tasks as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy tasks_insert on public.tasks as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy tasks_update on public.tasks as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy tasks_delete on public.tasks as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));

create policy activities_read on public.activities as permissive for select to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
create policy activities_insert on public.activities as permissive for insert to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy activities_update on public.activities as permissive for update to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
create policy activities_delete on public.activities as permissive for delete to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));

create policy audit_read on public.audit_logs as permissive for select to authenticated using (app_private.is_tenant_admin(tenant_id));
