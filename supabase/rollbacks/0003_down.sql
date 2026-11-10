-- Rollback for 0003. Run only after the 0005 and 0004 rollbacks. Manual only, never automatic.
drop index if exists public.landing_pages_scope_campaign_idx;
drop index if exists public.leads_scope_landing_page_idx;
drop index if exists public.leads_scope_campaign_idx;
drop index if exists public.tasks_scope_contact_idx;
drop index if exists public.tasks_scope_lead_idx;

alter table public.leads drop constraint if exists leads_scope_landing_page_fkey;
alter table public.leads drop constraint if exists leads_scope_campaign_fkey;
alter table public.landing_pages drop constraint if exists landing_pages_scope_campaign_fkey;
alter table public.tasks drop constraint if exists tasks_scope_contact_fkey;
alter table public.tasks drop constraint if exists tasks_scope_lead_fkey;
