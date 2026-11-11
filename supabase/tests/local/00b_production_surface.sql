-- 00b_production_surface.sql
-- Synthetic-only. Reproduces the production objects that the anon hardening touches, so the replica
-- is no longer a 20-table toy. Built from a READ-ONLY, schema-only introspection of production on
-- 2026-11-11: column definitions, primary keys, table grants, RLS state, policies, the notify helper,
-- and the bodies of the nine functions that anon can execute. No rows were copied.
--
-- Deliberately NOT reproduced (see reviews/0009_anon_hardening_notes.md, "Replica fidelity"):
--   * the DDL event trigger that runs rls_auto_enable() (it changes the DDL of new tables)
--   * foreign keys (they point at auth.users and at tables outside this surface)
--   * the other ~45 production tables and their policies
--   * production's other migrations (digimithra_* and 0001_foundation .. 0013_avatars_team_activity)
--
-- Run after 01_base_schema.sql and before the repo migrations. Every statement is idempotent, so the
-- replica migrations that create the same objects (0005a, 0006b) see them as already present, which
-- is the same situation production is in.

-- ----------------------------------------------------------------- tables that production has
-- Columns that the replica base may already have are added only if missing.
create table if not exists public.consent_records (
  id uuid not null default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  contact_id uuid not null,
  channel text not null,
  status text not null,
  source text,
  created_at timestamptz not null default now(),
  primary key (id));
create table if not exists public.conversations (
  id uuid not null default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  contact_id uuid,
  social_account_id uuid,
  channel text not null default 'instagram'::text,
  subject text,
  status text not null default 'open'::text,
  priority text not null default 'normal'::text,
  assigned_to uuid,
  unread_count integer not null default 0,
  last_message_at timestamptz not null default now(),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  web_session uuid,
  external_id text,
  handling text not null default 'human'::text,
  primary key (id));
create table if not exists public.email_sends (
  id uuid not null default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  campaign_id uuid not null,
  contact_id uuid,
  email text not null,
  status text not null,
  provider_id text,
  error text,
  created_at timestamptz not null default now(),
  primary key (id));
create table if not exists public.form_submissions (
  id uuid not null default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  landing_page_id uuid not null,
  data jsonb not null,
  contact_id uuid,
  lead_id uuid,
  utm jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  primary key (id));
create table if not exists public.messages (
  id uuid not null default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  conversation_id uuid not null,
  direction text not null,
  body text not null,
  sender_name text,
  is_ai_draft boolean not null default false,
  sent_by uuid,
  created_at timestamptz not null default now(),
  external_id text,
  primary key (id));

-- Columns present in production that the replica base may not have yet.
alter table public.landing_pages add column if not exists id uuid default gen_random_uuid();
alter table public.landing_pages add column if not exists tenant_id uuid;
alter table public.landing_pages add column if not exists workspace_id uuid;
alter table public.landing_pages add column if not exists slug text;
alter table public.landing_pages add column if not exists title text;
alter table public.landing_pages add column if not exists headline text default ''::text;
alter table public.landing_pages add column if not exists subheadline text;
alter table public.landing_pages add column if not exists body text;
alter table public.landing_pages add column if not exists bullets text[] default '{}'::text[];
alter table public.landing_pages add column if not exists cta_label text default 'Send enquiry'::text;
alter table public.landing_pages add column if not exists hero_image_url text;
alter table public.landing_pages add column if not exists accent text default '#3b7a0c'::text;
alter table public.landing_pages add column if not exists form_fields jsonb default '[{"name": "name", "type": "text", "label": "Full name", "required": true}, {"name": "phone", "type": "tel", "label": "Phone", "required": true}, {"name": "email", "type": "email", "label": "Email", "required": false}, {"name": "message", "type": "textarea", "label": "Message", "required": false}]'::jsonb;
alter table public.landing_pages add column if not exists success_message text default 'Thank you! Our team will contact you shortly.'::text;
alter table public.landing_pages add column if not exists consent_text text default 'I agree to be contacted about my enquiry.'::text;
alter table public.landing_pages add column if not exists campaign_id uuid;
alter table public.landing_pages add column if not exists status text default 'draft'::text;
alter table public.landing_pages add column if not exists views integer default 0;
alter table public.landing_pages add column if not exists submissions integer default 0;
alter table public.landing_pages add column if not exists created_by uuid;
alter table public.landing_pages add column if not exists created_at timestamp with time zone default now();
alter table public.landing_pages add column if not exists updated_at timestamp with time zone default now();

