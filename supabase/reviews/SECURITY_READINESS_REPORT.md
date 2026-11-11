# Security readiness report: DigiMithra GTM AI

Project `siyxkombexmowlggxlrb`. Branch `gtm-phase-3-live-crm`. Date 2026-11-11.

**Not ready for production execution.** The development artifacts are reviewed and tested on a local replica. Production
has no approval to change, and it has blockers that prevent the app from working as deployed (section 3).

Scope rule: nothing was applied to production. Read-only queries were run against production. `main` was not merged
into. Nothing was deployed. Each result below is classed PASSED, FAILED, BLOCKED or NOT TESTED.

## 1. PASSED

Each item has a reproducible command or query.

| Check | Evidence |
| --- | --- |
| Lint | `npm run lint`: exit 0 |
| Type check | `npx tsc --noEmit`: exit 0 |
| Unit tests | `npx vitest run`: 9 files, 139 tests passed |
| Production build | `next build` with placeholder public env: exit 0 |
| Production dependency audit | `npm audit --omit=dev`: 0 vulnerabilities |
| Local harness (all paths) | `tests/local/run_local.sh`: exit 0. 49 passing checks. Expected-failure controls reported as "observed (expected)" |
| 0010 least privilege, 56-table scope (path G) | Control fails before 0010 with TRUNCATE violations. After 0010, test 36 passes. ACL compare: only TRUNCATE removed, across all 56 tables. Suites 31, 32, 33, 34, `gtm_scope_rls` pass. Rollback refuses without confirmation, restores on confirmation, reapply passes |
| 0006b round trip (path F) | Snapshot S0 before; S1 after apply; suites `gtm_scope_rls`, 30, 31 pass; `0006b_down` applied; asserts (`37`) pass; only the 6 table ACL lines for `companies`, `clients`, `deals` differ from S0 (intended: grants not restored); reapply reproduces S1 exactly; suites pass again |
| 0009 step 4 alone (path H) | Control fails (PUBLIC and anon hold EXECUTE). After revoke, `38` passes (ensure_rls still enables RLS on a new table), and suite 34 passes (anon RPCs intact) |
| 0009 full proposal (path E) | Suites 33 (post), 34 (pre and post), 35 pass. Expected controls: 33 pre fails, 34 negative control fails |
| 0005 verify-only (replica) | Passes on the production-shaped replica. Negative control (index dropped) fails with the expected message |
| 0005 verify-only (production) | No exception raised (read-only; `NOTICE` text not shown by the tool) |
| Production privilege inventory | 56 public tables. anon, authenticated and service_role each hold all 8 table privileges on all 56. PUBLIC holds none |
| Production advisors | Security 45, performance 108, health 0: match `docs/advisor-baseline.md` |
| Production RLS and column state (read-only) | `companies` RLS on with four `companies_*` policies. `clients` and `deals` RLS on with no policies. 0005 columns, FKs and indexes match the repo file |
| Repo RPC callers | `run_workflow_test`, `retry_workflow_run`, `clients_readiness` (server actions). No edge functions in the repo. No repo caller of the anon RPCs |

## 2. FAILED

Findings that fail readiness. None has been fixed on production, and each needs an owner decision or a further change.

| # | Finding | Evidence | Impact |
| --- | --- | --- | --- |
| F1 | Production does not have the app's RPCs | `clients_readiness()` and `retry_workflow_run(uuid)` absent | The Clients readiness gate and workflow retry fail if deployed before 0007 and 0008 |
| F2 | `clients` and `deals` have RLS on but no policies in production | `pg_policies`: none on either table | Authenticated users see no rows there until 0006b. This is a live functional issue that must be confirmed with the owner |
| F3 | anon holds all 8 table privileges on all 56 production tables | Privilege inventory | Until 0009 is applied, anon can write to every table, subject only to RLS (TRUNCATE is not subject to RLS) |
| F4 | `authenticated` holds REFERENCES, TRIGGER and MAINTAIN on all 56 tables | Privilege inventory | Not addressed by 0010 (scope: TRUNCATE). Listed for a follow-up decision |
| F5 | New public functions give anon EXECUTE by default (`postgres` and `supabase_admin`) | `pg_default_acl`, objtype `f` | Any new function is callable by anon until the default is changed. Included in the Support request |
| F6 | `rls_auto_enable()` is executable by `authenticated` | Advisor `authenticated_security_definer_function_executable` | Not addressed by 0009 (which removes PUBLIC and anon only). Owner decision |
| F7 | `plans` gives anon TRUNCATE (before 0010) | Privilege inventory | Fixed by 0010 and 0009 |
| F8 | Migration history does not record GTM migrations; repo numbers collide with production names | `list_migrations` | Deployment cannot rely on the history table. Reconciled in `0005_migration_reconciliation.md` |
| F9 | The earlier plan and notes said 0004b and 0006b were applied to production | Catalog: neither is applied | Corrected in `DEPLOYMENT_PLAN.md`. Production order must start from the catalog |

