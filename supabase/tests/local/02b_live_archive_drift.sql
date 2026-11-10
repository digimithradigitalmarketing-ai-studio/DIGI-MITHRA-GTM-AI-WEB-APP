-- 02b_live_archive_drift.sql
-- LOCAL TEST FIXTURE ONLY. Never run on production.
-- Recreates the live project's catalog state for the archive columns. Migration 0004 defines
-- archived_at and archived_by on companies, clients and deals, and their partial indexes. The
-- live project's tables were created without them (checked against the live catalog on
-- 2026-11-10). Dropping a column also drops its foreign key and its partial index.
-- The archive guard in 0006b reads new.archived_at, so every write fails until 0004b runs.

alter table public.companies drop column if exists archived_at, drop column if exists archived_by;
alter table public.clients   drop column if exists archived_at, drop column if exists archived_by;
alter table public.deals     drop column if exists archived_at, drop column if exists archived_by;
