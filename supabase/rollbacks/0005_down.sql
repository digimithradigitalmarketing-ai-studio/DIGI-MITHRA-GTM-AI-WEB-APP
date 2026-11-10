-- Rollback for 0005. Removes the company link columns from contacts and leads.
-- Destroys any company_id values written after apply. Manual only, never automatic.
drop index if exists public.leads_scope_company_idx;
drop index if exists public.contacts_scope_company_idx;

alter table public.leads drop constraint if exists leads_scope_company_fkey;
alter table public.contacts drop constraint if exists contacts_scope_company_fkey;

alter table public.leads drop column if exists company_id;
alter table public.contacts drop column if exists company_id;