alter table public.workspaces add column if not exists id uuid default gen_random_uuid();
alter table public.workspaces add column if not exists tenant_id uuid;
alter table public.workspaces add column if not exists name text;
alter table public.workspaces add column if not exists slug text;
alter table public.workspaces add column if not exists industry text;
alter table public.workspaces add column if not exists timezone text default 'Asia/Kolkata'::text;
alter table public.workspaces add column if not exists brand_settings jsonb default '{}'::jsonb;
alter table public.workspaces add column if not exists created_at timestamp with time zone default now();
alter table public.workspaces add column if not exists chat_widget_key uuid default gen_random_uuid();

alter table public.contacts add column if not exists id uuid default gen_random_uuid();
alter table public.contacts add column if not exists tenant_id uuid;
alter table public.contacts add column if not exists workspace_id uuid;
alter table public.contacts add column if not exists name text;
alter table public.contacts add column if not exists email text;
alter table public.contacts add column if not exists phone text;
alter table public.contacts add column if not exists handle text;
alter table public.contacts add column if not exists source text;
alter table public.contacts add column if not exists tags text[] default '{}'::text[];
alter table public.contacts add column if not exists marketing_consent boolean default false;
alter table public.contacts add column if not exists notes text;
alter table public.contacts add column if not exists created_at timestamp with time zone default now();
alter table public.contacts add column if not exists utm_source text;
alter table public.contacts add column if not exists utm_medium text;
alter table public.contacts add column if not exists utm_campaign text;

alter table public.leads add column if not exists id uuid default gen_random_uuid();
alter table public.leads add column if not exists tenant_id uuid;
alter table public.leads add column if not exists workspace_id uuid;
alter table public.leads add column if not exists contact_id uuid;
alter table public.leads add column if not exists stage_id uuid;
alter table public.leads add column if not exists title text;
alter table public.leads add column if not exists value_inr integer default 0;
alter table public.leads add column if not exists source text;
alter table public.leads add column if not exists event_date date;
alter table public.leads add column if not exists assigned_to uuid;
alter table public.leads add column if not exists notes text;
alter table public.leads add column if not exists created_at timestamp with time zone default now();
alter table public.leads add column if not exists updated_at timestamp with time zone default now();
alter table public.leads add column if not exists landing_page_id uuid;
alter table public.leads add column if not exists campaign_id uuid;
alter table public.leads add column if not exists utm_source text;
alter table public.leads add column if not exists utm_medium text;
alter table public.leads add column if not exists utm_campaign text;

alter table public.pipeline_stages add column if not exists id uuid default gen_random_uuid();
alter table public.pipeline_stages add column if not exists tenant_id uuid;
alter table public.pipeline_stages add column if not exists workspace_id uuid;
alter table public.pipeline_stages add column if not exists name text;
alter table public.pipeline_stages add column if not exists position integer default 0;
alter table public.pipeline_stages add column if not exists color text default '#84cc16'::text;
alter table public.pipeline_stages add column if not exists is_won boolean default false;
alter table public.pipeline_stages add column if not exists is_lost boolean default false;

-- notifications: production shape (checked read-only 2026-11-11). Created here, without the 0007a foreign keys,
-- because notify_workspace is a SQL function and PostgreSQL validates its body at creation time.
create table if not exists public.notifications (id uuid default gen_random_uuid() not null, tenant_id uuid not null, user_id uuid not null, title text not null, body text, link text, read_at timestamptz, created_at timestamptz default now() not null, primary key (id));
alter table public.notifications enable row level security;
grant all on table public.notifications to anon, authenticated, service_role;

-- plans: public pricing. Production shape checked read-only 2026-11-11: PK (id), RLS on, one policy
-- plans_read (SELECT, anon and authenticated, USING true), and ALL table grants for anon, authenticated, service_role.
-- Note: RLS does not filter TRUNCATE, so the ALL grants include a TRUNCATE path that RLS cannot stop.
create table if not exists public.plans (id text not null, name text not null, price_inr integer, max_workspaces integer not null, max_accounts integer not null, max_posts_per_month integer not null, max_users integer not null, ai_credits_per_month integer not null, features text[] not null default '{}'::text[], sort_order integer not null default 0, primary key (id));
alter table public.plans enable row level security;
drop policy if exists "plans_read" on public.plans;
create policy "plans_read" on public.plans as PERMISSIVE for SELECT to anon, authenticated using (true);
grant all on table public.plans to anon, authenticated, service_role;

