-- 0003_gtm_scoped_crm_foreign_keys.sql
-- Additive. Tenant- and workspace-scoped foreign keys for existing CRM links.
-- Added NOT VALID, then validated. The single-column foreign keys stay in place.
-- Audit before apply: zero rows violate any of these constraints.

alter table public.tasks
  add constraint tasks_scope_lead_fkey
    foreign key (tenant_id, workspace_id, lead_id)
    references public.leads (tenant_id, workspace_id, id)
    on delete set null (lead_id) not valid,
  add constraint tasks_scope_contact_fkey
    foreign key (tenant_id, workspace_id, contact_id)
    references public.contacts (tenant_id, workspace_id, id)
    on delete set null (contact_id) not valid;

alter table public.landing_pages
  add constraint landing_pages_scope_campaign_fkey
    foreign key (tenant_id, workspace_id, campaign_id)
    references public.campaigns (tenant_id, workspace_id, id)
    on delete set null (campaign_id) not valid;

alter table public.leads
  add constraint leads_scope_campaign_fkey
    foreign key (tenant_id, workspace_id, campaign_id)
    references public.campaigns (tenant_id, workspace_id, id)
    on delete set null (campaign_id) not valid,
  add constraint leads_scope_landing_page_fkey
    foreign key (tenant_id, workspace_id, landing_page_id)
    references public.landing_pages (tenant_id, workspace_id, id)
    on delete set null (landing_page_id) not valid;

alter table public.tasks validate constraint tasks_scope_lead_fkey;
alter table public.tasks validate constraint tasks_scope_contact_fkey;
alter table public.landing_pages validate constraint landing_pages_scope_campaign_fkey;
alter table public.leads validate constraint leads_scope_campaign_fkey;
alter table public.leads validate constraint leads_scope_landing_page_fkey;

-- Indexes on the referencing side (partial, so they stay small).
create index tasks_scope_lead_idx
  on public.tasks (tenant_id, workspace_id, lead_id) where lead_id is not null;
create index tasks_scope_contact_idx
  on public.tasks (tenant_id, workspace_id, contact_id) where contact_id is not null;
create index leads_scope_campaign_idx
  on public.leads (tenant_id, workspace_id, campaign_id) where campaign_id is not null;
create index leads_scope_landing_page_idx
  on public.leads (tenant_id, workspace_id, landing_page_id) where landing_page_id is not null;
create index landing_pages_scope_campaign_idx
  on public.landing_pages (tenant_id, workspace_id, campaign_id) where campaign_id is not null;
