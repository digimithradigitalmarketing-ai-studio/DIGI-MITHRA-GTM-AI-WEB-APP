-- 0004b_down.sql
-- MANUAL ROLLBACK. Never run automatically, and never run it on production without a verified backup
-- and separate approval. It drops archived_at and archived_by on companies, clients and deals, which
-- also drops their foreign keys and partial indexes.
--
-- Order matters. Archive protection (0006b) reads archived_at, so it must be withdrawn first. 0006b_down.sql keeps
-- protection in place on purpose. To remove it, run supabase/rollbacks/0006b_archive_guard_down.sql (separate
-- approval) before this file.
--
-- The checks below refuse to run while the archive guard is installed, and while any archived row exists, so
-- archive history is never dropped silently. To proceed, remove the guard and restore or export the archived rows.

do $$
begin
  if to_regprocedure('app_private.guard_archive()') is not null
     or to_regprocedure('app_private.guard_archived_immutable()') is not null
     or to_regprocedure('public.restore_archived_record(text,uuid)') is not null then
    raise exception 'refusing rollback 0004b: archive protection is still installed (0006b). Run rollbacks/0006b_archive_guard_down.sql first, with separate approval.';
  end if;
  if exists (select 1 from public.companies where archived_at is not null)
     or exists (select 1 from public.clients where archived_at is not null)
     or exists (select 1 from public.deals where archived_at is not null) then
    raise exception 'refusing rollback 0004b: archived rows exist; restore or export them first';
  end if;
end $$;

alter table public.companies drop column if exists archived_at, drop column if exists archived_by;
alter table public.clients   drop column if exists archived_at, drop column if exists archived_by;
alter table public.deals     drop column if exists archived_at, drop column if exists archived_by;
