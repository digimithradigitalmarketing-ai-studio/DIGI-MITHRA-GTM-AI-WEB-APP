-- Rollback for 0002. Run only after the 0003 rollback. Manual only, never automatic.
alter table public.landing_pages drop constraint if exists landing_pages_tenant_id_workspace_id_id_key;
alter table public.campaigns drop constraint if exists campaigns_tenant_id_workspace_id_id_key;
