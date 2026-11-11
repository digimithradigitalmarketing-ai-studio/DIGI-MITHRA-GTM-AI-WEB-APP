-- 0006b_gtm_rls_completion.sql
-- Reconciles a partially applied 0006. Live state before this file: RLS enabled on
-- companies, clients and deals; four companies_* policies present; no clients or deals
-- policies; no guard_archive or sync_deal_status functions; no triggers on the new tables;
-- anon still holds privileges on the new tables.
--
-- Idempotent. Every object is created only if it is missing. No existing policy is
-- dropped or replaced. Nothing here is destructive.
--
-- Prerequisites (checked by section 0; the file stops before any change if one is missing):
--   * 0004b_gtm_archive_columns: archived_at and archived_by on companies, clients and deals (R4).
--   * 0002 and 0004: the (tenant_id, workspace_id, id) unique keys on companies, clients and deals.
--   * 0006: the four companies_* policies.
--   * The base helpers: app_private.ws_role, audit, set_created_by, set_updated_at; public.pipeline_stages
--     with is_won and is_lost; public.audit_logs.
--
-- Archive protection (R1). Once a row is archived, normal CRUD cannot change or delete it:
--   * trg_archive_immutable (before update or delete) refuses any change to an archived row with SQLSTATE 42501.
--   * The only exit is public.restore_archived_record(table, id). It requires tenant owner or admin, clears
--     archived_at, and writes a 'restore' row to audit_logs. It opens a one-transaction grant in
--     app_private.archive_restore_grant. No app role can read or write that table.
--   * Archiving itself stays a normal update, limited to tenant owners and admins by guard_archive.
--
-- NOT APPLIED. Do not run until the backup is verified and this file is approved.

-- 0. Preflight (R4). Stops before any change when a prerequisite is missing. Run 0004b first on a drifted schema.
do $$
declare
  v_missing text := '';
  t text;
  v_policy text;
begin
  if to_regnamespace('app_private') is null then
    v_missing := v_missing || ' schema app_private;';
  end if;
  foreach t in array array['app_private.ws_role(uuid,uuid)', 'app_private.audit()', 'app_private.set_created_by()',
                           'app_private.set_updated_at()'] loop
    if to_regprocedure(t) is null then
      v_missing := v_missing || ' function ' || t || ';';
    end if;
  end loop;
  if to_regclass('public.audit_logs') is null then
    v_missing := v_missing || ' table public.audit_logs;';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'pipeline_stages' and column_name = 'is_won')
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'pipeline_stages' and column_name = 'is_lost') then
    v_missing := v_missing || ' public.pipeline_stages.is_won and is_lost;';
  end if;

  foreach t in array array['companies', 'clients', 'deals'] loop
    if to_regclass('public.' || t) is null then
      v_missing := v_missing || ' table public.' || t || ';';
      continue;
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = 'archived_at') then
      v_missing := v_missing || ' ' || t || '.archived_at (0004b);';
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = t and column_name = 'archived_by') then
      v_missing := v_missing || ' ' || t || '.archived_by (0004b);';
    end if;
    if not exists (select 1 from pg_constraint where conrelid = to_regclass('public.' || t) and conname = t || '_tenant_id_workspace_id_id_key') then
      v_missing := v_missing || ' ' || t || ' scope key ' || t || '_tenant_id_workspace_id_id_key (0002/0004);';
    end if;
    if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = t || '_scope_active_idx') then
      v_missing := v_missing || ' index ' || t || '_scope_active_idx (0004b);';
    end if;
  end loop;

  -- companies_* policies are not required here: section 3 creates any that are missing, so a database
  -- with 0006 applied and one without it both reach the same policy set.

  if v_missing <> '' then
    raise exception 'preflight failed for 0006b; missing:%. Apply 0004b_gtm_archive_columns.sql and the earlier migrations first. No change was made.', v_missing
      using errcode = '42P01';
  end if;
end $$;

-- 1. Privileges (idempotent). Supabase's default grants give anon and authenticated
--    every table privilege. TRUNCATE is not filtered by RLS, and REFERENCES and TRIGGER
--    are not needed by the app, so authenticated keeps only SELECT, INSERT, UPDATE and
--    DELETE. RLS still decides which rows each role can touch. service_role is unchanged.
revoke all on public.companies, public.clients, public.deals from anon, authenticated;
grant select, insert, update, delete on public.companies, public.clients, public.deals to authenticated;

