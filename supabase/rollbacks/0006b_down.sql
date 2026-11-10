-- 0006b_down.sql
-- MANUAL ROLLBACK. Never run automatically, and never run it on production without a verified backup
-- and separate approval.
--
-- Removes what 0006b adds to the live state: the clients_* and deals_* policies, the guard and
-- status functions, and every trigger 0006b creates on companies, clients and deals.
-- Assumes the state 0006b expects before it runs: no triggers on those three tables (the live
-- state documented in 0006b's header). Do not run it on a database where 0006 itself applied its triggers.
--
-- Deliberately kept:
--   * RLS stays enabled on companies, clients and deals.
--   * The companies_* policies stay. They came from 0006, not from 0006b.
--   * Grants are NOT restored. The anon role must stay blocked, and authenticated must not
--     regain TRUNCATE, REFERENCES or TRIGGER on these tables.
--
-- Order: run this BEFORE supabase/rollbacks/0004b_down.sql. The archive guard reads archived_at,
-- so removing the columns first would break writes until this rollback runs.

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

drop policy if exists deals_delete on public.deals;
drop policy if exists deals_update on public.deals;
drop policy if exists deals_insert on public.deals;
drop policy if exists deals_read on public.deals;
drop policy if exists clients_delete on public.clients;
drop policy if exists clients_update on public.clients;
drop policy if exists clients_insert on public.clients;
drop policy if exists clients_read on public.clients;

drop function if exists app_private.sync_deal_status();
drop function if exists app_private.guard_archive();
