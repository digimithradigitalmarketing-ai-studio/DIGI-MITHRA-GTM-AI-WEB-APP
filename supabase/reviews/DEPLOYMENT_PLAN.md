# GTM deployment plan (production project `siyxkombexmowlggxlrb`)

Status: PLAN ONLY. Nothing in this document has been run against production. No production migration, privilege
change, rollback or deployment is approved. This revision replaces the 2026-11-10 plan, whose live-state table was wrong
(it said 0004b and 0006b had run; the catalog shows they have not).

Revised 2026-11-12 for owner decisions R1 to R4 (archive immutability, rollback safety, workflow dependencies, migration
order). Verified on the local replica (section 8). Production has not changed in this revision.

Sources of truth:
- Production state: read-only queries on 2026-11-11 (catalog, `list_migrations`, `get_advisors`). Recorded in
  `reviews/0005_migration_reconciliation.md` and `docs/advisor-baseline.md`.
- Rehearsal: `tests/local/run_local.sh` on a local Postgres 17 replica. Production-shaped, not production. Path meanings
  are in section 8.

## 1. Prerequisites (all must be true before the first production statement)

| # | Prerequisite | Evidence required | Status (2026-11-11) |
| --- | --- | --- | --- |
| P1 | Owner approval for each step, naming the file and its SHA-256 | Written approval | Not requested |
| P2 | Verified backup covering the window, with a restore test | Backup ID, time, restore result | BLOCKER: not verified. Tools here cannot read backup status |
| P3 | Live catalog matches the expected state (step C0) | Query output compared with `tests/local/fixtures/production_digests.expected` | Policies, grants, function bodies and ACLs match the replica surface. Columns of the GTM tables match. Migration history does not (section 2) |
| P4 | External callers of the anon RPCs are known | Owner confirmation | BLOCKER: not confirmed. The repo has no caller (section 6) |
| P5 | Maintenance window agreed, with no app deploy in the same window | Owner confirmation | Not agreed |
| P6 | Support decision on `supabase_admin` default privileges | Support ticket (draft in `reviews/0010_support_request.md`) | Drafted, not sent |
| P7 | The app's RPC dependencies exist in production before the app is deployed | Catalog check: `clients_readiness()`, `retry_workflow_run(uuid)` | BLOCKER: both absent (section 2) |

## 2. Live state against the repo migrations

Read-only, 2026-11-11.

| Repo migration | Live catalog evidence | Action |
| --- | --- | --- |
| 0002 `gtm_scope_keys` | `UNIQUE (tenant_id, workspace_id, id)` on `companies`, `clients`, `deals` | Applied. VERIFY ONLY |
| 0003 `gtm_scoped_crm_foreign_keys` | Scoped FKs present and validated (`landing_pages_scope_campaign_fkey`, `leads_scope_*`, `deals_scope_*`, `tasks_scope_*`) | Applied. VERIFY ONLY |
| 0004 `gtm_companies_clients_deals` | Tables present | Applied in part. VERIFY ONLY |
| 0004b `gtm_archive_columns` | **No** `archived_*` columns on `companies`, `clients`, `deals` | **NOT applied. RUN (step 4)** |
| 0005 `gtm_company_links` | `contacts.company_id`, `leads.company_id` (uuid, nullable); scoped FKs validated with `ON DELETE SET NULL (company_id)`; both partial indexes | Applied. **VERIFY ONLY** with `reviews/0005_verify_only.sql`. Do not re-run its DDL |
| 0005a `contacts_leads_baseline` | Not reviewed in this round | Unknown. Not run |
| 0006 `gtm_rls_triggers` | Partial: RLS on the three tables; four `companies_*` policies; no `clients_*` or `deals_*` policies; no triggers | Partial. Completed by 0006b. Do not re-run |
| 0006b `gtm_rls_completion` | **No** `clients_*` or `deals_*` policies; no `guard_archive`; no `sync_deal_status`; no triggers on the three tables | **NOT applied. RUN (step 5)** |
| 0007a `gtm_workflow_baseline` | `run_workflow_test(uuid,jsonb)` and `cancel_workflow_run(uuid)` present | Partial. RUN for parity (step 6). Confirm the `run_workflow` body md5 is unchanged |
| 0007 `gtm_automation_engine` | **No** `retry_workflow_run(uuid)`, `workflow_runs.retry_of`, `tasks.automation_key`, `trg_validate_definition` | **NOT applied. RUN (step 7)** |
| 0008 `gtm_clients_readiness` | **No** `clients_readiness()` | **NOT applied. RUN (step 8)** |
| 0009 anon hardening (proposed) | anon holds all 8 table privileges on all 56 tables | Not applied. Step 9, separate approval |
| 0010 least privilege (proposed) | authenticated and anon hold TRUNCATE on all 56 tables | Not applied. Step 10, separate approval |