Failures found during this round's testing, fixed before this report, and recorded for transparency:

- Test 36's pre-0010 control failed for the wrong reason (an array-concatenation error). Fixed with `array_append`. The control now fails on its TRUNCATE checks: 43 violations on the 26-table copy, and 103 on the 56-table copy.
- `gtm_scope_rls.sql` once showed "passed" only because its path was wrong and an empty script ran. Rerun with the real file.
- Path F ran suite 32, which needs 0008. Removed from path F, and documented.
- Path G rollback never saw its confirmation flag: `set_config(..., true)` in autocommit. Fixed by running the steps in one transaction with `psql -1`.
- Path G ran suite 30 after restoring production's anon/authenticated grants on the three tables. Suite 30 asserts the 0006b grant state, which production does not have yet. Removed from path G; it runs in path F.
- The 0005 verify script referenced a column it did not select. Fixed.
- The replica had 26 tables; production has 56. A fixture adds the 30 missing names with production's grant shape.

## 3. BLOCKED

These cannot be completed here. Each needs an owner or Supabase action.

| # | Blocker | Why it cannot be done here | Owner action |
| --- | --- | --- | --- |
| B1 | Production backup not verified | Tools cannot read backup status or run a restore | Confirm a backup inside the window and restore it to a scratch project |
| B2 | External callers of the anon RPCs | Not in this repository | Confirm any worker, webhook or service that calls them or uses the anon key |
| B3 | `supabase_admin` default privileges | Only `supabase_admin` can change them | Send `reviews/0010_support_request.md` to Supabase |
| B4 | Leaked-password protection | Requires the Pro plan or higher (docs). The dashboard path is reported inconsistently | Decide on the plan change. Do not activate a paid feature without approval |
| B5 | Production 0004b, 0006b, 0007, 0007a, 0008 not applied | Approval required; blocked by B1 | Approve each step by name, with its file hash |
| B6 | Production 0009 and 0010 not applied | Approval required; blocked by B1 and B2 | Approve by name |
| B7 | Recording GTM migrations in history | Changes production tracking; not allowed without approval | Owner decision after B1 |
| B8 | App deployment | Blocked by F1 (missing RPCs) | Deploy after steps 7 and 8, or fix F1 |
| B9 | Merge to `main` and deploy | Not authorized | Owner decision |

## 4. NOT TESTED

| # | Item | Why not |
| --- | --- | --- |
| N1 | Any step on production | Not approved, and not allowed by the owner's instructions |
| N2 | Production advisors after any change | No change applied. Predictions are in `docs/advisor-baseline.md` |
| N3 | Production smoke tests (section 11 of the plan) | Require production with an account, and no production change is approved |
| N4 | Behavior on the 30 modelled-only tables with real data | The replica uses empty placeholder tables. No production data was copied |
| N5 | 0010's interaction with the 26 product tables' policies | Those tables are not in the repo; only their privileges were tested |
| N6 | Workers and services outside this repository | Unknown (B2) |
| N7 | `anon` sequence privileges | Recorded only. Not in the 0009 or 0010 scope |
| N8 | Migration 0005a | Not reviewed in this round |
| N9 | Edge functions on production | `list_edge_functions` was not run in this round |
| N10 | Leaked-password behavior in the dashboard | Requires the owner to check the dashboard; not done |
| N11 | Suite 35 (0009 selective rollback) on the 56-table copy | Suite 35 runs only on the 26-table surface (path E). Suite 33 does run on the 56-table copy (path G) |

## 5. Commit and changes in this round

Changed or added (development branch only):

- `supabase/reviews/0005_verify_only.sql`, `0005_migration_reconciliation.md`
- `supabase/reviews/0010_support_request.md`
- `supabase/tests/local/0006b_state_snapshot.sql`, `37_0006b_rollback_asserts.sql`, `38_rls_auto_enable_standalone.sql`
- `supabase/tests/local/compare_0010_acl.py`, `fixtures/0009_step4_only.sql`, `fixtures/production_table_names.sql`
- `supabase/tests/local/run_local.sh` (paths F, G, H added; 36 wired in)
- `supabase/reviews/DEPLOYMENT_PLAN.md` (rewritten), `supabase/reviews/SECURITY_READINESS_REPORT.md`
- `docs/advisor-baseline.md`

The commit that adds this report carries its SHA on `gtm-phase-3-live-crm`. `main` is not changed.

## 6. Recommendation

Do not request production execution yet. Close B1, B2 and F1 first. Then approve steps 4 to 8 in order, with their
verification queries and rollbacks. Decide separately on 0009 and 0010, and on F2, F4, F5 and F6. Then send the Support
request and decide on B4.
