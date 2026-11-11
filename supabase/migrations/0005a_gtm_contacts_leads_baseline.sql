-- 0005a_gtm_contacts_leads_baseline.sql
--
-- Schema BASELINE for public.contacts and public.leads.
--
-- Source of truth: the production definitions read from project siyxkombexmowlggxlrb
-- (read-only inspection, no production changes). This file records what production
-- already has so a fresh database (local replica, staging) can be built to the same shape.
--
-- Properties:
--   * Non-destructive. Every object uses IF NOT EXISTS, or a guard that checks pg_catalog first.
--   * Does NOT overwrite production functions, policies or triggers. Existing objects are left alone.
--   * Does NOT create trg_on_lead. That trigger and app_private.on_lead / app_private.run_workflow
--     are owned by 0007a_gtm_workflow_baseline.sql, which matches production byte-for-byte
--     after whitespace normalisation (verified by md5 of the function bodies).
--   * Does NOT add triggers to contacts. Production contacts has no triggers, so none are created here.
--   * Does NOT grant anon any privileges. Production grants anon full table privileges on both tables.
--     That is a known over-grant. It is handled by the anon-hardening review, not by this baseline.
--
-- Dependency order: this file runs AFTER 0005_gtm_company_links.sql (it needs public.companies)
-- and needs the pre-GTM tables and helpers listed in the precondition check below.
--
-- Incompatibility reporting: if a table already exists with a different shape, the section at the
-- end emits a WARNING per mismatch (missing column, different type, different nullability) and does
-- not alter anything. Resolve drift by hand. Do not force it from here.

-- ---------------------------------------------------------------------------
-- 0. Preconditions. Fail early with a clear message instead of a half-built schema.
-- ---------------------------------------------------------------------------
do $precheck$
declare
  missing text := '';
begin
  if to_regclass('public.tenants') is null           then missing := missing || ' public.tenants'; end if;
  if to_regclass('public.workspaces') is null        then missing := missing || ' public.workspaces'; end if;
  if to_regclass('public.pipeline_stages') is null   then missing := missing || ' public.pipeline_stages'; end if;
  if to_regclass('public.campaigns') is null         then missing := missing || ' public.campaigns'; end if;
  if to_regclass('public.landing_pages') is null     then missing := missing || ' public.landing_pages'; end if;
  if to_regclass('public.companies') is null         then missing := missing || ' public.companies'; end if;
  if to_regclass('auth.users') is null               then missing := missing || ' auth.users'; end if;
  if to_regprocedure('app_private.ws_role(uuid,uuid)') is null then missing := missing || ' app_private.ws_role(uuid,uuid)'; end if;
  if to_regprocedure('app_private.audit()') is null            then missing := missing || ' app_private.audit()'; end if;
  if to_regprocedure('app_private.set_updated_at()') is null   then missing := missing || ' app_private.set_updated_at()'; end if;
  if missing <> '' then
    raise exception '0005a precondition failed, missing:%', missing;
  end if;
end
$precheck$;

-- ---------------------------------------------------------------------------
-- 1. public.contacts
-- ---------------------------------------------------------------------------
create table if not exists public.contacts (
  id                uuid        not null default gen_random_uuid(),
  tenant_id         uuid        not null,
  workspace_id      uuid        not null,
  name              text        not null,
  email             text,
  phone             text,
  handle            text,
  source            text,
  tags              text[]      not null default '{}'::text[],
  marketing_consent boolean     not null default false,
  notes             text,
  created_at        timestamptz not null default now(),
  utm_source        text,
  utm_medium        text,
  utm_campaign      text,
  company_id        uuid,
  constraint contacts_pkey primary key (id),
  constraint contacts_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint contacts_tenant_id_workspace_id_fkey
    foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade,
  constraint contacts_scope_company_fkey
    foreign key (tenant_id, workspace_id, company_id)
    references public.companies (tenant_id, workspace_id, id) on delete set null (company_id)
);

create index if not exists contacts_scope_company_idx
  on public.contacts (tenant_id, workspace_id, company_id)
  where company_id is not null;

alter table public.contacts enable row level security;

do $contacts_policies$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'contacts' and policyname = 'contacts_read') then
    create policy contacts_read on public.contacts for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'contacts' and policyname = 'contacts_insert') then
    create policy contacts_insert on public.contacts for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'contacts' and policyname = 'contacts_update') then
    create policy contacts_update on public.contacts for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]))
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'contacts' and policyname = 'contacts_delete') then
    create policy contacts_delete on public.contacts for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]));
  end if;
end
$contacts_policies$;

-- Privileges: authenticated gets the CRUD the policies gate. service_role keeps its usual access.
-- anon is intentionally NOT granted here (see header).
grant select, insert, update, delete on public.contacts to authenticated;

