# Security readiness report: DigiMithra GTM AI

Project `siyxkombexmowlggxlrb`. Branch `gtm-phase-3-live-crm`. Date 2026-11-11.

**Not ready for production execution.** The development artifacts are reviewed and tested on a local replica. Production
has no approval to change, and it has blockers that prevent the app from working as deployed (section 3). F3, F4, F5 and
F6 remain outstanding and are not addressed by any change in this round.

Scope rule: nothing was applied to production. Read-only queries were run against production. `main` was not merged
into. Nothing was deployed. Each result below is classed PASSED, FAILED, BLOCKED or NOT TESTED. Open limitations that
need an owner decision are in section 2a.

## 1. PASSED

Each item has a reproducible command or query. Results were run again on 2026-11-11 against the current tree.

| Check | Evidence |
| --- | --- |
| Lint | `npm run lint`: exit 0 |
| Type check | `npx tsc --noEmit`: exit 0 |
| Unit tests | `npx vitest run`: 10 files, 147 tests passed |
| Production build | `npm run build` with placeholder public env: exit 0 |
| Production dependency audit | `npm audit --omit=dev`: 0 vulnerabilities |
| Local SQL harness (all paths) | `supabase/tests/local/run_local.sh`: exit 0. 56 passing lines. 5 expected-failure controls, each reported as "observed (expected)" |
| F2 clients and deals role matrix (suite 39) | Passes on paths B (live replay final), fresh final, production-shaped final, 0006b applied and reapplied. Covers read, insert, update, delete and archive for owner, admin, manager, editor, support, analyst, viewer, outsider, cross-tenant and cross-workspace actors; tenant_id and workspace_id change attempts; composite-key refusal (23503); multi-membership RLS refusal. Every denial is verified at the database. Four deliberate mutations (widened clients insert, dropped clients audit, dropped deals archive guard, widened deals delete) were each caught |
| 0006b rollback fail-closed (suite 39b) | Passes after `0006b_down`. Owner and editor read zero clients and deals; inserts fail 42501; updates and deletes affect zero rows; anon has no access. Companies stay readable under the 0006 policies. See R2 for what the rollback does not restore |
| Concurrent task dedupe | `concurrency_task_dedupe.sh`: two real sessions call `run_workflow` with the same dedupe key. Session B waited 1.99 s on session A's lock (the test requires at least 1.5 s). Result: one run, one task, B returns no row |
| Concurrent retry | `concurrency_retry.sh` (existing): one retry row, one task; the second session is refused after waiting on the lock |
| Dependency verification (read-only) | `reviews/0007_0008_0006b_dependency_verify.sql`: 81 checks in one read-only transaction. Fresh replay: all present except `public.conversations` and `public.messages` (R3). Production-shaped replica: all present. Drifted shape (path A, before 0004b): 38 missing. Production: the missing set is listed in `DEPLOYMENT_PLAN.md` section 2 |
| 0010 least privilege, 56-table scope (path G) | Control fails before 0010 with TRUNCATE violations. After 0010, test 36 passes. ACL compare: only TRUNCATE removed, across all 56 tables. Suites 31, 32, 33, 34, `gtm_scope_rls` pass. Rollback refuses without confirmation, restores on confirmation, reapply passes |
| 0006b round trip (path F) | Snapshot S0 before; S1 after apply; suites pass; `0006b_down` applied; asserts (`37`) pass; only the 6 table ACL lines for `companies`, `clients`, `deals` differ from S0 (intended: grants not restored); reapply reproduces S1 exactly; suites pass again |
| 0009 step 4 alone (path H) | Control fails (PUBLIC and anon hold EXECUTE). After revoke, `38` passes (ensure_rls still enables RLS on a new table), and suite 34 passes (anon RPCs intact) |
| 0009 full proposal (path E) | Suites 33 (post), 34 (pre and post), 35 pass. Expected controls: 33 pre fails, 34 negative control fails |
| 0005 verify-only (replica) | Passes on the production-shaped replica. Negative control (index dropped) fails with the expected message |
| 0005 verify-only (production) | No exception raised (read-only; `NOTICE` text not shown by the tool) |
| Production privilege inventory | 56 public tables. anon, authenticated and service_role each hold all 8 table privileges on all 56. PUBLIC holds none |
| Production advisors (baseline) | Security 45, performance 108, health 0: match `docs/advisor-baseline.md` |
| Production RLS and column state (read-only) | `companies` RLS on with four `companies_*` policies. `clients` and `deals` RLS on with no policies. 0005 columns, FKs and indexes match the repo file |
| Repo RPC callers | `run_workflow_test`, `retry_workflow_run`, `clients_readiness` (server actions). No edge functions in the repo. No repo caller of the anon RPCs |

## 2. FAILED

Findings that fail readiness. None has been fixed on production, and each needs an owner decision or a further change.

