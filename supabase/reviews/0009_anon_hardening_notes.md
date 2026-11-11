# 0009 anon hardening review (Task 2)

Status: review only. No production change was made. `0009_anon_hardening_proposed.sql` is not applied
anywhere. Production facts below come from read-only SELECTs against project `siyxkombexmowlggxlrb`
on 2026-11-11. Nothing in this review writes to production.

## Files

| File | Purpose | Run where |
| --- | --- | --- |
| `0009_anon_hardening_inventory.sql` | Read-only inventory: anon table grants, default ACLs, anon-facing policies, anon-callable functions | Production (read-only) |
| `0009_emulated_advisor.sql` | Emulates the advisor lints in SQL, plus an anon table-grant check the advisor does not report | Replica and production (read-only) |
| `0009_anon_hardening_proposed.sql` | Proposed revokes. Records the pre-state in `app_private.gtm_0009_anon_baseline` first. NOT APPLIED | Replica only, until gates close |
| `0009_anon_hardening_rollback.sql` | Selective rollback. Restores only the named tables and privileges recorded in the baseline. TRUNCATE is refused | Replica, or production only in an incident |
| `tests/local/00b_production_surface.sql` | Production-shaped replica layer (tables, columns, grants, policies, function bodies and ACLs, event trigger) | Replica harness |
| `tests/local/fingerprint_surface.sql`, `columns_surface.sql`, `fixtures/production_digests.expected` | Catalog fidelity gates: the replica must match production's digests | Replica harness |
| `tests/local/33_anon_hardening_tests.sql` | Hardening checks, run with the proposal as prelude | Replica harness |
| `tests/local/34_anon_rpc_compat_tests.sql` | Anon RPC compatibility: landing page, landing form, web chat, unsubscribe, plans, ensure_rls. Runs before and after the proposal | Replica harness |
| `tests/local/35_anon_rollback_tests.sql` | Selective rollback checks | Replica harness |

## Findings

### 1. anon holds every table privilege on most of `public` (HIGH, defence in depth)

Production grants the `anon` role INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN and
SELECT on 56 public tables (emulation, `0009_emulated_advisor.sql` block 4). RLS is the only thing stopping
writes, and the only anon-facing policy is `plans_read`. PostgREST does not expose TRUNCATE, so over the Data
API anon can reach INSERT, UPDATE and DELETE only, and RLS blocks those on every table except `plans`. The
exposure is one wrong policy away from a write. It is not a present direct wipe.

### 2. The default ACLs give anon everything on new objects (HIGH, process risk)

Checked read-only (`pg_default_acl`, schema `public`):

| Default owner | Objects | anon receives |
| --- | --- | --- |
| `postgres` | tables | ALL (arwdDxtm) |
| `postgres` | functions | EXECUTE (explicit, not via PUBLIC) |
| `postgres` | sequences | SELECT, UPDATE, USAGE |
| `supabase_admin` | tables | ALL (arwdDxtm) |
| `supabase_admin` | functions | EXECUTE |

The proposal changes only the `postgres` table default. See section "supabase_admin requirement" for the rest.

### 3. The hosted advisor is blind to table grants

The hosted advisor reports no table-privilege finding. Only the emulation shows finding 1.

### 4. Anon-callable SECURITY DEFINER functions (9)

Advisor and emulation agree: 9 functions. Each was reviewed against its production definition (the
bodies were fingerprinted, see "Replica fidelity").

| Function | Decision | Reason / review item |
| --- | --- | --- |
| `get_landing_page(p_slug)` | Keep | Returns published pages only (`status = 'published'`). Tested for a draft page. |
| `record_landing_view(p_slug)` | Keep | Increments a counter. Abuse: no rate limit in the body. Owner review. |
| `submit_landing_form(p_slug, p_data, p_utm)` | Keep | Public form. 8000-char payload limit, consent required, 30 submissions per 10 minutes per page. Tested for consent, required fields and draft pages. |
| `start_web_chat(p_key, p_name, p_email, p_message, p_consent)` | Keep | Public chat. 60 conversations per 10 minutes per workspace. Tested for an unknown key. |
| `send_web_chat(p_session, p_message)` | Keep | The session UUID is the only credential. 2000-char limit, 20 messages per 10 minutes. Tested for an unknown session. |
| `web_chat_config(p_key)` | Keep | Public widget config (business name and greeting). Tested. |
| `web_chat_messages(p_session)` | Keep | Returns inbound and outbound messages for any session UUID, excluding AI drafts, max 200. The UUID is the only check. Owner review. |
| `unsubscribe_email(p_token)` | Keep | The `email_sends.id` is the token. Clears marketing consent and returns the business name only. Tested for an unknown token. |
| `rls_auto_enable()` | REVOKE from PUBLIC and anon | Event-trigger helper. It has PUBLIC EXECUTE in production, so revoking from anon alone does nothing. The `ensure_rls` event trigger still runs it (suite 34, section 7). |

