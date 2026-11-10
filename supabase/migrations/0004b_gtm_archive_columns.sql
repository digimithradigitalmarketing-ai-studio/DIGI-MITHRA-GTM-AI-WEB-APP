-- 0004b_gtm_archive_columns.sql
-- Additive and idempotent. Adds the soft-delete columns that 0004 defines but that the live
-- project does not have. Found during catalog reconciliation on 2026-11-10: the live
-- companies, clients and deals tables were created without archived_at, archived_by and
-- their active-row indexes. Without these columns the archive guard trigger in 0006b
-- fails on every write, so 0004b must be applied BEFORE 0006b on the live database.
--
-- On a database built from the repo files, every statement here is a no-op, because 0004
-- already created the columns and indexes.
--
-- No data is changed or removed. The columns are nullable and default to null, so every
-- existing row stays active. This file contains no destructive statement.
--
-- Rollback (manual, never automatic): supabase/rollbacks/0004b_down.sql. It drops the columns, which
-- also drops any archive history stored in them. Do not run it after rows are archived.

alter table public.companies
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users (id) on delete set null;

alter table public.clients
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users (id) on delete set null;

alter table public.deals
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users (id) on delete set null;

create index if not exists companies_scope_active_idx
  on public.companies (tenant_id, workspace_id) where archived_at is null;
create index if not exists clients_scope_active_idx
  on public.clients (tenant_id, workspace_id, status) where archived_at is null;
create index if not exists deals_scope_active_idx
  on public.deals (tenant_id, workspace_id, stage_id) where archived_at is null;
