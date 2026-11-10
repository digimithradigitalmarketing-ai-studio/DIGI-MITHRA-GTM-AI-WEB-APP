-- 0006_gtm_rls_triggers.sql
-- Additive. RLS, grants, triggers and functions for companies, clients and deals only.
-- No existing policy, trigger or function is changed.
--
-- SUPERSEDED FOR THE LIVE DATABASE. 0006 was partially applied there (RLS enabled and the
-- companies policies created, nothing else). Do not run this file on live. Use 0006b, which
-- is idempotent and reconciles the live state.
--
-- Access model (enforced in RLS and in the guard trigger, never only in the client):
--   admin      = app_private.ws_role() returns 'admin' (tenant owner or tenant admin)
--   sales      = workspace role 'manager' or 'editor' in that workspace
--   read only  = 'support', 'analyst', 'viewer', 'approver'
--   no access  = anyone without a membership in that workspace

revoke all on public.companies, public.clients, public.deals from anon;

alter table public.companies enable row level security;
alter table public.clients enable row level security;
alter table public.deals enable row level security;

-- companies: members read; admin and sales create and edit; admin only hard-deletes
create policy companies_read on public.companies for select to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) is not null);
create policy companies_insert on public.companies for insert to authenticated
  with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
create policy companies_update on public.companies for update to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]))
  with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
create policy companies_delete on public.companies for delete to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = 'admin');

-- clients: members read; admin only for create, edit, archive and delete
create policy clients_read on public.clients for select to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) is not null);
create policy clients_insert on public.clients for insert to authenticated
  with check (app_private.ws_role(tenant_id, workspace_id) = 'admin');
create policy clients_update on public.clients for update to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = 'admin')
  with check (app_private.ws_role(tenant_id, workspace_id) = 'admin');
create policy clients_delete on public.clients for delete to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = 'admin');

-- deals: members read; admin and sales create and edit; admin only hard-deletes
create policy deals_read on public.deals for select to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) is not null);
create policy deals_insert on public.deals for insert to authenticated
  with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
create policy deals_update on public.deals for update to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]))
  with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
create policy deals_delete on public.deals for delete to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = 'admin');

-- Archive and restore: admins only. RLS cannot see column changes, so this trigger checks them.
-- Sales users can still edit a row; they cannot change archived_at or archived_by.
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

-- Standard triggers, matching the existing tables.
create trigger trg_created_by before insert on public.companies
  for each row execute function app_private.set_created_by();
create trigger trg_updated before update on public.companies
  for each row execute function app_private.set_updated_at();
create trigger trg_guard_archive before insert or update on public.companies
  for each row execute function app_private.guard_archive();
create trigger trg_audit after insert or update or delete on public.companies
  for each row execute function app_private.audit();

create trigger trg_created_by before insert on public.clients
  for each row execute function app_private.set_created_by();
create trigger trg_updated before update on public.clients
  for each row execute function app_private.set_updated_at();
create trigger trg_guard_archive before insert or update on public.clients
  for each row execute function app_private.guard_archive();
create trigger trg_audit after insert or update or delete on public.clients
  for each row execute function app_private.audit();

create trigger trg_created_by before insert on public.deals
  for each row execute function app_private.set_created_by();
create trigger trg_updated before update on public.deals
  for each row execute function app_private.set_updated_at();
create trigger trg_guard_archive before insert or update on public.deals
  for each row execute function app_private.guard_archive();
create trigger trg_audit after insert or update or delete on public.deals
  for each row execute function app_private.audit();

-- A deal's status follows its stage flags, so it cannot disagree with pipeline_stages.
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

create trigger trg_deal_status before insert or update on public.deals
  for each row execute function app_private.sync_deal_status();
