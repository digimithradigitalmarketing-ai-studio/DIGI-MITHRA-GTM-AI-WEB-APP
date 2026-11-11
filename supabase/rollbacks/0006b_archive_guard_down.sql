-- 0006b_archive_guard_down.sql (R2)
-- MANUAL, SEPARATELY APPROVED. Removes archive protection: the immutability and guard triggers, the restore
-- function and its grant table, and the guard functions. After this runs, archived records become editable again
-- by any role that passes RLS, and there is no restore path. Do not run it to "finish" a rollback. Run it only when
-- archive protection is being deliberately withdrawn, with an owner decision recorded.
--
-- Refuses to run unless the session sets gtm.confirm_drop_archive_guard = 'yes', and refuses while any archived row
-- exists, so archive history is never removed silently. Restore or export the archived rows first.
--
-- Order: run this before supabase/rollbacks/0004b_down.sql, which refuses to drop the archive columns while the
-- guard is installed.

do $$
begin
  if current_setting('gtm.confirm_drop_archive_guard', true) is distinct from 'yes' then
    raise exception 'refusing: archive protection removal needs gtm.confirm_drop_archive_guard = yes (separate owner approval)';
  end if;
  if exists (select 1 from public.companies where archived_at is not null)
     or exists (select 1 from public.clients where archived_at is not null)
     or exists (select 1 from public.deals where archived_at is not null) then
    raise exception 'refusing archive guard removal: archived rows exist; restore or export them first';
  end if;
end $$;

drop trigger if exists trg_archive_immutable on public.companies;
drop trigger if exists trg_guard_archive on public.companies;
drop trigger if exists trg_archive_immutable on public.clients;
drop trigger if exists trg_guard_archive on public.clients;
drop trigger if exists trg_archive_immutable on public.deals;
drop trigger if exists trg_guard_archive on public.deals;

drop function if exists public.restore_archived_record(text, uuid);
drop table if exists app_private.archive_restore_grant;
drop function if exists app_private.guard_archived_immutable();
drop function if exists app_private.guard_archive();
