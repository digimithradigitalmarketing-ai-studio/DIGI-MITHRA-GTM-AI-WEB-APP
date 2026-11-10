-- 0005_gtm_company_links.sql
-- Additive. Nullable company link on existing contacts and leads.
-- Deleting a company clears the link on contacts and leads. It does not delete them.

alter table public.contacts add column company_id uuid;
alter table public.leads add column company_id uuid;

alter table public.contacts
  add constraint contacts_scope_company_fkey
    foreign key (tenant_id, workspace_id, company_id)
    references public.companies (tenant_id, workspace_id, id)
    on delete set null (company_id) not valid;

alter table public.leads
  add constraint leads_scope_company_fkey
    foreign key (tenant_id, workspace_id, company_id)
    references public.companies (tenant_id, workspace_id, id)
    on delete set null (company_id) not valid;

alter table public.contacts validate constraint contacts_scope_company_fkey;
alter table public.leads validate constraint leads_scope_company_fkey;

create index contacts_scope_company_idx
  on public.contacts (tenant_id, workspace_id, company_id) where company_id is not null;
create index leads_scope_company_idx
  on public.leads (tenant_id, workspace_id, company_id) where company_id is not null;
