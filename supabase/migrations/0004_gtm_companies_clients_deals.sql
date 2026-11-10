-- 0004_gtm_companies_clients_deals.sql
-- Additive. Creates three workspace-scoped tables. No existing table is altered.
-- Soft delete: archived_at / archived_by. Archiving is guarded by the trigger
-- in 0006. Hard delete is admin-only, and is refused while history depends on the row.

-- CRM prospect and customer companies
create table public.companies (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  name text not null check (length(btrim(name)) between 1 and 200),
  domain text check (domain is null or length(domain) <= 253),
  industry text,
  city text,
  lifecycle text not null default 'prospect'
    check (lifecycle in ('prospect', 'customer', 'former')),
  notes text,
  archived_at timestamptz,
  archived_by uuid references auth.users (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint companies_tenant_id_workspace_id_fkey
    foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade,
  constraint companies_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id)
);

create unique index companies_workspace_domain_key
  on public.companies (tenant_id, workspace_id, lower(domain)) where domain is not null;
create index companies_scope_name_idx
  on public.companies (tenant_id, workspace_id, lower(name));
create index companies_scope_active_idx
  on public.companies (tenant_id, workspace_id) where archived_at is null;

-- DigiMithra's agency customers. Each client is backed by exactly one company.
create table public.clients (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  company_id uuid not null,
  primary_contact_id uuid,
  status text not null default 'onboarding'
    check (status in ('onboarding', 'active', 'paused', 'churned')),
  services text,
  retainer_inr integer check (retainer_inr is null or retainer_inr >= 0),
  started_on date,
  ended_on date,
  account_owner_id uuid references auth.users (id) on delete set null,
  notes text,
  archived_at timestamptz,
  archived_by uuid references auth.users (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clients_tenant_id_workspace_id_fkey
    foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade,
  constraint clients_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint clients_scope_company_fkey
    foreign key (tenant_id, workspace_id, company_id)
    references public.companies (tenant_id, workspace_id, id) on delete restrict,
  constraint clients_scope_contact_fkey
    foreign key (tenant_id, workspace_id, primary_contact_id)
    references public.contacts (tenant_id, workspace_id, id) on delete set null (primary_contact_id),
  constraint clients_dates_check
    check (ended_on is null or started_on is null or ended_on >= started_on)
);

create unique index clients_one_per_company_key
  on public.clients (tenant_id, workspace_id, company_id);
create index clients_scope_active_idx
  on public.clients (tenant_id, workspace_id, status) where archived_at is null;

-- Priced opportunities. Several deals can belong to one lead.
-- Stages are the existing pipeline_stages rows for the workspace.
create table public.deals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  workspace_id uuid not null,
  title text not null check (length(btrim(title)) between 1 and 200),
  stage_id uuid not null,
  status text not null default 'open' check (status in ('open', 'won', 'lost')),
  value_inr integer not null default 0 check (value_inr >= 0),
  company_id uuid,
  contact_id uuid,
  lead_id uuid,
  owner_id uuid references auth.users (id) on delete set null,
  expected_close_on date,
  closed_at timestamptz,
  lost_reason text,
  archived_at timestamptz,
  archived_by uuid references auth.users (id) on delete set null,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deals_tenant_id_workspace_id_fkey
    foreign key (tenant_id, workspace_id) references public.workspaces (tenant_id, id) on delete cascade,
  constraint deals_tenant_id_workspace_id_id_key unique (tenant_id, workspace_id, id),
  constraint deals_scope_stage_fkey
    foreign key (tenant_id, workspace_id, stage_id)
    references public.pipeline_stages (tenant_id, workspace_id, id) on delete restrict,
  constraint deals_scope_company_fkey
    foreign key (tenant_id, workspace_id, company_id)
    references public.companies (tenant_id, workspace_id, id) on delete restrict,
  constraint deals_scope_contact_fkey
    foreign key (tenant_id, workspace_id, contact_id)
    references public.contacts (tenant_id, workspace_id, id) on delete set null (contact_id),
  constraint deals_scope_lead_fkey
    foreign key (tenant_id, workspace_id, lead_id)
    references public.leads (tenant_id, workspace_id, id) on delete set null (lead_id),
  constraint deals_closed_at_check check ((status = 'open') = (closed_at is null))
);

create index deals_scope_stage_idx on public.deals (tenant_id, workspace_id, stage_id);
create index deals_scope_active_idx
  on public.deals (tenant_id, workspace_id, stage_id) where archived_at is null;
create index deals_scope_status_close_idx
  on public.deals (tenant_id, workspace_id, status, expected_close_on);
create index deals_scope_company_idx
  on public.deals (tenant_id, workspace_id, company_id) where company_id is not null;
create index deals_scope_contact_idx
  on public.deals (tenant_id, workspace_id, contact_id) where contact_id is not null;
create index deals_scope_lead_idx
  on public.deals (tenant_id, workspace_id, lead_id) where lead_id is not null;
create index deals_owner_idx on public.deals (owner_id) where owner_id is not null;