| # | Finding | Evidence | Impact | Status after this round |
| --- | --- | --- | --- | --- |
| F1 | Production does not have the app's RPCs | `clients_readiness()` and `retry_workflow_run(uuid)` absent on production | The Clients readiness gate and workflow retry fail if deployed before 0007 and 0008 | Still FAILED on production. App side: a missing `retry_workflow_run` now returns "Automation retry is unavailable" and disables the retry button after the first attempt (commit `c3d9fee`). Pre-emptive detection is not added (R5). The Clients module gates its writes on readiness state (existing code, unchanged) |
| F2 | `clients` and `deals` have RLS on but no policies in production | `pg_policies`: none on either table | Authenticated users see no rows there until 0006b. A live functional issue that must be confirmed with the owner | Still FAILED on production. On the replica, 0006b policies and triggers are covered by suite 39 (role matrix) and suite 39b (rollback). See R1 and R2 |
| F3 | anon holds all 8 table privileges on all 56 production tables | Privilege inventory | Until 0009 is applied, anon can write to every table, subject only to RLS (TRUNCATE is not subject to RLS) | Outstanding. Not changed in this round |
| F4 | `authenticated` holds REFERENCES, TRIGGER and MAINTAIN on all 56 tables | Privilege inventory | Not addressed by 0010 (scope: TRUNCATE). Listed for a follow-up decision | Outstanding. Not changed in this round |
| F5 | New public functions give anon EXECUTE by default (`postgres` and `supabase_admin`) | `pg_default_acl`, objtype `f` | Any new function is callable by anon until the default is changed. Included in the Support request | Outstanding. Not changed in this round |
| F6 | `rls_auto_enable()` is executable by `authenticated` | Advisor `authenticated_security_definer_function_executable` | Not addressed by 0009 (which removes PUBLIC and anon only). Owner decision | Outstanding. Not changed in this round |
| F7 | `plans` gives anon TRUNCATE (before 0010) | Privilege inventory | Fixed by 0010 and 0009 | Fixed on the replica. Not applied to production |
| F8 | Migration history does not record GTM migrations; repo numbers collide with production names | `list_migrations` | Deployment cannot rely on the history table. Reconciled in `0005_migration_reconciliation.md` | Open. Owner decision after B1 (B7) |
| F9 | The earlier plan and notes said 0004b and 0006b were applied to production | Catalog: neither is applied | Corrected in `DEPLOYMENT_PLAN.md`. Production order must start from the catalog | Corrected |

Failures found during testing, fixed before this report, and recorded for transparency:

- Test 36's pre-0010 control failed for the wrong reason (an array-concatenation error). Fixed with `array_append`. The control now fails on its TRUNCATE checks: 43 violations on the 26-table copy, and 103 on the 56-table copy.
- `gtm_scope_rls.sql` once showed "passed" only because its path was wrong and an empty script ran. Rerun with the real file.
- Path F ran suite 32, which needs 0008. Removed from path F, and documented.
- Path G rollback never saw its confirmation flag: `set_config(..., true)` in autocommit. Fixed by running the steps in one transaction with `psql -1`.
- Path G ran suite 30 after restoring production's anon/authenticated grants on the three tables. Suite 30 asserts the 0006b grant state, which production does not have yet. Removed from path G; it runs in path F.
- The 0005 verify script referenced a column it did not select. Fixed.
- The replica had 26 tables; production has 56. A fixture adds the 30 missing names with production's grant shape.
- This round, the 0007/0008/0006b dependency probe was first run on a fresh replay and showed `conversations` and `messages` missing. The header had said all were present. The header is corrected (R3).
- E7 (0006b applied to a fresh shape without 0004b) succeeded, because 0004 already creates the archive columns. The dependency on 0004b applies only to the drifted production shape (E8: `record "new" has no field "archived_at"`).

## 2a. Open limitations (owner decision required)

Observed in this round's tests. Each is a design or scope consequence, not a test failure. None is fixed.

| # | Limitation | Evidence | Owner decision needed |
| --- | --- | --- | --- |
| R1 | An editor can edit a deal or client that is archived. Only archive and restore are restricted to admin | Suite 39, archived-row update case (observed, expected) | Accept, or add a policy condition that blocks edits to archived rows for non-admins |
| R2 | `0006b_down` removes the archive guard and the audit trigger on companies. It leaves clients and deals with RLS on and no policies (fail closed). Editors can archive a company after rollback | Suite 39b; `37` asserts the grant state | Accept as a rollback limit (section 7 of the plan), or require a rollback that restores the guard |
| R3 | `messages` and `conversations` are referenced by workflow WhatsApp branches, but no repo migration creates them. They exist in the production baseline and on the production-shaped replica | Dependency probe: missing on a fresh replay only | Add a repo migration or document the baseline dependency |
| R4 | On the drifted production shape, 0006b must run after 0004b. Without the archive columns, company writes fail at write time, not at migration time | Path A control (pre-0004b) and E8 | None beyond the approved order (plan section 3) |
| R5 | The app has no pre-emptive readiness probe for `retry_workflow_run`. The retry button is disabled only after the first retry attempt reveals the missing function | Code review of `c3d9fee`; no read-only readiness RPC exists | Accept, or add a read-only readiness RPC |
| R6 | The real Supabase advisor was not run before and after changes on an isolated project. Pre and post figures come from the local emulated advisor (`reviews/0009_emulated_advisor.sql`) | Not run: no isolated project. Emulated: anon-executable security-definer functions 9 to 8; anon table write-or-truncate grants 18 to 0 | Approve an isolated project or branch to run the real advisor (may incur cost) |

