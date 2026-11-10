# Supabase advisor baseline and policy fingerprint

Project: `siyxkombexmowlggxlrb` (shared production project, read-only checks only).
Captured: 2026-11-10 (advisor `observed_at` 11:42 UTC).
Purpose: record what the live project already reports, so future migrations can be judged
against it. Findings below are **existing** unless the section says otherwise.

## 1. Policy fingerprint

Query (run identically on production and locally; `COLLATE "C"` on the text and both ordering columns):

```sql
select count(*) as policy_count,
       md5(coalesce(string_agg(
         (tablename || '|' || policyname || '|' || cmd || '|' || roles::text || '|' ||
          coalesce(qual, '') || '|' || coalesce(with_check, '')) collate "C",
         E'\n' order by tablename collate "C", policyname collate "C"), '')) as fingerprint
from pg_policies
where schemaname = 'public' and tablename not in ('companies', 'clients', 'deals');
```

| Target | Policies | Fingerprint | Result |
|---|---|---|---|
| Production, full query | 143 | `f8a58a0bd0cb57356909931e1bc383c5` | baseline |
| Local replica (`gtm_local_fresh` and `gtm_local_live_replay`), full query | 41 | `33ad6c188e164f6eb50aefd064a7f8fc` | **not comparable**: the replica holds 15 public tables, production holds more |
| Production, subset of the 12 tables the replica also has | 41 | `33ad6c188e164f6eb50aefd064a7f8fc` | **match** |

The subset is `activities, audit_logs, campaigns, contacts, landing_pages, leads, pipeline_stages,
tasks, tenant_members, tenants, workspace_members, workspaces`. The subset comparison is the
meaningful parity check. The full-database hash cannot match a partial replica by design. Production
was not modified to make any hash match.

## 2. Advisor baseline (existing)

Counts: security 45, performance 108, health 0. Each is grouped below by lint.

### Security (45)

| Lint | Level | Count | Scope | Notes |
|---|---|---|---|---|
| `rls_enabled_no_policy` | INFO | 3 | `clients`, `deals`: GTM. `webhook_events`: outside GTM | `clients` and `deals` gaps are what 0006b closes. `webhook_events` is pre-existing and outside GTM. |
| `anon_security_definer_function_executable` | WARN | 9 | Outside GTM | `get_landing_page`, `record_landing_view`, `rls_auto_enable`, `send_web_chat`, `start_web_chat`, `submit_landing_form`, `unsubscribe_email`, `web_chat_config`, `web_chat_messages`. `anon` can call them. |
| `authenticated_security_definer_function_executable` | WARN | 32 | Outside GTM | Includes the `dashboard_stats`, `platform_*` and `*_post` functions. Not GTM-related. |
| `auth_leaked_password_protection` | WARN | 1 | Auth setting | HaveIBeenPwned check is disabled. Dashboard setting, not a migration. |

### Performance (108)

| Lint | Level | Count | Scope | Notes |
|---|---|---|---|---|
| `unindexed_foreign_keys` | INFO | 91 | 5 GTM, 86 outside GTM | GTM: `companies_created_by_fkey`, `clients_account_owner_id_fkey`, `clients_created_by_fkey`, `clients_scope_contact_fkey`, `deals_created_by_fkey`. |
| `unused_index` | INFO | 15 | 6 GTM, 9 outside GTM | GTM: all six `deals_*` indexes (`deals_scope_stage_idx`, `deals_scope_status_close_idx`, `deals_scope_company_idx`, `deals_scope_contact_idx`, `deals_scope_lead_idx`, `deals_owner_idx`). These are expected on a new table with little traffic. |
| `multiple_permissive_policies` | WARN | 2 | Outside GTM | `appointments` (SELECT), `workspace_members` (SELECT). |

Production does **not** have `companies_scope_active_idx`, `clients_scope_active_idx` or
`deals_scope_active_idx`. They are absent because the archive columns are missing (see section 4).

## 3. Expected migration-induced findings (predicted, not yet verified)

These predictions are for the advisor run after each migration is applied to production. They are not
observed. Confirm them with `get_advisors` after applying the migration.

| Migration | Expected change | Why |
|---|---|---|
| `0004b_gtm_archive_columns` | +3 `unindexed_foreign_keys` (`companies_archived_by_fkey`, `clients_archived_by_fkey`, `deals_archived_by_fkey`) | Adds `archived_by` foreign keys to `auth.users` with no covering index. |
| `0004b_gtm_archive_columns` | Possible +3 `unused_index` (the three `*_scope_active_idx` indexes) | Partial indexes on a new column; they will be unused until archives exist. |
| `0006b_gtm_rls_completion` | -2 `rls_enabled_no_policy` (`clients`, `deals`) | Creates the missing read, insert, update and delete policies. |
| `0006b_gtm_rls_completion` | No new `multiple_permissive_policies` expected | Each GTM table gets one permissive policy per action. |
| `0006b_gtm_rls_completion` | No change expected to the `anon_*` or `authenticated_*` function lints | The new functions live in `app_private`, which is not exposed through the REST API. |

Any finding outside this table after applying a migration is a new, migration-induced finding and must be
investigated before the next step.

## 4. Production drift found during reconciliation

Production `companies`, `clients` and `deals` do not have `archived_at`, `archived_by`, or the three
active-row partial indexes that migration 0004 defines. Migration `0004b_gtm_archive_columns.sql`
adds them additively. Until it is applied, the archive guard in 0006b fails on every write to those
three tables, so 0004b must run before 0006b on production.
