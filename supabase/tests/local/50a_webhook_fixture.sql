-- 50a_webhook_fixture.sql
-- Synthetic-only stand-in for public.webhook_events. The local base schema does not
-- define that table, so this creates it with the Data API default grants the review
-- revokes. Runs inside the runner's transaction and is rolled back with it.

create table public.webhook_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid,
  payload jsonb
);
grant all on public.webhook_events to anon, authenticated, service_role;
alter table public.webhook_events enable row level security;
