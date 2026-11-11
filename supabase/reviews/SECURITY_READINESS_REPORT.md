# Security readiness report: DigiMithra GTM AI

Project `siyxkombexmowlggxlrb`. Branch `gtm-phase-3-live-crm`. Revised 2026-11-12 for owner decisions R1 to R6. Results from
2026-11-11 are kept where they still hold.

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
| Local SQL harness (all paths) | `supabase/tests/local/run_local.sh`, 2026-11-12: exit 0. 56 passing lines. 8 results reported as "observed (expected)"; four of them are inverted controls whose suite prints FAILED first |
| F2 clients and deals role matrix (suite 39) | Passes on paths B (live replay final), fresh final, production-shaped final, 0006b applied and reapplied. Covers read, insert, update, delete and archive for owner, admin, manager, editor, support, analyst, viewer, outsider, cross-tenant and cross-workspace actors; tenant_id and workspace_id change attempts; composite-key refusal (23503); multi-membership RLS refusal. Every denial is verified at the database. Four deliberate mutations (widened clients insert, dropped clients audit, dropped deals archive guard, widened deals delete) were each caught |
| 0006b rollback fail-closed (suite 39b) | Passes after `0006b_down`. Owner and editor read zero clients and deals; inserts fail 42501; updates and deletes affect zero rows; anon has no access. Companies stay readable under the 0006 policies. See R2 for what the rollback does not restore |
| Concurrent task dedupe | `concurrency_task_dedupe.sh`: two real sessions call `run_workflow` with the same dedupe key. Session B waited 1.99 s on session A's lock (the test requires at least 1.5 s). Result: one run, one task, B returns no row |
| Concurrent retry | `concurrency_retry.sh` (existing): one retry row, one task; the second session is refused after waiting on the lock |
| Dependency verification (read-only) | `reviews/0007_0008_0006b_dependency_verify.sql`: 99 checks in one read-only transaction, run on production on 2026-11-12 (results in section 2a status). Fresh replay: all present except `public.conversations` and `public.messages` (R3). Production-shaped replica: all present. Drifted shape (path A, before 0004b): 38 missing. Production: the missing set is listed in `DEPLOYMENT_PLAN.md` section 2 |
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
| Archive immutability and restore-only path (R1) | Suites 30, `gtm_scope_rls`, 39 and 39b on the replica paths. An archived company, client or deal rejects update and delete from every role with SQLSTATE 42501, including tenant owners. A direct clear of `archived_at` is refused for admins too. Restore works only through `restore_archived_record`: admin succeeds, editor and another tenant's admin are refused, and each restore writes an audit row with action `restore`. Where RLS hides a row from a role (the editor and the deals delete), the suite checks that the row is still there |
| Rollback protection (R2) | Run by hand on a scratch replica database (`gtm_local_r2`), not in `run_local.sh`. `0004b_down` refuses while the guard is installed. `0006b_archive_guard_down.sql` refuses without `gtm.confirm_drop_archive_guard = 'yes'`, and refuses while an archived row exists. With both met it removes the guard, restore function, grant table and both archive triggers, and `0004b_down` then runs |
| Workflow dependencies and order (R3, R4) | Suite 42 (save-time and run-time refusal without `conversations` or `messages`). Path A's control: 0006b refuses on the drifted schema before 0004b, with the missing archived columns named. Suites 40 and 42 fixtures run with validation off, as documented in each file |
| Concurrency, same run | Retry: one retry row, one task, second session refused after waiting on the lock. Task dedupe: session B waited 2.01 s on session A's lock; one run and one task |
| Production dependency probe (read-only, 2026-11-12) | `begin read only` run on production: 99 checks. Present: the `conversations` and `messages` columns (R3), the 0004 unique keys, the 0007a dedupe index, `run_workflow` and its related functions. Missing: every R1 object, `require_relation`, the 0004b active-row indexes, the clients and deals policies and triggers, the 0007 items, `clients_readiness` and `retry_workflow_run`. This confirms section 2 of the deployment plan |

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
- 2026-11-12: 0006b's preflight required the four `companies_*` policies from 0006. The fresh replay (path B) does not have them, and 0006b's body creates any that are missing, so the requirement was removed.
- 2026-11-12: `guard_archived_immutable` ran as the caller and could not read the revoked grant table. A direct admin update therefore failed with "permission denied", not the read-only message. It is now `SECURITY DEFINER` with a fixed search path.
- 2026-11-12: several suite expectations were written for the old restore-by-update behaviour. They now use `restore_archived_record`. Where RLS hides a row (the editor's deal delete) the check is a zero-row count plus a check that the row survives. A 39b check ran as the owner instead of the editor and has been moved to the editor.
- 2026-11-12: suite 40 failed on databases without `conversations`, because the save-time refusal (R3) stopped its fixture. The fixture now runs with validation off, as suite 42 does, and validation is turned back on.

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

### Status of R1 to R6 (2026-11-12)

| # | Status | Detail |
| --- | --- | --- |
| R1 | Implemented on the replica. Pending owner acceptance and step 5 approval | Archived companies, clients and deals are read-only for every role (42501 on update and delete). `archive_restore_grant` is revoked from `public`, `anon` and `authenticated`. The only restore is `public.restore_archived_record(text, uuid)`: it checks the caller is a tenant owner or admin before it checks the archived state, so it does not reveal archive status to others, and it writes an audit row with action `restore`. The guard is `SECURITY DEFINER` (see the 2026-11-12 fix list). Suites 30, `gtm_scope_rls`, 39 and 39b pass on the replica |
| R2 | Implemented on the replica. Pending owner acceptance | `0006b_down` keeps archive protection: the guard, restore function and grant table stay, and only the clients and deals policies are removed. The removal is a separate script, `rollbacks/0006b_archive_guard_down.sql`, which needs `gtm.confirm_drop_archive_guard = 'yes'` and refuses while archived rows exist (tested 2026-11-12 on a scratch database). The rollback stays partial by design: grants are not restored, and it is not a full rollback |
| R3 | Documented and enforced at run time. Pending owner acceptance | Production has `conversations` and `messages` with every column the branches write (read-only catalog check, 2026-11-12). `set_priority` and `ai_draft` refuse at save time and at run time when the table is missing, so no run writes partial data. The guard is in 0007 (not applied). A fresh replay still lacks the two tables, because no repo migration creates them. Whether the WhatsApp worker outside this repository depends on them is unknown |
| R4 | Enforced by preflight | 0006b stops with SQLSTATE 42P01 before any change when the 0004b columns, scope keys or indexes are missing (control in path A). 0007 stops when 0007a objects are missing. 0008 stops when `clients` or `ws_role` is missing |
| R5 | OPEN | Exact description: "The app has no pre-emptive readiness probe for `retry_workflow_run`. The retry button is disabled only after the first retry attempt reveals the missing function." Proposed resolution: add a read-only readiness RPC, or accept the gap |
| R6 | OPEN | Exact description: "The real Supabase advisor was not run before and after changes on an isolated project. Pre and post figures come from the local emulated advisor (`reviews/0009_emulated_advisor.sql`)." Proposed resolution: approve an isolated Supabase project or branch to run the real advisor before and after each step (may incur cost). The emulated figures are: anon-executable security-definer functions 9 to 8, and anon table write-or-truncate grants 18 to 0 |

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

## 5. Changes in this round (2026-11-12)

Development branch only. `main` is not changed. Nothing was applied to production; the only production action was the
read-only dependency probe.

- `supabase/migrations/0006b_gtm_rls_completion.sql` (changed): R1 archive immutability, restore function and grant table; R2 rollback behaviour; R4 preflight. Hash `5209fccacd6384b24bc02d3c434b851e594e3def1b54e530ed10f0e5ca00dd6a`
- `supabase/migrations/0007_gtm_automation_engine.sql` (changed): R3 save-time and run-time checks; R4 preflight. Hash `83e36c5eb1197592a9198426579af57bed73d1ee22e79c3fc2b4b8ad8dd21a3a`
- `supabase/migrations/0008_gtm_clients_readiness.sql` (changed): R4 preflight. Hash `1136224ee4f9609c1207634a03a0ab8a03e5dac254358863a36a1302de4e5d95`
- `supabase/migrations/0004b_gtm_archive_columns.sql`, `0007a_gtm_workflow_baseline.sql`: unchanged
- `supabase/rollbacks/0006b_down.sql` (rewritten), `supabase/rollbacks/0006b_archive_guard_down.sql` (new), `supabase/rollbacks/0004b_down.sql` (guard check added)
- `supabase/tests/local/42_workflow_dependency_guard.sql` (new, R3), `39`, `39b`, `37`, `30`, `40`, `0006b_state_snapshot.sql`, `gtm_scope_rls.sql`, `run_local.sh` (updated)
- `supabase/reviews/0007_0008_0006b_dependency_verify.sql` (99 checks; R1, R3 and R4 objects added; production header updated)
- `supabase/reviews/DEPLOYMENT_PLAN.md` and this report (updated)

Quality gates on 2026-11-12: `npm run lint` exit 0; `npx tsc --noEmit` exit 0; `npx vitest run` 10 files, 147 tests pass;
`npm run build` exit 0 (placeholder public env); `npm audit --omit=dev` 0 vulnerabilities.

Earlier round (2026-11-11):

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
on 0009 and 0010, and on F2, F3, F4, F5 and F6. Accept or reject R1 to R4 (implemented on the replica), and decide R5 and
R6 (open). Then send the Support request and decide on B4.

Application status: not production-ready. F3, F4, F5 and F6 remain outstanding blockers until they are addressed or
explicitly risk-accepted by the owner.
