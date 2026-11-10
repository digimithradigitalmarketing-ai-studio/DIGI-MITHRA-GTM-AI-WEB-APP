-- 02_live_partial_state.sql
-- Reproduces the live project's state after the partial 0006 run, on top of 0002 to 0005:
--   * RLS enabled on companies, clients and deals;
--   * the four companies_* policies, with the same text as 0006;
--   * nothing else: no clients or deals policies, no GTM triggers, no guard or
--     sync functions, and anon still holds privileges (default grants).
-- Used to rehearse 0006b against the same starting point as production.
-- Local only. Never run this against production.

alter table public.companies enable row level security;
alter table public.clients enable row level security;
alter table public.deals enable row level security;

create policy companies_read on public.companies for select to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) is not null);
create policy companies_insert on public.companies for insert to authenticated
  with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
create policy companies_update on public.companies for update to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]))
  with check (app_private.ws_role(tenant_id, workspace_id) = any ('{admin,manager,editor}'::text[]));
create policy companies_delete on public.companies for delete to authenticated
  using (app_private.ws_role(tenant_id, workspace_id) = 'admin');
