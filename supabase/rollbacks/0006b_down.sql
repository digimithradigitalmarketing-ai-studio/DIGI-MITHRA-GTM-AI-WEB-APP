-- 0006b_down.sql (R2, revised 2026-11-12)
-- MANUAL ROLLBACK. Never run automatically, and never run it on production without a verified backup
-- and separate approval.
--
-- THIS IS NOT A FULL ROLLBACK. It removes only the clients_* and deals_* policies that 0006b adds, so that
-- clients and deals fail closed (no app role can read or write them). Everything else 0006b installs stays
-- in place on purpose, because archive protection and the audit trail must not be weakened by a rollback.
--
-- Changes made by this file (the complete list):
--   RLS      Removed: clients_read, clients_insert, clients_update, clients_delete, deals_read, deals_insert,
--            deals_update, deals_delete. RLS stays enabled on companies, clients and deals, so with no
--            policies on clients and deals every app role reads zero rows and every write is refused.
--   Policies Kept: the four companies_* policies (from 0006).
--   Grants   Not restored. anon keeps no privilege on the three tables. authenticated keeps SELECT, INSERT,
--            UPDATE and DELETE only (no TRUNCATE, REFERENCES, TRIGGER or MAINTAIN). See supabase/tests/local/37.
--   Triggers Kept on companies, clients and deals: trg_archive_immutable, trg_guard_archive, trg_audit,
--            trg_created_by, trg_updated. Kept on deals: trg_deal_status.
--   Functions Kept: app_private.guard_archive, app_private.guard_archived_immutable,
--            app_private.sync_deal_status, public.restore_archived_record, and the archive_restore_grant table.
--
-- Archive protection after this rollback: an archived record cannot be changed or deleted by any role, and the
-- only restore is public.restore_archived_record (tenant owner or admin, audited). Companies also keep the
-- archive guard, so only an admin can archive a company.
--
-- To remove archive protection as well, run supabase/rollbacks/0006b_archive_guard_down.sql, separately
-- approved. It refuses to run while any archived row exists.
--
-- Order: 0004b_down.sql refuses to run while the archive guard is installed, so 0006b_archive_guard_down.sql
-- must run before 0004b_down.sql, and the archive columns cannot be dropped while protection is still in place.

drop policy if exists deals_delete on public.deals;
drop policy if exists deals_update on public.deals;
drop policy if exists deals_insert on public.deals;
drop policy if exists deals_read on public.deals;
drop policy if exists clients_delete on public.clients;
drop policy if exists clients_update on public.clients;
drop policy if exists clients_insert on public.clients;
drop policy if exists clients_read on public.clients;