**Migration history.** `list_migrations` returns 20 rows: the base product's `20261020…` history and
`digimithra_0001_organizations_membership`. No repo GTM migration is recorded. Repo numbers collide with production
names (for example `0005_cron_publisher` vs `0005_gtm_company_links`). The reconciliation is in
`reviews/0005_migration_reconciliation.md`. Nothing is written to `supabase_migrations.schema_migrations` by this plan.

**Application dependency (blocker).** `src/lib/crm/readiness.ts` calls `rpc("clients_readiness")` and
`src/app/(app)/automations/actions.ts` calls `rpc("retry_workflow_run")`. Neither exists on production. Deploying the app
before steps 7 and 8 would break those features.

## 3. Migration dependency order

```
C0  catalog check (read only) and reviews/0007_0008_0006b_dependency_verify.sql (read only)
4   0004b_gtm_archive_columns            needs 0004 objects. Must precede 5 on the drifted production shape (R4)
5   0006b_gtm_rls_completion             needs 4 (archive guard reads archived_at) and the four companies_* policies
6   0007a_gtm_workflow_baseline          parity baseline; needed by 7 (workflows tables)
7   0007_gtm_automation_engine           needs 6. Does not touch companies, clients or deals, so independent of 4 and 5
8   0008_gtm_clients_readiness           needs only clients and ws_role. Independent of 4-7. Until 5 creates the clients
                                         policies, readiness returns not_configured: expected, not an error
9   0009_anon_hardening                  after 4-8 verified; the privilege change is independent of 4-8's objects
10  0010_gtm_least_privilege             after 9 (9 removes anon's privileges; 10 removes authenticated's TRUNCATE)
```

Dependencies proved on the replica (2026-11-11): 0007 fails without 0007a (`workflows` missing); 0008 applies without 0004b,
0006b, 0007a or 0007; 0007a and 0007 apply without 0004b or 0006b. The only ordering constraint that fails at write time is
4 before 5 on the drifted production shape (R4).

Preflights (2026-11-12). 0006b stops with SQLSTATE 42P01 before any change if the 0004b columns, the scope keys or the
active indexes are missing. 0007 stops if the 0007a tables, `run_workflow`, `require_ws_role` or the dedupe index are
missing. 0008 stops if `clients` or `ws_role` is missing. Each message names the missing objects.

Verify-only, never run: `0002`, `0003`, `0004`, `0005` (use `0005_verify_only.sql`), `0005a`, `0006` (partial).
Review-only, not migrations: `0006c_rls_review.sql`, `0009_anon_hardening_notes.md`.

Note on order: `0006b` must run after `0004b` on the drifted production shape. The harness path A runs them the other way to
reproduce the failure; that order is not a deployment order. The probe `reviews/0007_0008_0006b_dependency_verify.sql`
checks the presence of every object these steps need, and is read-only.

## 4. Verify-only migrations and production schema checks

**0005 (verify only).** Run `reviews/0005_verify_only.sql` on production. It is read-only and raises on any mismatch.
Result on 2026-11-11: no exception (the read-only tool does not show `NOTICE` text, so the pass is inferred from the
absence of an error). Negative control on the replica: dropping `leads_scope_company_idx` makes it fail.

