-- production_table_names.sql
-- LOCAL FIXTURE ONLY. Never run on production.
-- Creates the 30 production public tables the replica does not model, so the replica has the production count (56).
-- Each table gets production's grant shape: anon and authenticated hold all table privileges (checked read-only on
-- 2026-11-11). RLS is enabled. The columns are placeholders; the privilege tests do not read row data.
do $$ declare t text; begin
  foreach t in array array['ai_generations','api_keys','appointments','brand_knowledge','chat_messages','chat_threads','competitors','content_ideas','content_plans','content_posts','content_sources','email_campaigns','invitations','invoices','media_assets','metric_snapshots','post_approvals','post_targets','profiles','publish_attempts','reviews','saved_items','segments','social_accounts','subscriptions','support_messages','support_tickets','usage_events','webhook_endpoints','webhook_events'] loop
    execute format('create table if not exists public.%I (id uuid primary key default gen_random_uuid(), tenant_id uuid, workspace_id uuid, created_at timestamptz not null default now())', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('grant all on table public.%I to anon, authenticated, service_role', t);
  end loop;
end $$;

-- The replica's path E applies 0006b, which revokes anon and authenticated from companies, clients and deals. Production
-- has NOT applied 0006b (checked read-only on 2026-11-11: no clients or deals policies, no archived_* columns), so
-- production grants anon and authenticated every table privilege on these three as well. Restore that shape here.
grant all on table public.companies, public.clients, public.deals to anon, authenticated;
