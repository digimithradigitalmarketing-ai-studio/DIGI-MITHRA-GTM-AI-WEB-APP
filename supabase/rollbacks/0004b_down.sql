-- 0004b_down.sql
-- MANUAL ROLLBACK. Never run automatically, and never run it on production without a verified backup
-- and separate approval. It drops archived_at and archived_by on companies, clients and deals, which
-- also drops their foreign keys and partial indexes.
--
-- Order matters. Run supabase/rollbacks/0006b_down.sql first. Its guard_archive() trigger reads
-- new.archived_at, so writes to these tables fail once the columns are gone.
--
-- The guard below refuses to run while any archived row exists, so archive history is never
-- dropped silently. To proceed, restore those rows or export them first, then run this file.

do $$
begin
  if exists (select 1 from public.companies where archived_at is not null)
     or exists (select 1 from public.clients where archived_at is not null)
     or exists (select 1 from public.deals where archived_at is not null) then
    raise exception 'refusing rollback 0004b: archived rows exist; restore or export them first';
  end if;
end $$;

alter table public.companies drop column if exists archived_at, drop column if exists archived_by;
alter table public.clients   drop column if exists archived_at, drop column if exists archived_by;
alter table public.deals     drop column if exists archived_at, drop column if exists archived_by;
