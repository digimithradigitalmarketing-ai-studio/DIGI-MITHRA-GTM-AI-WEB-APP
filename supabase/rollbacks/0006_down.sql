-- Rollback for 0006. Removes policies, triggers and functions added by 0006.
-- Does NOT re-grant anon. Anon must stay blocked. Manual only, never automatic.
drop trigger if exists trg_deal_status on public.deals;
drop trigger if exists trg_audit on public.deals;
drop trigger if exists trg_guard_archive on public.deals;
drop trigger if exists trg_updated on public.deals;
drop trigger if exists trg_created_by on public.deals;
drop trigger if exists trg_audit on public.clients;
drop trigger if exists trg_guard_archive on public.clients;
drop trigger if exists trg_updated on public.clients;
drop trigger if exists trg_created_by on public.clients;
drop trigger if exists trg_audit on public.companies;
drop trigger if exists trg_guard_archive on public.companies;
drop trigger if exists trg_updated on public.companies;
drop trigger if exists trg_created_by on public.companies;

drop function if exists app_private.sync_deal_status();
drop function if exists app_private.guard_archive();

drop policy if exists deals_delete on public.deals;
drop policy if exists deals_update on public.deals;
drop policy if exists deals_insert on public.deals;
drop policy if exists deals_read on public.deals;
drop policy if exists clients_delete on public.clients;
drop policy if exists clients_update on public.clients;
drop policy if exists clients_insert on public.clients;
drop policy if exists clients_read on public.clients;
drop policy if exists companies_delete on public.companies;
drop policy if exists companies_update on public.companies;
drop policy if exists companies_insert on public.companies;
drop policy if exists companies_read on public.companies;

alter table public.deals disable row level security;
alter table public.clients disable row level security;
alter table public.companies disable row level security;