**Step C0 (before any change).**

```sql
-- Archive drift (must be empty before step 4)
select table_name, column_name from information_schema.columns
 where table_schema='public' and table_name in ('companies','clients','deals')
   and column_name in ('archived_at','archived_by');                     -- expect no rows

-- 0006b not yet applied (must be zero before step 5)
select count(*) from pg_policies where schemaname='public' and tablename in ('clients','deals');   -- expect 0

-- App RPC dependencies (must be false before step 8, true after)
select to_regprocedure('public.clients_readiness()') is not null;          -- expect false now
select to_regprocedure('public.retry_workflow_run(uuid)') is not null;     -- expect false now
```

Then run `tests/local/fingerprint_surface.sql` and `tests/local/columns_surface.sql` and compare with
`production_digests.expected`. Any difference stops the plan.

**Dependency probe (read-only, C0 and after each step).** Run `reviews/0007_0008_0006b_dependency_verify.sql` on production.
It runs in one `begin read only` transaction and returns one row per check (99 checks). Observed on 2026-11-12 (read-only,
production), the missing set
in section 2 (archive columns, `guard_archive`, `sync_deal_status`, `clients_read`, `deals_read`, `trg_deal_status`,
`retry_workflow_run`, `clients_readiness`, `validate_workflow_definition`, `tasks.automation_key`,
`workflow_runs.retry_of`, `workflow_runs.attempt`, and the two unique indexes). After each step, the missing set may
shrink only by that step's objects. Any other change stops the plan. The probe's `conversations` and `messages` items are
expected to be present on production (R3).

## 5. Ordered steps