-- ----------------------------------------------------------------- helper: notify_workspace (owner: postgres)
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

-- ----------------------------------------------------------------- the nine anon-callable functions (production bodies)
CREATE OR REPLACE FUNCTION public.get_landing_page(p_slug text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'slug', lp.slug, 'title', lp.title, 'headline', lp.headline, 'subheadline', lp.subheadline,
    'body', lp.body, 'bullets', lp.bullets, 'cta_label', lp.cta_label, 'hero_image_url', lp.hero_image_url,
    'accent', lp.accent, 'form_fields', lp.form_fields, 'success_message', lp.success_message,
    'consent_text', lp.consent_text, 'business', w.name)
  from public.landing_pages lp join public.workspaces w on w.id = lp.workspace_id
  where lp.slug = lower(p_slug) and lp.status = 'published';
$function$;

CREATE OR REPLACE FUNCTION public.record_landing_view(p_slug text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update public.landing_pages set views = views + 1 where slug = lower(p_slug) and status = 'published';
$function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.send_web_chat(p_session uuid, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.conversations;
begin
  select * into c from public.conversations where web_session = p_session;
  if not found then raise exception 'Chat session expired'; end if;
  if coalesce(trim(p_message), '') = '' or length(p_message) > 2000 then raise exception 'Please enter a message'; end if;
  if (select count(*) from public.messages where conversation_id = c.id and direction = 'inbound' and created_at > now() - interval '10 minutes') >= 20 then
    raise exception 'Too many messages, please wait a moment';
  end if;
  insert into public.messages (tenant_id, workspace_id, conversation_id, direction, body, sender_name)
  values (c.tenant_id, c.workspace_id, c.id, 'inbound', left(p_message, 2000), 'Visitor');
end $function$;

CREATE OR REPLACE FUNCTION public.start_web_chat(p_key uuid, p_name text, p_email text, p_message text, p_consent boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare w public.workspaces; v_contact uuid; v_conv uuid; v_session uuid := gen_random_uuid(); v_email text := lower(nullif(trim(p_email), ''));
begin
  select * into w from public.workspaces where chat_widget_key = p_key;
  if not found then raise exception 'Chat is not available'; end if;
  if coalesce(trim(p_message), '') = '' or length(p_message) > 2000 then raise exception 'Please enter a message'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid email'; end if;
  if (select count(*) from public.conversations where workspace_id = w.id and channel = 'website' and created_at > now() - interval '10 minutes') >= 60 then
    raise exception 'Chat is busy, please try again shortly';
  end if;
  insert into public.contacts (tenant_id, workspace_id, name, email, source, marketing_consent)
  values (w.tenant_id, w.id, left(coalesce(nullif(trim(p_name), ''), 'Website visitor'), 120), v_email, 'website', coalesce(p_consent, false))
  returning id into v_contact;
  if coalesce(p_consent, false) then
    insert into public.consent_records (tenant_id, workspace_id, contact_id, channel, status, source)
    values (w.tenant_id, w.id, v_contact, 'email', 'opt_in', 'website_chat');
  end if;
  insert into public.conversations (tenant_id, workspace_id, contact_id, channel, subject, web_session)
  values (w.tenant_id, w.id, v_contact, 'website', left(p_message, 60), v_session) returning id into v_conv;
  insert into public.messages (tenant_id, workspace_id, conversation_id, direction, body, sender_name)
  values (w.tenant_id, w.id, v_conv, 'inbound', left(p_message, 2000), left(coalesce(nullif(trim(p_name), ''), 'Visitor'), 120));
  return v_session;
end $function$;

CREATE OR REPLACE FUNCTION public.submit_landing_form(p_slug text, p_data jsonb, p_utm jsonb DEFAULT '{}'::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  lp public.landing_pages;
  v_name text; v_email text; v_phone text; v_msg text;
  v_contact uuid; v_lead uuid; v_stage uuid;
  f jsonb;
begin
  select * into lp from public.landing_pages where slug = lower(p_slug) and status = 'published';
  if not found then raise exception 'This page is not available'; end if;
  if p_data is null or jsonb_typeof(p_data) <> 'object' or length(p_data::text) > 8000 then
    raise exception 'Invalid form data';
  end if;
  for f in select * from jsonb_array_elements(lp.form_fields) loop
    if coalesce((f->>'required')::boolean, false) and coalesce(trim(p_data->>(f->>'name')), '') = '' then
      raise exception '% is required', f->>'label';
    end if;
  end loop;
  if not coalesce((p_data->>'consent')::boolean, false) then raise exception 'Please accept the consent checkbox'; end if;
  if (select count(*) from public.form_submissions where landing_page_id = lp.id and created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'Too many submissions, please try again later';
  end if;

  v_name := left(coalesce(nullif(trim(p_data->>'name'), ''), 'Website visitor'), 120);
  v_email := lower(nullif(trim(p_data->>'email'), ''));
  v_phone := left(nullif(regexp_replace(coalesce(p_data->>'phone', ''), '[^0-9+]', '', 'g'), ''), 20);
  v_msg := left(nullif(trim(p_data->>'message'), ''), 2000);
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter a valid email'; end if;

  select id into v_contact from public.contacts
   where workspace_id = lp.workspace_id and ((v_email is not null and lower(email) = v_email) or (v_phone is not null and phone = v_phone))
   limit 1;
  if v_contact is null then
    insert into public.contacts (tenant_id, workspace_id, name, email, phone, source, marketing_consent, utm_source, utm_medium, utm_campaign, notes)
    values (lp.tenant_id, lp.workspace_id, v_name, v_email, v_phone, 'landing_page', true,
            left(p_utm->>'utm_source', 100), left(p_utm->>'utm_medium', 100), left(p_utm->>'utm_campaign', 100), v_msg)
    returning id into v_contact;
  else
    update public.contacts set marketing_consent = true where id = v_contact;
  end if;
  insert into public.consent_records (tenant_id, workspace_id, contact_id, channel, status, source)
  values (lp.tenant_id, lp.workspace_id, v_contact, 'email', 'opt_in', 'landing_page:' || lp.slug);

  select id into v_stage from public.pipeline_stages where workspace_id = lp.workspace_id order by position limit 1;
  insert into public.leads (tenant_id, workspace_id, contact_id, stage_id, title, source, notes, landing_page_id, campaign_id, utm_source, utm_medium, utm_campaign)
  values (lp.tenant_id, lp.workspace_id, v_contact, v_stage, left(lp.title || ': ' || v_name, 200), 'landing_page', v_msg, lp.id, lp.campaign_id,
          left(p_utm->>'utm_source', 100), left(p_utm->>'utm_medium', 100), left(p_utm->>'utm_campaign', 100))
  returning id into v_lead;

  insert into public.form_submissions (tenant_id, workspace_id, landing_page_id, data, contact_id, lead_id, utm)
  values (lp.tenant_id, lp.workspace_id, lp.id, p_data, v_contact, v_lead, coalesce(p_utm, '{}'::jsonb));
  update public.landing_pages set submissions = submissions + 1 where id = lp.id;
  perform app_private.notify_workspace(lp.tenant_id, lp.workspace_id, 'New form submission: ' || v_name,
    lp.title, '/app/crm', array['admin','manager','editor','support']);
  return lp.success_message;
end $function$;

CREATE OR REPLACE FUNCTION public.unsubscribe_email(p_token uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare s public.email_sends;
begin
  select * into s from public.email_sends where id = p_token;
  if not found then raise exception 'Link is invalid or expired'; end if;
  if s.contact_id is not null then
    update public.contacts set marketing_consent = false where id = s.contact_id;
    insert into public.consent_records (tenant_id, workspace_id, contact_id, channel, status, source)
    values (s.tenant_id, s.workspace_id, s.contact_id, 'email', 'opt_out', 'unsubscribe_link');
  end if;
  return (select name from public.workspaces where id = s.workspace_id);
end $function$;

CREATE OR REPLACE FUNCTION public.web_chat_config(p_key uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('business', w.name, 'greeting', coalesce(w.brand_settings->>'chat_greeting', 'Hi! How can we help you today?'))
  from public.workspaces w where w.chat_widget_key = p_key;
$function$;

CREATE OR REPLACE FUNCTION public.web_chat_messages(p_session uuid)
 RETURNS TABLE(direction text, body text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select m.direction, m.body, m.created_at from public.messages m
  join public.conversations c on c.id = m.conversation_id
  where c.web_session = p_session and m.direction in ('inbound','outbound') and not m.is_ai_draft
  order by m.created_at limit 200;
$function$;

-- ----------------------------------------------------------------- table grants (production, schema-only)
-- These are production's current grants (read-only catalog check, 2026-11-11): anon, authenticated and
-- service_role hold ALL on each table, including PG17 MAINTAIN. RLS, not grants, is what limits anon.
grant all on table public.consent_records to anon, authenticated, service_role;
grant all on table public.contacts to anon, authenticated, service_role;
grant all on table public.conversations to anon, authenticated, service_role;
grant all on table public.email_sends to anon, authenticated, service_role;
grant all on table public.form_submissions to anon, authenticated, service_role;
grant all on table public.landing_pages to anon, authenticated, service_role;
grant all on table public.leads to anon, authenticated, service_role;
grant all on table public.messages to anon, authenticated, service_role;
grant all on table public.pipeline_stages to anon, authenticated, service_role;
grant all on table public.workspaces to anon, authenticated, service_role;

-- ----------------------------------------------------------------- function ACLs (production, read-only check)
-- notify_workspace: owner-only in production (no PUBLIC, no anon). Revoke the default PUBLIC execute.
revoke all on function app_private.notify_workspace(uuid, uuid, text, text, text, text[]) from public;
-- The eight anon-facing RPCs: production ACL is postgres, anon, authenticated, service_role (no PUBLIC).
revoke all on function public.get_landing_page(text) from public;
revoke all on function public.record_landing_view(text) from public;
revoke all on function public.submit_landing_form(text, jsonb, jsonb) from public;
revoke all on function public.start_web_chat(uuid, text, text, text, boolean) from public;
revoke all on function public.send_web_chat(uuid, text) from public;
revoke all on function public.web_chat_config(uuid) from public;
revoke all on function public.web_chat_messages(uuid) from public;
revoke all on function public.unsubscribe_email(uuid) from public;
grant execute on function public.get_landing_page(text) to anon, authenticated, service_role;
grant execute on function public.record_landing_view(text) to anon, authenticated, service_role;
grant execute on function public.submit_landing_form(text, jsonb, jsonb) to anon, authenticated, service_role;
grant execute on function public.start_web_chat(uuid, text, text, text, boolean) to anon, authenticated, service_role;
grant execute on function public.send_web_chat(uuid, text) to anon, authenticated, service_role;
grant execute on function public.web_chat_config(uuid) to anon, authenticated, service_role;
grant execute on function public.web_chat_messages(uuid) to anon, authenticated, service_role;
grant execute on function public.unsubscribe_email(uuid) to anon, authenticated, service_role;
-- rls_auto_enable: production ACL is PUBLIC, postgres, authenticated, service_role. It is left at the
-- default (PUBLIC), which is how anon inherits EXECUTE in production. Task 2 revokes it.
revoke execute on function public.rls_auto_enable() from anon;
grant execute on function public.rls_auto_enable() to authenticated, service_role;

-- ----------------------------------------------------------------- RLS (production state)
alter table public.consent_records enable row level security;
alter table public.contacts enable row level security;
alter table public.conversations enable row level security;
alter table public.email_sends enable row level security;
alter table public.form_submissions enable row level security;
alter table public.landing_pages enable row level security;
alter table public.leads enable row level security;
alter table public.messages enable row level security;
alter table public.pipeline_stages enable row level security;
alter table public.workspaces enable row level security;

-- ----------------------------------------------------------------- policies (production, schema-only)
-- Every policy here is for authenticated. No policy in this surface targets anon or PUBLIC.
drop policy if exists "consent_records_insert" on public.consent_records;
create policy "consent_records_insert" on public.consent_records as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "consent_records_read" on public.consent_records;
create policy "consent_records_read" on public.consent_records as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "consent_records_update" on public.consent_records;
create policy "consent_records_update" on public.consent_records as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "consent_records_delete" on public.consent_records;
create policy "consent_records_delete" on public.consent_records as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "contacts_insert" on public.contacts;
create policy "contacts_insert" on public.contacts as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "contacts_read" on public.contacts;
create policy "contacts_read" on public.contacts as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "contacts_update" on public.contacts;
create policy "contacts_update" on public.contacts as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "contacts_delete" on public.contacts;
create policy "contacts_delete" on public.contacts as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "conversations_insert" on public.conversations;
create policy "conversations_insert" on public.conversations as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "conversations_read" on public.conversations;
create policy "conversations_read" on public.conversations as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "conversations_update" on public.conversations;
create policy "conversations_update" on public.conversations as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "conversations_delete" on public.conversations;
create policy "conversations_delete" on public.conversations as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "email_sends_insert" on public.email_sends;
create policy "email_sends_insert" on public.email_sends as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'editor'::text])));
drop policy if exists "email_sends_read" on public.email_sends;
create policy "email_sends_read" on public.email_sends as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "email_sends_update" on public.email_sends;
create policy "email_sends_update" on public.email_sends as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'editor'::text]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY (ARRAY['admin'::text, 'manager'::text, 'editor'::text])));
drop policy if exists "form_submissions_read" on public.form_submissions;
create policy "form_submissions_read" on public.form_submissions as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "landing_pages_delete" on public.landing_pages;
create policy "landing_pages_delete" on public.landing_pages as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
drop policy if exists "landing_pages_insert" on public.landing_pages;
create policy "landing_pages_insert" on public.landing_pages as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
drop policy if exists "landing_pages_read" on public.landing_pages;
create policy "landing_pages_read" on public.landing_pages as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "landing_pages_update" on public.landing_pages;
create policy "landing_pages_update" on public.landing_pages as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor}'::text[])));
drop policy if exists "leads_update" on public.leads;
create policy "leads_update" on public.leads as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "leads_delete" on public.leads;
create policy "leads_delete" on public.leads as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "leads_read" on public.leads;
create policy "leads_read" on public.leads as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "leads_insert" on public.leads;
create policy "leads_insert" on public.leads as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "messages_insert" on public.messages;
create policy "messages_insert" on public.messages as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "messages_read" on public.messages;
create policy "messages_read" on public.messages as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "messages_update" on public.messages;
create policy "messages_update" on public.messages as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "messages_delete" on public.messages;
create policy "messages_delete" on public.messages as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager,editor,support}'::text[])));
drop policy if exists "pipeline_stages_read" on public.pipeline_stages;
create policy "pipeline_stages_read" on public.pipeline_stages as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, workspace_id) IS NOT NULL));
drop policy if exists "pipeline_stages_delete" on public.pipeline_stages;
create policy "pipeline_stages_delete" on public.pipeline_stages as PERMISSIVE for DELETE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[])));
drop policy if exists "pipeline_stages_insert" on public.pipeline_stages;
create policy "pipeline_stages_insert" on public.pipeline_stages as PERMISSIVE for INSERT to authenticated with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[])));
drop policy if exists "pipeline_stages_update" on public.pipeline_stages;
create policy "pipeline_stages_update" on public.pipeline_stages as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[]))) with check ((app_private.ws_role(tenant_id, workspace_id) = ANY ('{admin,manager}'::text[])));
drop policy if exists "ws_insert" on public.workspaces;
create policy "ws_insert" on public.workspaces as PERMISSIVE for INSERT to authenticated with check (app_private.is_tenant_admin(tenant_id));
drop policy if exists "ws_delete" on public.workspaces;
create policy "ws_delete" on public.workspaces as PERMISSIVE for DELETE to authenticated using (app_private.is_tenant_admin(tenant_id));
drop policy if exists "ws_read" on public.workspaces;
create policy "ws_read" on public.workspaces as PERMISSIVE for SELECT to authenticated using ((app_private.ws_role(tenant_id, id) IS NOT NULL));
drop policy if exists "ws_update" on public.workspaces;
create policy "ws_update" on public.workspaces as PERMISSIVE for UPDATE to authenticated using ((app_private.ws_role(tenant_id, id) = ANY (ARRAY['admin'::text, 'manager'::text]))) with check ((app_private.ws_role(tenant_id, id) = ANY (ARRAY['admin'::text, 'manager'::text])));

-- Event trigger, production name and tags (checked read-only 2026-11-11): ensure_rls, ddl_command_end,
-- CREATE TABLE / CREATE TABLE AS / SELECT INTO, enabled, running rls_auto_enable. The Supabase-managed
-- pgrst_* and issue_* triggers are not reproduced; they do not touch table privileges.
create event trigger ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();
