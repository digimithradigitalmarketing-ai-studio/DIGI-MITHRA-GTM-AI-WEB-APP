# Migration history reconciliation (0005 and the GTM sequence)

Project: `siyxkombexmowlggxlrb`. Read-only review, 2026-11-11.
Production was not changed. No row was written to `supabase_migrations.schema_migrations`, and nothing was
replayed. The companion check is `supabase/reviews/0005_verify_only.sql`.

## 1. What production records

`list_migrations` returns 20 rows. The first 19 are the base product's history, and the last one is the GTM org foundation:

| version (production) | name (production) |
|---|---|
| 20261020055517 | 0001_foundation |
| 20261020055827 | 0002a_access_helpers |
| 20261020055833 | 0002b_revokes |
| 20261020055852 | 0002c_rls_policies |
| 20261020055923 | 0003_logic_triggers |
| 20261020060011 | 0004a_rpc_core |
| 20261020060054 | 0004b_rpc_inbox_workflows |
| 20261020060118 | 0004c_rpc_billing_dashboard |
| 20261020060207 | 0004d_send_reply_and_owner_delete |
| 20261020060214 | 0004e_lock_private_functions |
| 20261020060224 | 0005_cron_publisher |
| 20261020061218 | 0006_revoke_anon_rpc |
| 20261020063704 | 0007_content_studio |
| 20261020064540 | 0008_marketing_hub |
| 20261020064609 | 0009_email_send_log_policy |
| 20261020070100 | 0010_platform_completion |
| 20261020070107 | 0011_more_providers |
| 20261020070243 | 0012_worker_queue |
| 20261020075023 | 0013_avatars_team_activity |
| 20261109051134 | digimithra_0001_organizations_membership |

No row for any GTM migration in this repository (0002_gtm_scope_keys through 0008_gtm_clients_readiness) is recorded.

## 2. Version format mismatch

- Production versions are 14-digit timestamps (`YYYYMMDDHHMMSS`). The repository uses 4-digit numeric prefixes.
- The repository's number cannot be matched to a production version. Matching has to be done by name, and a name
  match is not evidence that the migration ran.
- Four numbers collide between the two sequences. Production `0005_cron_publisher` vs repository `0005_gtm_company_links`.
  Production `0006_revoke_anon_rpc` vs `0006_gtm_rls_triggers`. Production `0007_content_studio` vs `0007_gtm_automation_engine`.
  Production `0008_marketing_hub` vs `0008_gtm_clients_readiness`. Production also has `0004b_rpc_inbox_workflows`, which
  collides with the repository's `0004b_gtm_archive_columns`, and `0002a`/`0002b`/`0002c` and `0004a`–`0004e` have
  no repository counterpart.
- Production's `0001` is `digimithra_0001_organizations_membership`. The repository's is `0001_organizations_membership`.

Consequence: the repository's migration numbers must never be used to decide what is applied. This report decides it
from the catalog.

## 3. What the catalog shows for each GTM migration (read-only)

| repo migration | production catalog evidence | status |
|---|---|---|
| 0002_gtm_scope_keys | `companies`, `clients`, `deals`, `contacts`, `leads` have `UNIQUE (tenant_id, workspace_id, id)` | applied (no history row) |
| 0003_gtm_scoped_crm_foreign_keys | `landing_pages_scope_campaign_fkey` present and validated; `leads_scope_campaign_fkey`, `leads_scope_landing_page_fkey`, `tasks_scope_*`, `deals_scope_*` present | applied (no history row) |
| 0004_gtm_companies_clients_deals | tables `companies`, `clients`, `deals`, `pipeline_stages` exist with scoped FKs | applied in part (no history row) |
| 0004b_gtm_archive_columns | **no** `archived_*` column on `companies`, `clients` or `deals` | **NOT applied** |
| 0005_gtm_company_links | `contacts.company_id` and `leads.company_id` nullable uuid; `contacts_scope_company_fkey` and `leads_scope_company_fkey` validated with `ON DELETE SET NULL (company_id)`; both partial indexes present | **applied** (verified by `0005_verify_only.sql`, which raised no exception) |
| 0005a_gtm_contacts_leads_baseline | not reviewed in this round | unknown |
| 0006_gtm_rls_triggers (partial) | RLS enabled on `companies`, `clients`, `deals`; four `companies_*` policies; no `clients_*` or `deals_*` policies; no GTM triggers | partial, as the notes say |
| 0006b_gtm_rls_completion | **no** `clients_*` or `deals_*` policies; no `app_private.guard_archive`; no `app_private.sync_deal_status`; no triggers on the three tables | **NOT applied** |
| 0007a_gtm_workflow_baseline | `run_workflow_test(uuid,jsonb)` and `cancel_workflow_run(uuid)` exist | partial (baseline functions present) |
| 0007_gtm_automation_engine | **no** `public.retry_workflow_run(uuid)`, `workflow_runs.retry_of`, `tasks.automation_key` or `workflows` trigger `trg_validate_definition` | **NOT applied** |
| 0008_gtm_clients_readiness | **no** `public.clients_readiness()` | **NOT applied** |
| 0009 (proposed) | anon holds every table privilege on all 56 tables | **NOT applied** |
| 0010 (proposed) | authenticated and anon hold TRUNCATE on all 56 tables | **NOT applied** |

Earlier notes (`DEPLOYMENT_PLAN.md` live-state table) say 0004b and 0006b were run on production. The catalog contradicts
that for both, so the live-state table must be corrected before any deployment is considered. The correction is in
the deployment plan update for this round.

## 4. Application dependencies that production cannot satisfy today

The application code calls functions that production does not have:

- `src/lib/crm/readiness.ts` calls `supabase.rpc("clients_readiness")`. Production has no such function (0008).
- `src/app/(app)/automations/actions.ts` calls `supabase.rpc("retry_workflow_run", ...)`. Production has no such function (0007).

Deploying the application before 0007 and 0008 are applied would break the Clients readiness gate and the workflow retry
action. This is a deployment blocker, recorded in the security-readiness report.

## 5. Verify-only result for 0005

`supabase/reviews/0005_verify_only.sql` checks: the two `company_id` columns (uuid, nullable, no default); both
scoped foreign keys (validated, referencing `companies (tenant_id, workspace_id, id)`, `ON DELETE SET NULL` limited to
`company_id`, child columns `(tenant_id, workspace_id, company_id)`); both partial indexes with their definitions;
and the `companies (tenant_id, workspace_id, id)` unique key that the foreign keys depend on.

- Replica (`gtm_local_prod_surface`): passes.
- Negative control (a copy with `leads_scope_company_idx` dropped): fails with `one or both company indexes are missing`.
- Production: no exception raised. The read-only tool does not display `NOTICE` text, so the pass is inferred from the
  absence of an error.

## 6. Decision

- Do not replay `0005_gtm_company_links.sql` on production. Its `ADD COLUMN` statements would fail, and the columns
  already match the file.
- Do not insert history rows. Inserting rows that claim the GTM migrations ran would fabricate history. Recording
  them is a separate owner decision that must follow a verified backup and a `migration repair` step, outside this round.
- The catalog is the source of truth until that decision. The deployment order in `DEPLOYMENT_PLAN.md` is based on the
  catalog, not on the history table.
- The source of the 0005 objects is not recorded in production history. The catalog matches the file, but how it got
  there (manual SQL, a different branch, or the earlier partial run) cannot be determined with read-only access.
