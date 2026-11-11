# 0009 anon hardening review (Task 2)

Status: review only. No production change was made. `0009_anon_hardening_proposed.sql` is not applied
anywhere. Production facts below come from read-only SELECTs against project `siyxkombexmowlggxlrb`
on 2026-11-11.

## Files

| File | Purpose | Run where |
| --- | --- | --- |
| `0009_anon_hardening_inventory.sql` | Read-only inventory: anon table grants, default ACLs, anon-facing policies, anon-callable functions | Production (read-only) |
| `0009_emulated_advisor.sql` | Emulates the three advisor lints in SQL, plus an anon table-grant check the advisor does not report | Replica and production (read-only) |
| `0009_anon_hardening_proposed.sql` | Proposed minimal revokes. NOT APPLIED | Replica only, until gates close |
| `0009_anon_hardening_rollback.sql` | Restores the recorded production ACL | Replica, or production only in an incident |
| `tests/local/33_anon_hardening_tests.sql` | Compatibility tests, run with the proposed script as a prelude | Replica harness |

## Findings

### 1. anon holds INSERT, UPDATE, DELETE or TRUNCATE on 56 public tables (HIGH, defence in depth)

Production gives the `anon` role every table privilege on most of `public`. Each table had RLS on, and
the only anon-facing policy is `plans_read`. Corrected severity: PostgREST does not expose TRUNCATE,
so over the REST API anon can only INSERT, UPDATE and DELETE, and RLS blocks those for every table
except `plans`. The risk is one wrong policy away from exposure. It is not a present direct wipe.

Default ACLs for `postgres` in `public` also grant `anon` all privileges on any new table, so a future
migration inherits the exposure unless the default is changed.

### 2. Hosted advisor is blind to table grants

The hosted advisor reports no table-privilege finding. Only the emulation (block 4 of
`0009_emulated_advisor.sql`) shows the 56 tables. The advisor cannot be relied on for this class.

### 3. Anon-callable SECURITY DEFINER functions (9)

Advisor and emulation agree: 9 functions.

| Function | Keep? | Reason / review item |
| --- | --- | --- |
| `get_landing_page(p_slug)` | Keep | Public landing page. Review: returns only published pages? |
| `record_landing_view(p_slug)` | Keep | Increments views. Review: rate limiting, abuse. |
| `submit_landing_form(p_slug, p_data, p_utm)` | Keep | Public form, writes leads. Review: input size, spam, whether it respects the trigger path. |
| `start_web_chat(p_key, p_name, p_email, p_message, p_consent)` | Keep | Public chat. Review: consent and PII handling. |
| `send_web_chat(p_session, p_message)` | Keep | Review: the session UUID is the only credential. |
| `web_chat_config(p_key)` | Keep | Public widget config. |
| `web_chat_messages(p_session)` | Keep | Returns messages for any session UUID. Review: the UUID is the only check. |
| `unsubscribe_email(p_token)` | Keep | Review: token is a send id; confirm it cannot leak other data. |
| `rls_auto_enable()` | REVOKE | Event-trigger helper. It cannot be called as an RPC meaningfully, but it is still a SECURITY DEFINER function with PUBLIC EXECUTE. Revoke from PUBLIC and anon. |

Revoking `rls_auto_enable` from anon alone is not enough. Its ACL also grants EXECUTE to PUBLIC, so the
proposed script revokes from both.

### 4. Other anon-callable functions

`segment_contacts(p_segment)` is SECURITY INVOKER. It runs with the caller's rights. After the proposed
revoke, anon gets a permission error instead of zero rows. Expected and safe.

### 5. Tables RLS on, no policies (advisor, 3)

`clients`, `deals`, `webhook_events`. Clients is covered in the app by the readiness gate (Task 1).
`deals` and `webhook_events` deny every non-owner read and write. Not changed by this review.

### 6. Out of scope, recorded for follow-up

- 31 further SECURITY DEFINER functions are callable by `authenticated` (advisor 0029). Each needs its
  own review. Not addressed here.