-- 2. RLS stays enabled on every new table (idempotent).
alter table public.companies enable row level security;
alter table public.clients enable row level security;
alter table public.deals enable row level security;

-- 3. Policies: create only if missing. companies_* already exist and match 0006, so they are skipped.
do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'companies' and policyname = 'companies_read') then
    create policy companies_read on public.companies for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'companies' and policyname = 'companies_insert') then
    create policy companies_insert on public.companies for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'companies' and policyname = 'companies_update') then
    create policy companies_update on public.companies for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]))
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'companies' and policyname = 'companies_delete') then
    create policy companies_delete on public.companies for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_read') then
    create policy clients_read on public.clients for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_insert') then
    create policy clients_insert on public.clients for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_update') then
    create policy clients_update on public.clients for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin')
      with check (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'clients' and policyname = 'clients_delete') then
    create policy clients_delete on public.clients for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;

  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_read') then
    create policy deals_read on public.deals for select to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) is not null);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_insert') then
    create policy deals_insert on public.deals for insert to authenticated
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_update') then
    create policy deals_update on public.deals for update to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]))
      with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'deals' and policyname = 'deals_delete') then
    create policy deals_delete on public.deals for delete to authenticated
      using (app_private.ws_role(tenant_id, workspace_id) = 'admin');
  end if;
end $$;

-- 4. Functions and archive protection (R1). create or replace is idempotent.

-- 4a. Archive grant table. Written only by restore_archived_record(), which runs as its owner. No app role has any privilege.
create table if not exists app_private.archive_restore_grant (
  txid bigint not null,
  table_name text not null,
  record_id uuid not null,
  primary key (txid, table_name, record_id)
);
revoke all on app_private.archive_restore_grant from public, anon, authenticated;

-- 4b. Archive and restore guard (BEFORE INSERT OR UPDATE). Archiving: tenant owner or admin only.
--     Clearing archived_at outside restore_archived_record is refused by guard_archived_immutable first.
create or replace function app_private.guard_archive()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.archived_at is null then
      new.archived_by := null;
      return new;
    end if;
  elsif new.archived_at is not distinct from old.archived_at then
    return new;
  end if;

  if app_private.ws_role(new.tenant_id, new.workspace_id) is distinct from 'admin' then
    raise exception 'only workspace admins can archive or restore records'
      using errcode = '42501';
  end if;

  new.archived_by := case when new.archived_at is null then null else (select auth.uid()) end;
  return new;
end
$$;

-- 4c. Immutability (BEFORE UPDATE OR DELETE, R1). An archived row cannot be changed or deleted, for any role.
--     The one permitted change is the restore, and only while restore_archived_record() holds a grant for this
--     transaction and this row.
-- SECURITY DEFINER: archive_restore_grant is revoked from authenticated (and anon), so the check must read it as the
-- function owner. Run as the caller, a direct update by an admin fails with "permission denied" instead of the
-- read-only message. The function body only reads its own table and txid_current(), so definer rights add no reach.
create or replace function app_private.guard_archived_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.archived_at is not null then
      raise exception 'archived records cannot be deleted; restore the record first' using errcode = '42501';
    end if;
    return old;
  end if;

  if old.archived_at is null then
    return new;
  end if;

  if new.archived_at is null and exists (
       select 1 from app_private.archive_restore_grant g
        where g.txid = txid_current() and g.table_name = tg_table_name and g.record_id = old.id) then
    return new;
  end if;

  raise exception 'archived records are read-only; restore the record first' using errcode = '42501';
end
$$;