Each step runs in one transaction (`psql -1`, or the runner's transaction). Stop at the first unexpected result.

**Approval.** Each step 4 to 10 needs its own written owner approval, naming the file and its SHA-256 (section 15). No step
is batched under another step's approval. The hashes are those of the files at this commit; if a file changes, its
approval is void.

**Step 4, 0004b_gtm_archive_columns.sql.** Adds `archived_at` and `archived_by` and the active-row indexes.
Idempotent (replica path B runs it twice). Rollback: `rollbacks/0004b_down.sql`, which must run after 0006b is rolled back.
Verify: the archive-drift query returns six rows.

**Step 5, 0006b_gtm_rls_completion.sql.** Revokes ALL on the three tables from anon and authenticated, then grants
SELECT, INSERT, UPDATE and DELETE to authenticated. Adds the clients and deals policies, `guard_archive`,
`guard_archived_immutable`, `restore_archived_record`, `archive_restore_grant`, `sync_deal_status` and their triggers.
Its preflight refuses before any change if 0004b is missing (R4). Rollback: `rollbacks/0006b_down.sql`, tested in path F
(section 8). Known limit: the rollback does not restore grants, by design (section 7). Verify: `clients` and `deals` each
have policies, and `trg_archive_immutable` exists on all three tables.
R1 (archived records are read-only for every role; restore only through `public.restore_archived_record`, for tenant owners
and admins, audited) and R2 (`0006b_down` keeps the archive guard; its removal is a separate script,
`rollbacks/0006b_archive_guard_down.sql`) are implemented and tested on the replica. Their status is in the security report,
section 2a. Owner acceptance is needed before this step is approved.

**Step 6, 0007a_gtm_workflow_baseline.sql.** Parity baseline. Verify the `run_workflow` body md5 is unchanged.
No rollback file. Recovery is a restore from backup.

**Step 7, 0007_gtm_automation_engine.sql.** Requires step 6 (`workflows` must exist); its preflight stops if it is missing. `set_priority` and `ai_draft` refuse at save
time and at run time when `conversations` or `messages` is absent, so no run writes partial data (R3). Revokes ALL on workflow tables from anon; revokes EXECUTE on
`run_workflow_test`, `cancel_workflow_run`, `retry_workflow_run` from PUBLIC and anon. Rollback:
`rollbacks/0007_down.sql`, round-trip tested in path C.

**Step 8, 0008_gtm_clients_readiness.sql.** Needs only `clients` and `ws_role`; independent of steps 4 to 7. Creates `clients_readiness()`, SECURITY INVOKER, `search_path ''`. Revokes
PUBLIC and anon. Rollback: `rollbacks/0008_down.sql`; the app then shows "Clients module not configured". Verify:
`has_function_privilege('anon', 'public.clients_readiness()', 'EXECUTE')` is false.

**Step 9, 0009_anon_hardening (separate approval).** Apply `reviews/0009_anon_hardening_proposed.sql` in one transaction.
It records the anon baseline first. Rollback: `reviews/0009_anon_hardening_rollback.sql`, selective only (named tables and
SELECT/INSERT/UPDATE/DELETE). Never a blanket restore. The `rls_auto_enable` step (step 4 of 0009) was tested alone in
path H.

**Step 10, 0010_gtm_least_privilege (separate approval).** Apply `reviews/0010_gtm_least_privilege_proposed.sql` in one
transaction. It revokes TRUNCATE from PUBLIC, anon and authenticated on every public table, and resets the postgres
default ACL for TRUNCATE. Rollback: `reviews/0010_gtm_least_privilege_rollback.sql`, which needs
`gtm.confirm_reopen_truncate = yes` and restores only the recorded TRUNCATE grants. Tested in path G.

## 6. Privilege compatibility requirements

- `authenticated` loses TRUNCATE on all public tables (step 10). No app code, SQL function or trigger uses TRUNCATE
  (checked: repo grep, production function bodies, production triggers). The only TRUNCATE trigger is in the `cron`
  schema.
- `anon` loses all privileges except `SELECT` on `plans` (step 9). The anon RPCs keep EXECUTE:
  `get_landing_page`, `record_landing_view`, `submit_landing_form`, `start_web_chat`, `send_web_chat`,
  `web_chat_config`, `web_chat_messages`, `unsubscribe_email`. Suite 34 checks them with fixtures before and after.
- `authenticated` keeps SELECT, INSERT, UPDATE, DELETE on the tables it uses. The ACL compare in path G confirms this
  across all 56 tables: the only difference is TRUNCATE.
- Not removed in this plan, and listed as findings (section 9): `REFERENCES`, `TRIGGER` and `MAINTAIN` for
  `authenticated` on all tables, and the same privileges for `anon` until step 9 is applied.
- **External callers (P4, unconfirmed).** Nothing in this repository calls the anon RPCs. The repo calls `run_workflow_test`,
  `retry_workflow_run` and `clients_readiness` from server actions with the user's session. Any worker, webhook or
  other service that calls the anon RPCs or uses the anon key directly is outside this repository and cannot be checked
  here.

## 7. Rollback limitations

| Rollback | Limitation |
| --- | --- |
| 0004b_down | Drops archive columns. Refuses while the archive guard is installed (tested 2026-11-12) |
| 0006b_down | Does not restore grants: anon stays at none, and authenticated stays at DML only (no TRUNCATE, REFERENCES, TRIGGER, MAINTAIN). This is the intended result (path F asserts it). It is not a full restoration. Since 2026-11-12 it keeps the archive guard, the restore function and the grant table, and removes only the clients and deals policies, so clients and deals fail closed (security report R2) |
| 0006b_archive_guard_down | Removes the archive guard, restore function, grant table and both archive triggers. Needs `gtm.confirm_drop_archive_guard = 'yes'` and refuses while any archived row exists. Separate owner approval. Run by hand on a scratch replica database on 2026-11-12 (not in the harness): refusal without the setting, refusal with an archived row, success once the row is gone, and `0004b_down` runs afterwards |
| 0007a | No rollback file. Recovery is a restore from backup (B1) |
| 0007_down | Round-trip tested |
| 0008_down | The Clients module shows "not configured" |
| 0009 rollback | Selective only. Refuses TRUNCATE, REFERENCES, TRIGGER, MAINTAIN. Never restores default ACLs or `rls_auto_enable` |
| 0010 rollback | Restores TRUNCATE to authenticated and anon. This re-opens the exposure. Needs `gtm.confirm_reopen_truncate = yes`. Use only in an incident |

## 8. Harness coverage (local replica, `tests/local/run_local.sh`)

| Path | What it proves | Result on 2026-11-11 |
| --- | --- | --- |
| A | Live replay in production's partial order; pre-0004b drift fails as expected | Pass (controls observed) |
| B | Fresh database; 0004b is idempotent | Pass |
| C | 0007 rollback round trip restores ACL, function body and shape | Pass |
| D | Concurrent retry | Pass |
| E | Production-shaped surface: fingerprints and column digests match production; 0009 suites 33, 34, 35 | Pass |
| F | 0006b round trip: snapshot S0 before, S1 after apply, suites pass, S2 after `0006b_down`, asserts (`37`), only the three tables' ACL lines differ, S3 after reapply equals S1 | Pass. 6 expected ACL diff lines (3 tables x before/after) |
| G | 0010: control fails with 56 tables' TRUNCATE; apply; `36` passes; ACL compare shows only TRUNCATE removed across 56 tables; suites 31, 32, 33, 34, `gtm_scope_rls` pass; rollback refuses without confirmation; rollback restores; reapply passes | Pass |
| H | 0009 step 4 alone: control fails; after the change `38` and `34` pass | Pass |

Suite 30 is run only in path F: it asserts the 0006b grant state and is not part of the 0010 path.
Suite 32 needs 0008, so it runs in paths B and E, not F.

Suite 39 (F2 clients and deals role matrix) runs in path A (final), B (final), E (final), and path F (applied and reapplied).
Suite 39b (fail-closed behaviour after `0006b_down`) runs in path F. Suite 42 (R3: workflow dependency guard) runs in path C.
Path A's R4 control shows 0006b refusing on the drifted schema before 0004b, and the message names the missing archived columns.

Result on 2026-11-12: `run_local.sh` exit 0, 56 passing lines, 8 results reported as "observed (expected)". Four of those are
inverted controls whose suite prints FAILED first (suites 33 and 34 on the pre-0009 surface, 36 before 0010, and 38 before
step 4). The other four are assertions that a refusal happens (the R4 preflight, two `0006b_down` checks, and the 0010
rollback without confirmation). Concurrency, on the same run: retry (one retry row, one task, second session refused after
waiting on the lock) and task dedupe (session B waited 2.01 s on session A's lock; one run and one task).

## 9. Post-migration RLS verification (read-only)

```sql
-- A. Archive columns present (after step 4): expect 6
select count(*) from information_schema.columns
 where table_schema='public' and table_name in ('companies','clients','deals')
   and column_name in ('archived_at','archived_by');

-- B. RLS enabled and policies present (after step 5): clients and deals must have policies
select c.relname, c.relrowsecurity,
       (select count(*) from pg_policies p where p.schemaname='public' and p.tablename=c.relname) as policies
  from pg_class c where c.relnamespace='public'::regnamespace
   and c.relname in ('companies','clients','deals','workflows','workflow_runs','notifications') order by 1;

-- C. anon holds no table privilege on the GTM tables (after steps 5 and 9): expect false
select c.relname, has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') as anon_any
  from pg_class c where c.relnamespace='public'::regnamespace
   and c.relname in ('companies','clients','deals','workflows','workflow_versions','workflow_runs','workflow_steps','notifications');

-- D. TRUNCATE gone for anon and authenticated on every public table (after step 10): expect 0 rows
select c.relname from pg_class c where c.relnamespace='public'::regnamespace and c.relkind in ('r','p')
   and (has_table_privilege('anon', c.oid, 'TRUNCATE') or has_table_privilege('authenticated', c.oid, 'TRUNCATE'));

-- E. Readiness RPC (after step 8): present; not executable by anon or PUBLIC
select to_regprocedure('public.clients_readiness()') is not null as present,
       has_function_privilege('anon', 'public.clients_readiness()', 'EXECUTE') as anon_exec;   -- true, false
```

Expected after each step, and to be recorded as the new digests: the policy, grant and function-ACL digests change only
where 0006b, 0007, 0008, 0009 and 0010 changed them.

## 10. Backup and recovery verification

- **BLOCKED (B1, P2). Every step is blocked until this is confirmed independently.** The tools available here cannot read
  backup status or run a restore. Owner action: confirm a backup taken inside the window, and run a restore to a scratch
  project before step 4. Record the backup ID, time and restore result.
- Recovery order: first the step's rollback file (section 5), then restore from the verified backup (P2). Do not
  improvise a data repair.
- A write failing with `record "new" has no field "archived_at"` means step 4 was skipped. Run step 4, then continue.

## 11. Smoke tests and recovery actions

Owner, with an existing account, after each window:

1. Sign in. Open the Clients module. The readiness check must return a result, not an error (requires step 8).
2. Open the automations list. Retry on a failed run must work (requires step 7).
3. Anonymous: open a published landing page. Submit nothing. The page must load (`get_landing_page`).
4. Anonymous: the web-chat widget must open its session (`web_chat_config`, `start_web_chat`).
5. Anonymous: an unsubscribe link must work on a test email (`unsubscribe_email`). Use a test record only.
6. Anonymous `GET /rest/v1/leads` with the publishable key must return no rows (requires step 9).

Recovery actions by failure: section 7 for the rollback, section 10 for restore.

## 12. Advisor baseline comparison

Baseline 2026-11-11 (read-only): security 45, performance 108, health 0. Detail in `docs/advisor-baseline.md`.

The real Supabase advisor was not run before or after any change, because no isolated project was approved (security
report R6). The only pre and post figures are from the local emulated advisor (`reviews/0009_emulated_advisor.sql`):
anon-executable security-definer functions 9 to 8, and anon table write-or-truncate grants 18 to 0.

Expected changes, to be verified after each step (predictions, not observations):

| Step | Expected advisor change |
| --- | --- |
| 5 (0006b) | `rls_enabled_no_policy` loses `clients` and `deals`: 3 to 1 |
| 9 (0009) | `anon_security_definer_function_executable`: 9 to 8 (`rls_auto_enable` removed; the other eight are intended anon RPCs) |
| 10 (0010) | No advisor change expected. TRUNCATE is not an advisor lint. Verified by the ACL compare instead |
| 8 (0008) | `authenticated_security_definer_function_executable` count is unchanged (`clients_readiness` is SECURITY INVOKER) |

Any other difference must be explained before the window closes.

## 13. Blockers (open)

1. Backup not verified (P2). Blocks every step.
2. External callers of the anon RPCs unconfirmed (P4). Blocks step 9.
3. Production app RPC dependencies missing (P7): `clients_readiness` (0008) and `retry_workflow_run` (0007). Blocks the app deploy.
4. Production 0006b state: `clients` and `deals` have RLS on and no policies, so authenticated sees no rows there until step 5.
   Blocks the Clients module on production, and is a live functional issue to confirm with the owner.
5. Leaked-password protection disabled (Auth). Requires the Pro plan or higher (section 14).
6. `supabase_admin` default privileges need Supabase Support (P6).
7. Production migration history does not record the GTM migrations (reconciliation report). Recording them is an owner decision
   after a verified backup.
8. Replica is production-shaped, not production: the 56-table scope is modelled with empty placeholder tables, and no data is copied.
9. F3, F4, F5 and F6 are outstanding (security report section 2). The owner has not risk-accepted them.
10. Owner decisions (security report section 2a): R1 to R4 are implemented on the replica and need owner acceptance. R5 and R6 are open.

## 14. Leaked-password protection (research)

- Official docs state: "Leaked password protection is available on the Pro Plan and above."
- The check uses the HaveIBeenPwned Pwned Passwords API (per the Supabase docs).
- The dashboard location is reported differently by secondary sources (Authentication settings, or Passwords / Email
  provider settings). It must be confirmed in the dashboard, not assumed. Activation must be done by the owner.
- Constraint: enabling it may require a paid plan. No paid feature is to be activated without owner approval.
- Compatibility: the setting only affects new signups and password changes. Existing users are not affected.

## 15. Production execution approval

Not requested. Request it only after blockers 1, 2, 3 and 4 are closed or explicitly accepted by the owner. The request
must list each step, its file SHA-256, the C0 output, the verification queries, and each rollback.

Steps awaiting separate owner approval (SHA-256 of the files at this commit, computed 2026-11-12). An approval is void if
its file's hash changes. 0004b, 0007a, 0009 and 0010 are unchanged since 2026-11-11; 0006b, 0007, 0008 and the probe changed.

| Order | Step | File | SHA-256 |
| --- | --- | --- | --- |
| 4 | 0004b_gtm_archive_columns | `supabase/migrations/0004b_gtm_archive_columns.sql` | `af864ae6153cde6356c5fff6f767c4a74f58a9a992b0d1271fab6a8d032f98f6` |
| 5 | 0006b_gtm_rls_completion | `supabase/migrations/0006b_gtm_rls_completion.sql` | `5209fccacd6384b24bc02d3c434b851e594e3def1b54e530ed10f0e5ca00dd6a` |
| 6 | 0007a_gtm_workflow_baseline | `supabase/migrations/0007a_gtm_workflow_baseline.sql` | `d9214fc3d2868cdf0cb0705deb2384e317bdff322acf3334d48ca58100531cac` |
| 7 | 0007_gtm_automation_engine | `supabase/migrations/0007_gtm_automation_engine.sql` | `83e36c5eb1197592a9198426579af57bed73d1ee22e79c3fc2b4b8ad8dd21a3a` |
| 8 | 0008_gtm_clients_readiness | `supabase/migrations/0008_gtm_clients_readiness.sql` | `1136224ee4f9609c1207634a03a0ab8a03e5dac254358863a36a1302de4e5d95` |
| 9 | 0009_anon_hardening (proposed) | `supabase/reviews/0009_anon_hardening_proposed.sql` | `13762ae13ad47be9bdb93f2f59831e773a176e187a4a0dcb56083a9184077d18` |
| 10 | 0010_gtm_least_privilege (proposed) | `supabase/reviews/0010_gtm_least_privilege_proposed.sql` | `af111c235e7d2a9f7f1c0bbad83e4033eef7d66117e205bb3a05cdf94cf8cd75` |
| C0 | Dependency probe (read-only; no approval needed to run) | `supabase/reviews/0007_0008_0006b_dependency_verify.sql` | `27cdf7af0555571e2383e606d5999b273cafa7f52c8bed68ceab46ec98d2c40d` |
| R | Rollback for step 4, if used | `supabase/rollbacks/0004b_down.sql` | `2e478f8d31d5ca0dae460c9d71627b1bd40bfee1438d5c587ac681d9d1684767` |
| R | Rollback for step 5, if used | `supabase/rollbacks/0006b_down.sql` | `76e42bca6d7b22273d1025a247bc1fa25e336d9f40cc294e424f59675373baed` |
| R | Archive-guard removal, separate, if used | `supabase/rollbacks/0006b_archive_guard_down.sql` | `1afc1dc6e04a1d6b270dcd87f4feb1c8cd963a6cef44cfd1b2c31e2308925d35` |

Each approval covers only the named file and hash. If a hash differs at execution, stop and re-approve. Verify-only
items (0002, 0003, 0004, 0005 via `0005_verify_only.sql`) and 0005a (not reviewed) are not in this table.
