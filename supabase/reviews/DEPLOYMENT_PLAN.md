# GTM migration deployment plan (Task 5)

Status: PLAN ONLY. Nothing in this document has been run against production (project `siyxkombexmowlggxlrb`).
The approval needed for production execution is listed at the end. It has not been requested yet, because the
blockers in section 6 are open.

Source of truth for the live state: `tests/local/fixtures/production_digests.expected` and the read-only
catalog checks in section 3. The replica used for rehearsal is `tests/local/run_local.sh`, path E
(`gtm_local_prod_surface`), which reproduces production's policies, grants, function bodies and ACLs, and the
column sets of the GTM-relevant tables.

## 1. Prerequisites (all must be true before the first production statement)

| # | Prerequisite | Evidence required | Status |
| --- | --- | --- | --- |
| P1 | Owner approval for each step, naming the file and its SHA-256 | Written approval in this repository's PR, or the owner's message | Not requested |
| P2 | Verified backup covering the window, with a restore test | Backup ID and time, and the restore result. Tools here cannot read backup status | BLOCKER: not verified |
| P3 | Live catalog matches the expected state (section 3, step C0) | Query output, compared with `fixtures/production_digests.expected` | Checked read-only on 2026-11-11: policies, grants, function bodies and ACLs match. Columns match. Migration history differs as recorded below |
| P4 | External callers of the anon RPCs are known (landing, web chat, unsubscribe) | Owner confirmation | BLOCKER: not confirmed |
| P5 | Maintenance window agreed, and no app deploy in the same window | Owner confirmation | Not agreed |
| P6 | Supabase support decision on the `supabase_admin` default privileges (see `0009_anon_hardening_notes.md`) | Support ticket or owner decision | Not requested. Optional for this plan |

## 2. Live state against the repo migrations

Read-only, 2026-11-11. The live catalog is in the "live partial state" that path A models.

| Migration | Live state | Action in production |
| --- | --- | --- |
| 0002 `gtm_scope_keys` | Objects present (verify) | VERIFY ONLY. Do not re-run unless C-steps show it missing |
| 0003 `gtm_scoped_crm_foreign_keys` | Objects present (verify) | VERIFY ONLY |
| 0004 `gtm_companies_clients_deals` | `companies`, `clients`, `deals` exist. No `archived_at` columns (drift) | VERIFY ONLY. Drift is fixed by 0004b |
| 0005 `gtm_company_links` | `contacts.company_id` and `leads.company_id` exist | VERIFY ONLY. DO NOT RE-RUN: it runs `add column` without `if not exists`, so it fails on the live catalog |
| 0005a `contacts_leads_baseline` | Contacts and leads policies present (guarded in the file) | VERIFY ONLY. Not run |
| 0006 `rls_triggers` | PARTIAL: RLS on `companies`, `clients`, `deals`; four `companies_*` policies | DO NOT RE-RUN. 0006b completes it |
| 0004b `archive_columns` | Missing on `companies`, `clients`, `deals` | RUN (step 4) |
| 0006b `rls_completion` | Not applied | RUN (step 5) |
| 0007a `workflow_baseline` | Live engine present. File is a no-op on live | RUN for parity (step 6) |
| 0007 `automation_engine` | Not applied (per migration history) | RUN (step 7) |
| 0008 `clients_readiness` | Not applied | RUN (step 8) |
| 0009 anon hardening (proposed) | Not applied | SEPARATE APPROVAL, LAST (step 9) |
| 0006c review | Review-only file, not a migration | Not run |

Migration history on production lists `0001_foundation` through `0013_avatars_team_activity` and
`digimithra_0001_organizations_membership`. None of the repo's GTM 0002 to 0008 names appear there, because the
GTM objects were created outside the migration runner. The plan is therefore written against the catalog, not
against the history table.

## 3. Ordered steps