-- 4d. Restore (R1). Callable by authenticated only. Tenant owner or admin only. Clears archived_at through the
--     grant in section 4a and writes a 'restore' row to audit_logs. The restore is refused for a record that is
--     not archived, and for a table outside the three GTM tables.
create or replace function public.restore_archived_record(p_table text, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_workspace uuid;
  v_archived timestamptz;
begin
  if p_table is null or p_table not in ('companies', 'clients', 'deals') then
    raise exception 'restore is not available for this table' using errcode = '22023';
  end if;

  execute format('select tenant_id, workspace_id, archived_at from public.%I where id = $1', p_table)
    into v_tenant, v_workspace, v_archived
    using p_id;
  if v_tenant is null then
    raise exception 'record not found' using errcode = 'P0002';
  end if;

  -- Role is checked before the archive state, so a caller who cannot restore learns nothing about archive status.
  if app_private.ws_role(v_tenant, v_workspace) is distinct from 'admin' then
    raise exception 'only tenant owners and admins can restore records' using errcode = '42501';
  end if;
  if v_archived is null then
    raise exception 'record is not archived' using errcode = '22023';
  end if;

  insert into app_private.archive_restore_grant (txid, table_name, record_id)
  values (txid_current(), p_table, p_id);

  execute format('update public.%I set archived_at = null where id = $1', p_table) using p_id;

  delete from app_private.archive_restore_grant
   where txid = txid_current() and table_name = p_table and record_id = p_id;

  insert into public.audit_logs (tenant_id, workspace_id, actor_id, action, entity, entity_id, meta)
  values (v_tenant, v_workspace, (select auth.uid()), 'restore', p_table, p_id::text,
          jsonb_build_object('archived_at_before', v_archived));
end
$$;

revoke execute on function public.restore_archived_record(text, uuid) from public, anon;
grant execute on function public.restore_archived_record(text, uuid) to authenticated;

-- 4e. Deal status from the pipeline stage (unchanged from the original 0006b).
create or replace function app_private.sync_deal_status()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_won boolean;
  v_lost boolean;
begin
  select ps.is_won, ps.is_lost into v_won, v_lost
    from public.pipeline_stages ps
   where ps.tenant_id = new.tenant_id
     and ps.workspace_id = new.workspace_id
     and ps.id = new.stage_id;
  if not found then
    raise exception 'deal stage % does not belong to this workspace', new.stage_id;
  end if;

  new.status := case when v_won then 'won' when v_lost then 'lost' else 'open' end;
  if new.status = 'open' then
    new.closed_at := null;
    new.lost_reason := null;
  elsif new.closed_at is null then
    new.closed_at := now();
  end if;
  return new;
end
$$;

-- 5. Triggers: create only if missing on that table.
do $$
declare
  spec record;
begin
  for spec in
    select * from (values
      ('companies', 'trg_created_by',       'before insert',                    'app_private.set_created_by'),
      ('companies', 'trg_updated',          'before update',                    'app_private.set_updated_at'),
      ('companies', 'trg_archive_immutable', 'before update or delete',         'app_private.guard_archived_immutable'),
      ('companies', 'trg_guard_archive',    'before insert or update',         'app_private.guard_archive'),
      ('companies', 'trg_audit',            'after insert or update or delete', 'app_private.audit'),
      ('clients',   'trg_created_by',       'before insert',                    'app_private.set_created_by'),
      ('clients',   'trg_updated',          'before update',                    'app_private.set_updated_at'),
      ('clients',   'trg_archive_immutable', 'before update or delete',         'app_private.guard_archived_immutable'),
      ('clients',   'trg_guard_archive',    'before insert or update',         'app_private.guard_archive'),
      ('clients',   'trg_audit',            'after insert or update or delete', 'app_private.audit'),
      ('deals',     'trg_created_by',       'before insert',                    'app_private.set_created_by'),
      ('deals',     'trg_updated',          'before update',                    'app_private.set_updated_at'),
      ('deals',     'trg_archive_immutable', 'before update or delete',         'app_private.guard_archived_immutable'),
      ('deals',     'trg_guard_archive',    'before insert or update',         'app_private.guard_archive'),
      ('deals',     'trg_audit',            'after insert or update or delete', 'app_private.audit'),
      ('deals',     'trg_deal_status',      'before insert or update',         'app_private.sync_deal_status')
    ) as v(tbl, name, timing, fn)
  loop
    if not exists (
      select 1 from pg_trigger
       where tgname = spec.name
         and tgrelid = format('public.%I', spec.tbl)::regclass
    ) then
      execute format(
        'create trigger %I %s on public.%I for each row execute function %s()',
        spec.name, spec.timing, spec.tbl, spec.fn);
    end if;
  end loop;
end $$;