-- ---------------------------------------------------------------------------
-- 2. public.leads
-- ---------------------------------------------------------------------------
create table if not exists public.leads (
  id              uuid        not null default gen_random_uuid(),
  tenant_id       uuid        not null,
  workspace_id    uuid        not null,
  contact_id      uuid,
  stage_id        uuid,
  title           text        not null,
  value_inr       integer     not null default 0,
  source          text,
  event_date      date,
  assigned_to     uuid,
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  landing_page_id uuid,
  campaign_id     uuid,
  utm_source      text,
  utm_medium      text,
  utm_campaign    text,
  company_id      uuid,
  constraint leads_pkey primary key (id),
  constraint leads_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint leads_tenant_id_workspace_id_contact_id_fkey
    foreign key (tenant_id, workspace_id, contact_id)
    references public.contacts (tenant_id, workspace_id, id) on delete set null (contact_id),
  constraint leads_tenant_id_workspace_id_stage_id_fkey
    foreign key (tenant_id, workspace_id, stage_id)
    references public.pipeline_stages (tenant_id, workspace_id, id) on delete set null (stage_id),
  constraint leads_assigned_to_fkey
    foreign key (assigned_to) references auth.users (id) on delete set null,
  constraint leads_campaign_id_fkey
    foreign key (campaign_id) references public.campaigns (id) on delete set null,
  constraint leads_landing_page_id_fkey
    foreign key (landing_page_id) references public.landing_pages (id) on delete set null,
  constraint leads_scope_campaign_fkey
    foreign key (tenant_id, workspace_id, campaign_id)
    references public.campaigns (tenant_id, workspace_id, id) on delete set null (campaign_id),
  constraint leads_scope_landing_page_fkey
    foreign key (tenant_id, workspace_id, landing_page_id)
    references public.landing_pages (tenant_id, workspace_id, id) on delete set null (landing_page_id),
  constraint leads_scope_company_fkey
    foreign key (tenant_id, workspace_id, company_id)
    references public.companies (tenant_id, workspace_id, id) on delete set null (company_id)
);

create index if not exists leads_scope_campaign_idx
  on public.leads (tenant_id, workspace_id, campaign_id) where campaign_id is not null;
create index if not exists leads_scope_company_idx
  on public.leads (tenant_id, workspace_id, company_id) where company_id is not null;
create index if not exists leads_scope_landing_page_idx
  on public.leads (tenant_id, workspace_id, landing_page_id) where landing_page_id is not null;

alter table public.leads enable row level security;

do $leads_policies$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'leads' and policyname = 'leads_read') then
    create policy leads_read on public.leads for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'leads' and policyname = 'leads_insert') then
    create policy leads_insert on public.leads for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'leads' and policyname = 'leads_update') then
    create policy leads_update on public.leads for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]))
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'leads' and policyname = 'leads_delete') then
    create policy leads_delete on public.leads for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor,support}'::text[]));
  end if;
end
$leads_policies$;

-- Triggers that production leads has, created only if missing.
-- trg_on_lead is NOT created here. It is owned by 0007a (see header).
do $leads_triggers$
begin
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                 where c.relname = 'leads' and t.tgname = 'trg_updated' and not t.tgisinternal) then
    create trigger trg_updated before update on public.leads
      for each row execute function app_private.set_updated_at();
  end if;
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                 where c.relname = 'leads' and t.tgname = 'trg_audit' and not t.tgisinternal) then
    create trigger trg_audit after insert or update or delete on public.leads
      for each row execute function app_private.audit();
  end if;
end
$leads_triggers$;

-- Privileges: same as contacts. anon intentionally not granted here.
grant select, insert, update, delete on public.leads to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Drift report. Reads only, changes nothing.
--    Emits a WARNING for each mismatch between this baseline and what is already in the database.
--    A clean run on an empty database emits no warnings.
-- ---------------------------------------------------------------------------
do $drift_report$
declare
  r record;
  expected record;
begin
  for expected in
    select * from (values
      ('contacts','id','uuid',false), ('contacts','tenant_id','uuid',false), ('contacts','workspace_id','uuid',false),
      ('contacts','name','text',false), ('contacts','email','text',true), ('contacts','phone','text',true),
      ('contacts','handle','text',true), ('contacts','source','text',true),
      ('contacts','tags','ARRAY',false), ('contacts','marketing_consent','boolean',false),
      ('contacts','notes','text',true), ('contacts','created_at','timestamp with time zone',false),
      ('contacts','utm_source','text',true), ('contacts','utm_medium','text',true),
      ('contacts','utm_campaign','text',true), ('contacts','company_id','uuid',true),
      ('leads','id','uuid',false), ('leads','tenant_id','uuid',false), ('leads','workspace_id','uuid',false),
      ('leads','contact_id','uuid',true), ('leads','stage_id','uuid',true), ('leads','title','text',false),
      ('leads','value_inr','integer',false), ('leads','source','text',true), ('leads','event_date','date',true),
      ('leads','assigned_to','uuid',true), ('leads','notes','text',true),
      ('leads','created_at','timestamp with time zone',false), ('leads','updated_at','timestamp with time zone',false),
      ('leads','landing_page_id','uuid',true), ('leads','campaign_id','uuid',true),
      ('leads','utm_source','text',true), ('leads','utm_medium','text',true), ('leads','utm_campaign','text',true),
      ('leads','company_id','uuid',true)
    ) as v(tbl, col, typ, nullable)
  loop
    select c.data_type, c.is_nullable into r
      from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = expected.tbl and c.column_name = expected.col;
    if not found then
      raise warning 'DRIFT: %.% is missing (baseline expects %)', expected.tbl, expected.col, expected.typ;
    elsif r.data_type <> expected.typ or (r.is_nullable = 'YES') <> expected.nullable then
      raise warning 'DRIFT: %.% is % nullable=% (baseline: % nullable=%)',
        expected.tbl, expected.col, r.data_type, r.is_nullable, expected.typ,
        case when expected.nullable then 'YES' else 'NO' end;
    end if;
  end loop;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='leads' and policyname='leads_update') then
    raise warning 'DRIFT: leads_update policy absent after baseline run';
  end if;
end
$drift_report$;
