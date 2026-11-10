-- 0006b_gtm_rls_completion.sql
-- Reconciles a partially applied 0006. Live state before this file: RLS enabled on
-- companies, clients and deals; four companies_* policies present; no clients or deals
-- policies; no guard_archive or sync_deal_status functions; no triggers on the new tables;
-- anon still holds privileges on the new tables.
--
-- Idempotent. Every object is created only if it is missing. No existing policy is
-- dropped or replaced. Nothing here is destructive.
--
-- NOT APPLIED. Do not run until the backup is verified and this file is approved.

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

-- 4. Functions (create or replace is idempotent).
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
      ('companies', 'trg_created_by',    'before insert',                    'app_private.set_created_by'),
      ('companies', 'trg_updated',       'before update',                    'app_private.set_updated_at'),
      ('companies', 'trg_guard_archive', 'before insert or update',         'app_private.guard_archive'),
      ('companies', 'trg_audit',         'after insert or update or delete', 'app_private.audit'),
      ('clients',   'trg_created_by',    'before insert',                    'app_private.set_created_by'),
      ('clients',   'trg_updated',       'before update',                    'app_private.set_updated_at'),
      ('clients',   'trg_guard_archive', 'before insert or update',         'app_private.guard_archive'),
      ('clients',   'trg_audit',         'after insert or update or delete', 'app_private.audit'),
      ('deals',     'trg_created_by',    'before insert',                    'app_private.set_created_by'),
      ('deals',     'trg_updated',       'before update',                    'app_private.set_updated_at'),
      ('deals',     'trg_guard_archive', 'before insert or update',         'app_private.guard_archive'),
      ('deals',     'trg_audit',         'after insert or update or delete', 'app_private.audit'),
      ('deals',     'trg_deal_status',   'before insert or update',         'app_private.sync_deal_status')
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