- Leaked password protection is disabled in Auth (advisor). Needs an owner decision in the dashboard.

## Advisor comparison

| Check | Production, hosted advisor | Production, emulation | Replica, emulation (baseline) | Expected after proposed |
| --- | --- | --- | --- | --- |
| rls_enabled_no_policy | 3 | 3 | 0 | 3 (unchanged) |
| anon SECURITY DEFINER executable | 9 | 9 | 0 | 8 (rls_auto_enable removed) |
| authenticated SECURITY DEFINER executable | 32 | 32 | 3 | 32 (unchanged, follow-up) |
| anon INSERT/UPDATE/DELETE/TRUNCATE on tables | not reported | 56 | 12 | 0 (plans keeps SELECT only) |

The emulation matches the hosted advisor exactly on the three lints it covers. The hosted advisor cannot
run on the replica, so the replica column is the emulation only.

## Replica fidelity (read this before trusting the replica results)

- The replica has 20 public tables. Production has roughly 60. The replica does not model the whole schema.
- Before any proposed script runs, replica `clients`, `companies` and `deals` have no anon TRUNCATE.
  Production has all of it. So the replica's anon ACL is narrower than production's on those tables.
- The replica has no `plans` table, no `rls_auto_enable`, and none of the nine landing, web-chat and
  unsubscribe functions. Suite 33 therefore uses a stand-in SECURITY DEFINER function to prove the
  mechanism. It does not prove the real functions still work.
- The rollback round trip (proposed, then rollback, in one rolled-back transaction) reproduces the
  production ACL, not the replica's own prior ACL. Those differ on the tables named above.

## Compatibility checklist

- App code in this repo: all reads go through the signed-in server client (role `authenticated` when
  signed in). The three RPCs it calls (`run_workflow_test`, `retry_workflow_run`, `clients_readiness`)
  are not anon-callable. Result: no in-repo caller depends on anon table grants.
- Not verified: external callers of the landing, web-chat and unsubscribe RPCs, and any edge function
  using the anon key. Each needs an owner check before production apply.
- Definer RPCs run as the owner, so removing anon table grants does not change what they can reach.
  The replica test shows this for a stand-in function.
- `supabase_admin` also has default ACLs that grant anon rights. The proposed script covers only the
  `postgres` default. Any object created by `supabase_admin` needs a separate decision, normally with
  Supabase support.

## Test results (replica, both paths)

- `33_anon_hardening_tests.sql` passes on `gtm_local_live_replay` and `gtm_local_fresh` with the
  proposed script as its prelude.
- Negative control: the same suite without the prelude fails with
  `FAIL anon still holds privileges on workspaces`. The test is not vacuous.
- Rollback round trip: proposed then rollback, inside a rolled-back transaction, restores the recorded
  production state. Zero errors.

## Gates before any production apply

1. Backup status verified and recorded (the production backup must be confirmed before any migration
   receives execution approval).
2. Explicit written approval from the owner for the revoke, naming the script and its hash.
3. Confirm the external-caller question above.
4. A staging or branch check is not available without a paid branch, which is prohibited. Use the
   replica results, and plan a post-apply smoke test of the landing and chat RPCs with an anon request.
5. Apply in a maintenance window inside one transaction (`psql -1` or the migration runner).
6. After apply, rerun `0009_emulated_advisor.sql` and expect the values in the last table column.

## Rollback plan

Trigger: a real caller of a revoked table or function fails, and the fix cannot be shipped quickly.
Action: apply `0009_anon_hardening_rollback.sql` in one transaction. It restores ALL grants to anon on
every public table, the `postgres` default ACL, and EXECUTE on `rls_auto_enable`. Then rerun the
emulated advisor to confirm the pre-apply values.

## Production blockers

- Owner approval for the revoke and the backup check. No production change was made here.
- The external-caller question for landing, web-chat and unsubscribe.
- `supabase_admin` default ACLs.
- Replica divergence (above). A production-faithful test needs a copy of the production catalog.
