-- 0002_gtm_scope_keys.sql
-- Additive. Composite unique keys so child rows can reference campaigns and
-- landing pages inside the same tenant and workspace. Existing primary keys
-- and single-column foreign keys are unchanged.

alter table public.campaigns
  add constraint campaigns_tenant_id_workspace_id_id_key
  unique (tenant_id, workspace_id, id);

alter table public.landing_pages
  add constraint landing_pages_tenant_id_workspace_id_id_key
  unique (tenant_id, workspace_id, id);