Each step runs in its own transaction (`psql -1` or the migration runner's own transaction). Stop at the first
unexpected result, and go to section 5 for recovery.

### C0. Catalog check before anything runs (read-only)

Run `tests/local/fingerprint_surface.sql` and `tests/local/columns_surface.sql` against production. Compare the
output with `tests/local/fixtures/production_digests.expected`. Also confirm the drift that 0004b fixes:

```sql
select table_name, column_name
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('companies', 'clients', 'deals')
   and column_name in ('archived_at', 'archived_by');
-- Expected before step 4: no rows.
```

Any difference from the expected file stops the plan.

### 4. 0004b_gtm_archive_columns.sql (RUN)

- Dependencies: 0004 objects present (C0).
- Why first: 0006b's archive guard reads `new.archived_at`. Without this column, every write to `companies`,
  `clients` or `deals` fails. The harness shows the failure (`gtm_scope_rls.sql` fails before 0004b).
- Idempotent: the replica runs it twice on the fresh path, and the second run is a no-op.
- Rollback: `rollbacks/0004b_down.sql`. Drops the archive columns. Do not run it after step 5 without also rolling
  back step 5, because the guard then reads a missing column.
- Verify: the query in C0 now returns six rows (three tables, two columns each).

### 5. 0006b_gtm_rls_completion.sql (RUN)

- Dependencies: step 4. Requires the four `companies_*` policies from the partial 0006.
- Effects: revokes ALL on `companies`, `clients`, `deals` from anon and authenticated, then grants SELECT, INSERT,
  UPDATE and DELETE to authenticated. Adds the clients and deals policies, the archive guard and the sync triggers.
- Replica result: suites 30, 31, 32, 40, 41, 50 and `gtm_scope_rls.sql` pass after it on path A (after the drift
  is fixed) and path E.
- Rollback: `rollbacks/0006b_down.sql`. Drops what 0006b added. Test before use: path C covers 0007 only, so
  0006b's rollback is not round-trip tested. This is a gap to close before approval.
- Verify: `select count(*) from pg_policies where schemaname = 'public' and tablename in ('clients','deals');` is
  greater than zero. The readiness check (0008) reports "not configured" until this step is done. That is expected.

### 6. 0007a_gtm_workflow_baseline.sql (RUN, expected no-op on live)

- Dependencies: none beyond the base.
- Header states that every object is guarded and every function is the live definition. Verify the no-op with the
  fingerprint: the `run_workflow` body md5 must not change.
- Rollback: none. It is a baseline. Recovery is a restore from backup (section 5).

### 7. 0007_gtm_automation_engine.sql (RUN)

- Dependencies: step 6.
- Effects: revokes ALL on `workflows`, `workflow_versions`, `workflow_runs`, `workflow_steps`, `notifications` from
  anon. Revokes EXECUTE on `run_workflow_test`, `cancel_workflow_run`, `retry_workflow_run` from PUBLIC and anon, and
  grants authenticated and service_role.
- Replica: path C (rollback round trip) and path E pass. The round trip restores the pre-0007 ACL, function body and
  shape.
- Rollback: `rollbacks/0007_down.sql`, round-trip tested.

### 8. 0008_gtm_clients_readiness.sql (RUN)

- Dependencies: `clients` (step 5).
- Effects: creates `public.clients_readiness()` (SECURITY INVOKER, `search_path ''`), revokes PUBLIC and anon, grants
  authenticated.
- Replica: suite 32 passes on every path, including the authorized and unauthorized cases.
- Rollback: `rollbacks/0008_down.sql`. The app then shows "Clients module not configured" for the Clients module,
  which is the intended failure mode.
- Verify: `select has_function_privilege('anon', 'public.clients_readiness()', 'EXECUTE');` must be `false`.

### 9. 0009 anon hardening (SEPARATE APPROVAL, LAST)

Do not start this step until steps 4 to 8 have passed their verification queries, the owner has approved it by
name, and the blockers in section 6 that concern it are closed.

- Apply `reviews/0009_anon_hardening_proposed.sql` in one transaction. It records the baseline first.
- Verify with `reviews/0009_emulated_advisor.sql` and compare with the table in the notes: anon table privileges
  go to zero (plans keeps SELECT); anon SECURITY DEFINER executable goes from 9 to 8.
- Smoke test (owner, with an existing account, read-only): sign in, open the landing page, submit nothing. Confirm
  an anonymous `GET` of `/rest/v1/leads` with the publishable key returns no rows.
- Rollback: `reviews/0009_anon_hardening_rollback.sql`, selective. Only for a named caller that fails. Never the
  blanket restore.

## 4. Post-deployment verification queries (read-only)

Run after each step, and again after step 9.

```sql
-- A. Drift fixed
select count(*) as archive_columns_present
  from information_schema.columns
 where table_schema='public' and table_name in ('companies','clients','deals')
   and column_name in ('archived_at','archived_by');                  -- expect 6

-- B. RLS on the GTM tables, and policies present
select c.relname, c.relrowsecurity,
       (select count(*) from pg_policies p where p.schemaname='public' and p.tablename=c.relname) as policies
  from pg_class c
 where c.relnamespace='public'::regnamespace
   and c.relname in ('companies','clients','deals','workflows','workflow_runs','notifications')
 order by 1;                                                            -- RLS true on all; clients and deals policies > 0

-- C. anon holds nothing on the GTM tables (after 0006b and 0007)
select c.relname, has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') as anon_any
  from pg_class c
 where c.relnamespace='public'::regnamespace
   and c.relname in ('companies','clients','deals','workflows','workflow_versions','workflow_runs','workflow_steps','notifications');
-- expect false on all rows

-- D. Readiness RPC present, and not executable by anon or PUBLIC
select to_regprocedure('public.clients_readiness()') is not null as present,
       has_function_privilege('anon', 'public.clients_readiness()', 'EXECUTE') as anon_exec;   -- true, false

-- E. Guard and sync functions present
select to_regprocedure('app_private.guard_archive()') is not null as guard,
       to_regprocedure('app_private.sync_deal_status()') is not null as sync;                  -- true, true
```

After step 9: re-run the fingerprint and columns checks, and expect the policy, grant and function-ACL digests to
differ from `production_digests.expected` only where 0006b, 0007 and 0009 changed them. Record the new digests as the
new expected values.

## 5. Recovery

| Failure | Action |
| --- | --- |
| A write fails with `record "new" has no field "archived_at"` | Step 4 was skipped. Run 0004b, then continue |
| Step 5 fails part-way | The transaction rolls back. Re-run from step 4 after the cause is fixed |
| A step succeeds but the app breaks | Run that step's rollback file (section 3). Tested for 0007 and 0008; 0004b, 0006b are not round-trip tested |
| Data loss or a bad write | Restore from the verified backup (P2). Do not improvise a data repair |
| 0009 breaks a real caller | Selective rollback of one table and one privilege (see the notes). Never the blanket restore |

Rollback order is the reverse of the apply order: 0009, then 0008, 0007, 0007a (no rollback), 0006b, 0004b.

## 6. Blockers (open at the time of writing)

1. Backup not verified (P2). Tools available here cannot read backup status. Blocks every step.
2. External callers of the landing, web-chat and unsubscribe RPCs not confirmed (P4). Blocks step 9.
3. `authenticated` keeps TRUNCATE on most tables (notes, finding 8). Owner decision.
4. Migration 0005 cannot be re-run on production as written (notes, finding 9). Plan keeps it VERIFY ONLY.
5. 0006b rollback not round-trip tested. Needs a test before approval.
6. `supabase_admin` default privileges need Supabase support (notes, section "supabase_admin requirement").
7. Replica is production-shaped, not production. Its advisor counts differ (notes, "Replica fidelity").
8. Leaked password protection disabled in Auth (advisor). Owner decision in the dashboard.

## 7. Production execution approval

Not requested. Production execution approval should be requested only after blockers 1 to 6 are closed or explicitly
accepted by the owner. The request must list each step, the file hash, the verification query output from C0, and the
rollback for each step.