### 5. Other anon-callable functions

`segment_contacts(p_segment)` is SECURITY INVOKER. After the proposal, anon gets a permission error instead of
zero rows. Expected and safe.

### 6. Tables with RLS on and no policy (advisor, 3)

`clients`, `deals`, `webhook_events`. Clients is covered in the app by the readiness gate (Task 1).
`deals` and `webhook_events` deny every non-owner read and write. Not changed by this review.

### 7. NEW: `plans` gives anon TRUNCATE (HIGH, defence in depth)

Production `plans` (checked read-only): primary key `(id)`, RLS on, one policy `plans_read`
(SELECT, roles anon and authenticated, `USING true`), and anon holds ALL on the table, including TRUNCATE.
RLS does not filter TRUNCATE, so the write policies are the only thing between anon and an empty pricing table
over a direct connection. The proposal resets anon to SELECT only. Suite 35 checks that TRUNCATE stays off.

### 8. NEW: `authenticated` keeps TRUNCATE on most tables (HIGH, cross-tenant, owner decision)

Checked read-only: `authenticated` holds ALL on the 10 surface tables and on `plans`, including TRUNCATE.
TRUNCATE is not subject to RLS, so a signed-in user of one tenant could truncate another tenant's rows if they
could run TRUNCATE at all. The Data API does not expose it, so this is not reachable over PostgREST today.

Scope after the GTM migrations (read from the migration files, not yet tested on the replica):

- `companies`, `clients`, `deals`: 0006b revokes ALL from anon and authenticated, then grants back SELECT, INSERT,
  UPDATE and DELETE to authenticated. TRUNCATE is removed for authenticated there.
- `workflows`, `workflow_versions`, `workflow_runs`, `workflow_steps`, `notifications`: 0007 revokes from anon only,
  so authenticated keeps TRUNCATE.
- Every other public table (leads, contacts, conversations, messages, landing_pages, pipeline_stages, workspaces,
  consent_records, email_sends, form_submissions, plans, and the rest): authenticated keeps TRUNCATE.

The proposal does not change `authenticated`. Recommendation, needing an owner decision: revoke TRUNCATE from
`authenticated` (and anon) on every tenant table in a separate reviewed migration, with a replica test that the app
paths still work. Not included in 0009.

### 9. NEW: production `contacts.company_id` and `leads.company_id` already exist

The column digests of the production catalog match the replica only after migration 0005 has added those two
columns. Migration 0005 runs `alter table public.contacts add column company_id uuid;` without `if not exists`,
so it fails on production as written. The deployment plan records 0002 to 0005 as already present in the live
catalog and requires a verification query before any step is skipped. Do not re-run 0005 on production.

### 10. Out of scope, recorded for follow-up

- 32 SECURITY DEFINER functions are executable by `authenticated` (advisor). Each needs its own review.
- Leaked password protection is disabled in Auth (advisor). Needs an owner decision in the dashboard.

## Proposed revokes: review of each step

| Step in `0009_anon_hardening_proposed.sql` | Keep? | Evidence |
| --- | --- | --- |
| 0. Record the anon baseline in `app_private.gtm_0009_anon_baseline` | Keep | Insert-only, `on conflict do nothing`. The rollback reads only this table. |
| 1. `revoke all on table ... from anon` for every table in `public` | Keep | Suite 33 passes after it. Suite 34 passes after it: every RPC and the landing form still work. |
| 2. `alter default privileges for role postgres ... revoke all on tables from anon` | Keep | Stops new `postgres` tables from granting anon anything. Does not cover `supabase_admin` (below). |
| 3. `grant select on plans to anon` (after step 1) | Keep | Restores the one intentional read. Suite 34 section 6 reads `plans` as anon. Suite 33 checks no TRUNCATE. |
| 4. `revoke execute on function rls_auto_enable() from public, anon` | Keep | Suite 34 section 7: a new table still gets RLS enabled after the revoke. |
| Not included: revoke anon EXECUTE on the 8 landing and web-chat RPCs | Not revoked | Anonymous visitors need them. Each has a review item in section 4. |
| Not included: revoke `authenticated` TRUNCATE | Not revoked | Owner decision, finding 8. |
| Not included: function default EXECUTE for anon (postgres) | Not revoked | Would require future anon RPCs to be granted explicitly. Owner decision. |

## supabase_admin requirement (for Supabase support)

`supabase_admin` has default table privileges in `public` that give `anon` ALL on new tables and EXECUTE on new
functions (finding 2). Only `supabase_admin`, or a role that can `SET ROLE` to it, can change those defaults.
The migration role `postgres` cannot. The exact statement, for Supabase support to run after approval:

    alter default privileges for role supabase_admin in schema public revoke all on tables from anon;

If the owner also wants functions covered, the same support request should include:

    alter default privileges for role supabase_admin in schema public revoke execute on functions from anon;
    alter default privileges for role postgres in schema public revoke execute on functions from anon;