## 3. BLOCKED

These cannot be completed here. Each needs an owner or Supabase action.

| # | Blocker | Why it cannot be done here | Owner action |
| --- | --- | --- | --- |
| B1 | Production backup not verified | Tools cannot read backup status or run a restore | Confirm a backup inside the window and restore it to a scratch project. Blocks every production step |
| B2 | External callers of the anon RPCs | Not in this repository | Confirm any worker, webhook or service that calls them or uses the anon key |
| B3 | `supabase_admin` default privileges | Only `supabase_admin` can change them | Send `reviews/0010_support_request.md` to Supabase |
| B4 | Leaked-password protection | Requires the Pro plan or higher (docs). The dashboard path is reported inconsistently | Decide on the plan change. Do not activate a paid feature without approval |
| B5 | Production 0004b, 0006b, 0007a, 0007 and 0008 not applied | Each needs separate owner approval by name and file hash; blocked by B1 | Approve each step separately (plan section 15) |
| B6 | Production 0009 and 0010 not applied | Each needs separate owner approval by name; blocked by B1 and B2 | Approve each separately |
| B7 | Recording GTM migrations in history | Changes production tracking; not allowed without approval | Owner decision after B1 |
| B8 | App deployment | Blocked by F1 (missing RPCs) | Deploy after steps 7 and 8, or accept the F1 gap |
| B9 | Merge to `main` and deploy | Not authorized | Owner decision |

## 4. NOT TESTED

| # | Item | Why not |
| --- | --- | --- |
| N1 | Any step on production | Not approved, and not allowed by the owner's instructions |
| N2 | Real Supabase advisor before and after any change | No isolated project. See R6 for the emulated comparison |
| N3 | Production smoke tests (plan section 11) | Require production with an account, and no production change is approved |
| N4 | Behavior on the 30 modelled-only tables with real data | The replica uses empty placeholder tables. No production data was copied |
| N5 | 0010's interaction with the 26 product tables' policies | Those tables are not in the repo; only their privileges were tested |
| N6 | Workers and services outside this repository | Unknown (B2) |
| N7 | `anon` sequence privileges | Recorded only. Not in the 0009 or 0010 scope |
| N8 | Migration 0005a | Not reviewed in this round |
| N9 | Edge functions on production | `list_edge_functions` was not run in this round |
| N10 | Leaked-password behavior in the dashboard | Requires the owner to check the dashboard; not done |
| N11 | Suite 35 (0009 selective rollback) on the 56-table copy | Suite 35 runs only on the 26-table surface (path E). Suite 33 does run on the 56-table copy (path G) |
| N12 | Live Clients module and retry flow against a deployed app with a real account | No deployed environment was used. Covered by unit tests (`retry-action.test.ts`, `errors.test.ts`) and the database suites only |

## 5. Changes in this round

Development branch only. `main` is not changed.

- `supabase/tests/local/39_f2_clients_deals_matrix.sql` (new): F2 role matrix, archive guard, audit, moves and mutation checks
- `supabase/tests/local/39b_0006b_rollback_fail_closed.sql` (new): fail-closed behaviour after `0006b_down`
- `supabase/tests/local/concurrency_task_dedupe.sh` (new): two-session dedupe race with measured lock wait
- `supabase/tests/local/run_local.sh` (modified): suites 39 and 39b and the dedupe race wired into paths A, B, D, E, F and the final runs
- `supabase/reviews/0007_0008_0006b_dependency_verify.sql` (new): read-only dependency probe (81 checks)
- `supabase/reviews/SECURITY_READINESS_REPORT.md` and `supabase/reviews/DEPLOYMENT_PLAN.md` (updated)

Earlier rounds (already on the branch): `c3d9fee` (F1 retry-unavailable handling); the 0005 verify and reconciliation files;
the 0010 support request; suites 36, 37, 38; `docs/advisor-baseline.md`.

The commit that adds this round carries its SHA on `gtm-phase-3-live-crm`.

## 6. Recommendation

Do not request production execution yet. Close B1 (backup), B2 (external callers) and F1 (the app RPC gap) first. Then
approve steps 4 to 8 in order, each by name and file hash, with its verification queries and rollback. Decide separately
on 0009 and 0010, and on F2, F3, F4, F5 and F6. Decide on R1 to R6. Then send the Support request and decide on B4.

Application status: not production-ready. F3, F4, F5 and F6 remain outstanding blockers until they are addressed or
explicitly risk-accepted by the owner.