The second `postgres` statement is a decision, not a fix: every future anon-facing RPC must then be granted
explicitly. It is not in the proposal.

## Rollback (redesigned)

The earlier rollback restored ALL grants to anon on every public table, the `postgres` default ACL and EXECUTE on
`rls_auto_enable`. That is the indiscriminate restore the review rejects, so it is replaced.

The new `0009_anon_hardening_rollback.sql`:

- restores nothing unless the operator names tables (`gtm.restore_anon_tables`) and privileges
  (`gtm.restore_anon_privileges`), and both must be set;
- restores only privileges the baseline recorded for anon on the named table;
- allows only SELECT, INSERT, UPDATE and DELETE. It refuses TRUNCATE, REFERENCES, TRIGGER and MAINTAIN;
- refuses any table that was not recorded as anon-held, and refuses grant-option restores;
- never restores the default privileges (postgres or supabase_admin) and never restores `rls_auto_enable`
  EXECUTE. Both would re-open everything the proposal closed. Doing either is a separate, documented decision.

Incident procedure: identify the one caller that fails, name its table and the single privilege it needs, run the
rollback with those inputs in one transaction, and then fix the caller so the grant can be removed again.

## Replica fidelity

`tests/local/00b_production_surface.sql` builds a production-shaped layer on top of the base schema. It is checked
against production by catalog digests, and the harness stops if they differ:

| Check | Production digest | Replica digest |
| --- | --- | --- |
| policies (36 on 10 tables) | `752b9d5f…` | `752b9d5f…` |
| table grants (320) | `ededfd3c…` | `ededfd3c…` |
| function bodies (10, normalised whitespace) | `27a0e828…` | `27a0e828…` |
| function ACLs (10) | `76a965d8…` | `76a965d8…` |
| column sets (12 tables, checked after 0005) | per table in `fixtures/production_digests.expected` | identical |

Not reproduced, on purpose: foreign keys, the other ~45 production tables, the Supabase-managed `pgrst_*` and
`issue_*` event triggers, and production's other migration history. The advisor counts on the replica therefore
differ from production:

| Lint | Production (hosted and emulated) | Replica before 0009 | Replica after 0009 | Production expected after 0009 |
| --- | --- | --- | --- | --- |
| rls_enabled_no_policy | 3 | 0 | 0 | 3 (unchanged) |
| anon SECURITY DEFINER executable | 9 | 9 | 8 | 8 |
| authenticated SECURITY DEFINER executable | 32 | 12 | 12 | 32 (unchanged) |
| anon table INSERT/UPDATE/DELETE/TRUNCATE | 56 tables | 18 tables | 0 | 0 |

The replica is not a copy of the whole catalog, so these counts do not transfer. The proposal's effect on the
lints that the replica does model (anon SECURITY DEFINER count, anon table privileges) does match what is expected.

## Test results (replica, all paths)

Harness: `tests/local/run_local.sh`, exit 0.

- `gtm_local_live_replay` and `gtm_local_fresh`: suites 30 to 33, 40, 41, 50 and `gtm_scope_rls.sql` pass.
- `gtm_local_prod_surface` (production-shaped):
  - fidelity gates pass (fingerprint after 00b, columns after 0005);
  - 33 fails before 0009 (expected: anon still holds privileges on `conversations`);
  - 34 fails when anon loses the landing form RPC (negative control, expected: permission denied);
  - 34 passes before and after 0009 (compatibility);
  - 33 passes after 0009;
  - 35 passes (selective rollback restores exactly one SELECT and nothing else);
  - the rollback refuses TRUNCATE (expected failure);
  - 30, 31, 32, 40, 41, 50 and `gtm_scope_rls.sql` pass on the surface.
- Concurrency retry (path D): passes.
- Rollback round trip for 0007 (path C): passes.

## Gates before any production apply

1. Backup status verified and recorded. The backup cannot be checked with the tools available here; it is a
   blocker.
2. Explicit written approval from the owner for each revoke, naming the script and its SHA-256.
3. The external-caller question for the landing, web-chat and unsubscribe RPCs (owner check).
4. A branch or staging copy is not available without a paid resource, which is prohibited. The replica is the
   test environment. Plan a post-apply smoke test of the landing and chat RPCs with an anonymous request.
5. Apply in a maintenance window inside one transaction (`psql -1` or the migration runner).
6. Re-run `0009_emulated_advisor.sql` and compare with the "Production expected after 0009" column.

## Production blockers

- Owner approval for the revoke, and the backup check. No production change was made.
- External callers of the landing, web-chat and unsubscribe RPCs (owner check).
- `supabase_admin` default ACLs: Supabase support (statement above).
- `authenticated` TRUNCATE on tenant tables other than companies, clients and deals (finding 8): owner decision.
- Migration 0005 is not re-runnable on production as written (finding 9).
