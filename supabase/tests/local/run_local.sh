#!/usr/bin/env bash
# Replays the GTM migrations against a local Postgres 17 replica and runs the RLS tests.
# LOCAL ONLY. It drops and recreates databases named gtm_local_* on the local socket.
# It refuses to run against anything other than a local socket or localhost.
#
# Usage: PGPORT=54329 PGHOST=/tmp ./run_local.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUPA="$(cd "$HERE/../.." && pwd)"           # supabase/
PGHOST="${PGHOST:-/tmp}"
PGPORT="${PGPORT:-54329}"

case "$PGHOST" in
  /*|localhost|127.0.0.1) ;;
  *) echo "refusing: PGHOST must be a local socket or localhost" >&2; exit 1 ;;
esac

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U postgres)

new_db() {
  local name="$1"
  case "$name" in gtm_local_*) ;; *) echo "refusing db name $name" >&2; exit 1 ;; esac
  "${PSQL[@]}" -d postgres -c "drop database if exists $name with (force);"
  "${PSQL[@]}" -d postgres -c "create database $name;"
}

run() { "${PSQL[@]}" -d "$1" -f "$2"; }

# MD5 of the pre-GTM RLS policies, as the H3 check in gtm_scope_rls.sql computes it.
# Must be taken BEFORE any GTM migration runs.
baseline_md5() {
  "${PSQL[@]}" -d "$1" -tA -c "
    select md5(coalesce(string_agg(
      tablename || '|' || policyname || '|' || cmd || '|' || roles::text || '|' ||
      coalesce(qual, '') || '|' || coalesce(with_check, ''), E'\n' order by tablename, policyname), ''))
      from pg_policies
     where schemaname = 'public'
       and tablename not in ('companies', 'clients', 'deals',
                             'workflows', 'workflow_versions', 'workflow_runs', 'workflow_steps', 'notifications');"
}

# Runs one test file inside a single transaction that ends in ROLLBACK, with the
# baseline setting supplied. Returns non-zero if any check raises. The optional tag
# keeps the log of each stage separate, so an expected failure is not overwritten.
run_suite() {
  local db="$1" file="$2" md5="$3" tag="${4:-}" prelude="${5:-}"
  local name="$(basename "$file")"
  local log="$RESULTS/$db.${tag:+$tag.}$name.log"
  {
    echo "begin;"
    echo "select set_config('gtm.baseline_policy_md5', '$md5', false);"
    [ -n "$prelude" ] && cat "$prelude"
    cat "$file"
    echo "rollback;"
  } | "${PSQL[@]}" -d "$db" -f - >"$log" 2>&1 \
    || { echo "FAILED: $db ${tag:+$tag }$name (see $log)" >&2; tail -n 5 "$log" >&2; return 1; }
  echo "passed: $db ${tag:+$tag }$name"
}

base() {
  local db="$1"
  run "$db" "$HERE/00_auth_shim.sql"
  run "$db" "$HERE/01_base_schema.sql"
}

RESULTS="$HERE/results"
mkdir -p "$RESULTS"

# Path A: the live project's history. Migrations 0002 to 0005, then the partial 0006
# state, then the production archive drift, then 0006b, then 0004b. This is what production needs.
new_db gtm_local_live_replay
base gtm_local_live_replay
MD5_A="$(baseline_md5 gtm_local_live_replay)"
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links; do
  run gtm_local_live_replay "$SUPA/migrations/$m.sql"
done
run gtm_local_live_replay "$HERE/02_live_partial_state.sql"
run gtm_local_live_replay "$HERE/02b_live_archive_drift.sql"   # local fixture: matches the live catalog
run gtm_local_live_replay "$SUPA/migrations/0006b_gtm_rls_completion.sql"

# Before 0004b, the drifted schema must fail the suite: guard_archive reads archived_at on writes.
# This check is inverted. The suite passing here would mean the drift is not reproduced.
FAIL=0
if run_suite gtm_local_live_replay "$SUPA/tests/gtm_scope_rls.sql" "$MD5_A" pre-0004b; then
  echo "UNEXPECTED: drifted live schema passed gtm_scope_rls.sql before 0004b" >&2
  FAIL=1
else
  echo "observed (expected): drifted live schema fails gtm_scope_rls.sql before 0004b"
fi

run gtm_local_live_replay "$SUPA/migrations/0004b_gtm_archive_columns.sql"
# Phase 5. 0007a records the live workflow engine (a no-op on production), then 0007 extends it.
run gtm_local_live_replay "$SUPA/migrations/0007a_gtm_workflow_baseline.sql"
run gtm_local_live_replay "$SUPA/migrations/0007_gtm_automation_engine.sql"
run gtm_local_live_replay "$SUPA/migrations/0008_gtm_clients_readiness.sql"

# Path B: a clean database with the same migration files, no partial state and no drift.
# 0004b is a no-op here, which checks that it is idempotent.
new_db gtm_local_fresh
base gtm_local_fresh
MD5_B="$(baseline_md5 gtm_local_fresh)"
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links 0004b_gtm_archive_columns 0006b_gtm_rls_completion; do
  run gtm_local_fresh "$SUPA/migrations/$m.sql"
done
run gtm_local_fresh "$SUPA/migrations/0004b_gtm_archive_columns.sql"   # second apply: must be a no-op
run gtm_local_fresh "$SUPA/migrations/0007a_gtm_workflow_baseline.sql"
run gtm_local_fresh "$SUPA/migrations/0007_gtm_automation_engine.sql"
run gtm_local_fresh "$SUPA/migrations/0008_gtm_clients_readiness.sql"

echo "replay complete: gtm_local_live_replay, gtm_local_fresh"

# The 0007a run_workflow body, renamed run_workflow_legacy. 41 compares it with the new engine. It is loaded
# inside each transaction, so the replicas never keep it.
LEGACY_PRELUDE="$RESULTS/legacy_run_workflow.sql"
sed -n '/^CREATE OR REPLACE FUNCTION app_private.run_workflow(/,/^end \$function\$;/p' \
  "$SUPA/migrations/0007a_gtm_workflow_baseline.sql" \
  | sed 's/app_private\.run_workflow(/app_private.run_workflow_legacy(/' > "$LEGACY_PRELUDE"
grep -q "run_workflow_legacy(p_workflow" "$LEGACY_PRELUDE" || { echo "could not extract the 0007a engine" >&2; exit 1; }

# 0006c review: the webhook fixture plus the review file run first, inside the same
# rolled-back transaction, before the checks in 50_review_0006c_tests.sql.
REVIEW_PRELUDE="$RESULTS/review_0006c_prelude.sql"
cat "$HERE/50a_webhook_fixture.sql" "$SUPA/reviews/0006c_rls_review.sql" > "$REVIEW_PRELUDE"

# Final suites after 0004b, on both paths. The fixtures are rolled back, so the replicas stay clean.
for db_md5 in "gtm_local_live_replay $MD5_A" "gtm_local_fresh $MD5_B"; do
  set -- $db_md5
  run_suite "$1" "$SUPA/tests/gtm_scope_rls.sql" "$2" final || FAIL=1
  run_suite "$1" "$HERE/30_gtm_completion_tests.sql" "$2" final || FAIL=1
  run_suite "$1" "$HERE/31_crm_role_matrix_tests.sql" "$2" final || FAIL=1
  run_suite "$1" "$HERE/32_clients_readiness_tests.sql" "$2" final || FAIL=1
  run_suite "$1" "$HERE/33_anon_hardening_tests.sql" "$2" final "$SUPA/reviews/0009_anon_hardening_proposed.sql" || FAIL=1
  run_suite "$1" "$HERE/40_automation_engine_tests.sql" "$2" final || FAIL=1
  run_suite "$1" "$HERE/41_legacy_node_regression.sql" "$2" final "$LEGACY_PRELUDE" || FAIL=1
  run_suite "$1" "$HERE/50_review_0006c_tests.sql" "$2" final "$REVIEW_PRELUDE" || FAIL=1
  run_suite "$1" "$HERE/39_f2_clients_deals_matrix.sql" "$2" final || FAIL=1
done

# Path C: rollback round trip. 0007 is applied and then rolled back on a scratch replica. The privilege
# and shape snapshot must match the state before 0007 exactly, so the rollback neither leaves Phase 5
# objects behind nor widens access.
new_db gtm_local_rollback
base gtm_local_rollback
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links 0004b_gtm_archive_columns 0006b_gtm_rls_completion 0007a_gtm_workflow_baseline; do
  run gtm_local_rollback "$SUPA/migrations/$m.sql"
done
# The replica's Supabase default privileges give PUBLIC EXECUTE on new functions. Production has none
# on the run controls, so set the replica to production's ACL before the baseline snapshot is taken.
"${PSQL[@]}" -d gtm_local_rollback -c "
  revoke all on function public.run_workflow_test(uuid, jsonb), public.cancel_workflow_run(uuid) from public, anon;
  grant execute on function public.run_workflow_test(uuid, jsonb), public.cancel_workflow_run(uuid) to authenticated, service_role;"
SNAP="$SUPA/tests/local/rollback_acl_snapshot.sql"
PSQL_SNAP=(psql -X -q -t -A -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U postgres -d gtm_local_rollback)
"${PSQL_SNAP[@]}" -f "$SNAP" > "$RESULTS/rollback.pre_0007.acl.txt"
run gtm_local_rollback "$SUPA/migrations/0007_gtm_automation_engine.sql"
run gtm_local_rollback "$SUPA/rollbacks/0007_down.sql"
"${PSQL_SNAP[@]}" -f "$SNAP" > "$RESULTS/rollback.post_down.acl.txt"
if diff -u "$RESULTS/rollback.pre_0007.acl.txt" "$RESULTS/rollback.post_down.acl.txt"; then
  echo "passed: rollback round trip restores the pre-0007 ACL, function body and shape"
else
  echo "FAILED: rollback round trip differs from the pre-0007 state (see diff above)" >&2
  FAIL=1
fi

# Path E: the production-shaped replica (00b_production_surface.sql). Base schema, then the surface, then the
# repo migrations in dependency order. The surface holds production's policies, grants, function bodies and
# ACLs, the plans table, the notifications shape and the ensure_rls event trigger. 00b_production_surface.sql
# is checked against production by catalog fingerprint (see notes, section "Replica fidelity").
# No synthetic row is copied from production. Every fixture is rolled back.
new_db gtm_local_prod_surface
base gtm_local_prod_surface
run gtm_local_prod_surface "$HERE/00b_production_surface.sql"
MD5_E="$(baseline_md5 gtm_local_prod_surface)"

# Fidelity gate 1: after 00b, the surface's policies, table grants, function bodies and function ACLs must match
# the catalog digests captured from production (fixtures/production_digests.expected). A mismatch stops the path.
check_digests() {  # $1 = label, $2 = sql file, $3 = check prefix
  local out="$RESULTS/gtm_local_prod_surface.digests.$1.txt"
  "${PSQL[@]}" -At -d gtm_local_prod_surface -f "$2" | grep "^$3|" | sort > "$out"
  grep "^$3|" "$HERE/fixtures/production_digests.expected" | sort | diff -u - "$out" \
    || { echo "FAILED: surface $1 digests differ from production (see diff above)" >&2; exit 1; }
  echo "passed: surface $1 digests match production ($(wc -l < "$out") rows)"
}
check_digests fingerprint "$HERE/fingerprint_surface.sql" fingerprint
# Same order production has: 0002 to 0005 (already applied to the live catalog, which is why contacts.company_id
# exists), then the partial 0006 state and archive drift from path A, then 0006b, 0004b and the workflow migrations.
# Any failure here stops the path: a migration error must never be silently skipped.
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links; do
  run gtm_local_prod_surface "$SUPA/migrations/$m.sql" || { echo "FAILED: surface migration $m" >&2; exit 1; }
done
# Fidelity gate 2: after 0005 the column sets must match production for the 12 tables checked.
check_digests columns "$HERE/columns_surface.sql" columns
run gtm_local_prod_surface "$HERE/02_live_partial_state.sql" || { echo "FAILED: live partial state" >&2; exit 1; }
run gtm_local_prod_surface "$HERE/02b_live_archive_drift.sql" || { echo "FAILED: archive drift" >&2; exit 1; }
for m in 0006b_gtm_rls_completion 0004b_gtm_archive_columns 0007a_gtm_workflow_baseline 0007_gtm_automation_engine 0008_gtm_clients_readiness; do
  run gtm_local_prod_surface "$SUPA/migrations/$m.sql" || { echo "FAILED: surface migration $m" >&2; exit 1; }
done

# The 0009 proposal and rollback as they would run in production: one transaction each.
PROP="$SUPA/reviews/0009_anon_hardening_proposed.sql"
PRELUDE_RESTORE="$RESULTS/0009_restore_leads_select.sql"
{ cat "$PROP"; echo "select set_config('gtm.restore_anon_tables', 'public.leads', true);"
  echo "select set_config('gtm.restore_anon_privileges', 'SELECT', true);"
  cat "$SUPA/reviews/0009_anon_hardening_rollback.sql"; } > "$PRELUDE_RESTORE"
PRELUDE_TRUNCATE="$RESULTS/0009_restore_truncate_refused.sql"
{ cat "$PROP"; echo "select set_config('gtm.restore_anon_tables', 'public.leads', true);"
  echo "select set_config('gtm.restore_anon_privileges', 'TRUNCATE', true);"
  cat "$SUPA/reviews/0009_anon_hardening_rollback.sql"; } > "$PRELUDE_TRUNCATE"

# Expected failure: without the 0009 proposal the anon-hardening suite must fail on the surface, because
# anon still holds privileges. A pass here would mean the check is blind to the production ACL.
if run_suite gtm_local_prod_surface "$HERE/33_anon_hardening_tests.sql" "$MD5_E" pre-0009; then
  echo "UNEXPECTED: production ACL passed 33_anon_hardening_tests.sql without the proposal" >&2
  FAIL=1
else
  echo "observed (expected): production ACL fails 33_anon_hardening_tests.sql before 0009"
fi

# Negative control for suite 34: removing anon EXECUTE on a landing-page RPC must fail it.
NEG="$RESULTS/neg_revoke_submit_landing_form.sql"
echo "revoke execute on function public.submit_landing_form(text, jsonb, jsonb) from anon;" > "$NEG"
if run_suite gtm_local_prod_surface "$HERE/34_anon_rpc_compat_tests.sql" "$MD5_E" neg-control "$NEG"; then
  echo "UNEXPECTED: 34 passed with the landing form RPC revoked from anon" >&2
  FAIL=1
else
  echo "observed (expected): 34 fails when anon loses the landing form RPC"
fi

# Final suites on the surface, before and after the proposal. 34 must pass in both states.
run_suite gtm_local_prod_surface "$SUPA/tests/gtm_scope_rls.sql" "$MD5_E" final || FAIL=1
run_suite gtm_local_prod_surface "$HERE/30_gtm_completion_tests.sql" "$MD5_E" final || FAIL=1
run_suite gtm_local_prod_surface "$HERE/31_crm_role_matrix_tests.sql" "$MD5_E" final || FAIL=1
run_suite gtm_local_prod_surface "$HERE/32_clients_readiness_tests.sql" "$MD5_E" final || FAIL=1
run_suite gtm_local_prod_surface "$HERE/34_anon_rpc_compat_tests.sql" "$MD5_E" pre-0009 || FAIL=1
run_suite gtm_local_prod_surface "$HERE/33_anon_hardening_tests.sql" "$MD5_E" post-0009 "$PROP" || FAIL=1
run_suite gtm_local_prod_surface "$HERE/34_anon_rpc_compat_tests.sql" "$MD5_E" post-0009 "$PROP" || FAIL=1
run_suite gtm_local_prod_surface "$HERE/35_anon_rollback_tests.sql" "$MD5_E" restore-leads-select "$PRELUDE_RESTORE" || FAIL=1
run_suite gtm_local_prod_surface "$HERE/40_automation_engine_tests.sql" "$MD5_E" final || FAIL=1
run_suite gtm_local_prod_surface "$HERE/41_legacy_node_regression.sql" "$MD5_E" final "$LEGACY_PRELUDE" || FAIL=1
run_suite gtm_local_prod_surface "$HERE/50_review_0006c_tests.sql" "$MD5_E" final "$REVIEW_PRELUDE" || FAIL=1
run_suite gtm_local_prod_surface "$HERE/39_f2_clients_deals_matrix.sql" "$MD5_E" final || FAIL=1

# Refusal: the rollback must refuse TRUNCATE. A pass here would mean the allow-list is not enforced.
if { echo "begin;"; cat "$PRELUDE_TRUNCATE"; echo "rollback;"; } | "${PSQL[@]}" -d gtm_local_prod_surface -f - >"$RESULTS/gtm_local_prod_surface.0009_truncate_refused.log" 2>&1; then
  echo "UNEXPECTED: 0009 rollback accepted TRUNCATE" >&2
  FAIL=1
else
  echo "passed: 0009 rollback refuses TRUNCATE"
fi

# Emulated advisor, recorded before and after the proposal. Read-only queries; the post run is rolled back.
{ echo "begin;"; cat "$SUPA/reviews/0009_emulated_advisor.sql"; echo "rollback;"; } \
  | "${PSQL[@]}" -d gtm_local_prod_surface -f - > "$RESULTS/gtm_local_prod_surface.advisor_pre.txt" 2>&1 || FAIL=1
{ echo "begin;"; cat "$PROP"; cat "$SUPA/reviews/0009_emulated_advisor.sql"; echo "rollback;"; } \
  | "${PSQL[@]}" -d gtm_local_prod_surface -f - > "$RESULTS/gtm_local_prod_surface.advisor_post.txt" 2>&1 || FAIL=1
echo "surface path complete: advisor output in $RESULTS/gtm_local_prod_surface.advisor_{pre,post}.txt"

# Path D: two real sessions race a retry on a committed database (not rolled back).
PGHOST="$PGHOST" PGPORT="$PGPORT" "$HERE/concurrency_retry.sh" || FAIL=1
PGHOST="$PGHOST" PGPORT="$PGPORT" "$HERE/concurrency_task_dedupe.sh" || FAIL=1

# Path F: 0006b round trip, in production order. 0004b must come first: the archive guard in 0006b reads archived_at,
# and production has no archived_* columns yet. The snapshot S0 is taken before 0006b, S1 after it, S2 after
# 0006b_down, and S3 after the reapply. Expected: S2 differs from S0 only in the table ACL lines for companies,
# clients and deals (the grants 0006b_down deliberately does not restore). S3 must equal S1 exactly.
FSNAP="$HERE/0006b_state_snapshot.sql"
new_db gtm_local_0006b
base gtm_local_0006b
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links; do
  run gtm_local_0006b "$SUPA/migrations/$m.sql" || { echo "FAILED: path F migration $m" >&2; exit 1; }
done
run gtm_local_0006b "$HERE/02_live_partial_state.sql" || { echo "FAILED: path F partial state" >&2; exit 1; }
run gtm_local_0006b "$HERE/02b_live_archive_drift.sql" || { echo "FAILED: path F archive drift" >&2; exit 1; }
run gtm_local_0006b "$SUPA/migrations/0004b_gtm_archive_columns.sql" || { echo "FAILED: path F 0004b" >&2; exit 1; }
MD5_F="$(baseline_md5 gtm_local_0006b)"
snap() { "${PSQL[@]}" -At -d gtm_local_0006b -f "$FSNAP" > "$RESULTS/0006b.$1.snap.txt"; }
snap S0
run gtm_local_0006b "$SUPA/migrations/0006b_gtm_rls_completion.sql" || { echo "FAILED: path F 0006b apply" >&2; exit 1; }
snap S1
run_suite gtm_local_0006b "$SUPA/tests/gtm_scope_rls.sql" "$MD5_F" 0006b-applied || FAIL=1
run_suite gtm_local_0006b "$HERE/30_gtm_completion_tests.sql" "$MD5_F" 0006b-applied || FAIL=1
run_suite gtm_local_0006b "$HERE/31_crm_role_matrix_tests.sql" "$MD5_F" 0006b-applied || FAIL=1
run_suite gtm_local_0006b "$HERE/39_f2_clients_deals_matrix.sql" "$MD5_F" 0006b-applied || FAIL=1
# 32 needs 0008 (not applied on path F); it runs on paths B and E.
run gtm_local_0006b "$SUPA/rollbacks/0006b_down.sql" || { echo "FAILED: path F 0006b_down" >&2; exit 1; }
snap S2
# Fail-closed after the rollback (39b): clients and deals read zero rows for every app role; the observed archive limit is asserted.
run_suite gtm_local_0006b "$HERE/39b_0006b_rollback_fail_closed.sql" "$MD5_F" 0006b-rolled-back || FAIL=1
# Assert the privileges that 0006b_down deliberately leaves revoked (anon: none; authenticated: no TRUNCATE,
# REFERENCES, TRIGGER or MAINTAIN), and the rest of the state that must return to the baseline.
"${PSQL[@]}" -d gtm_local_0006b -f "$HERE/37_0006b_rollback_asserts.sql" > "$RESULTS/0006b.asserts.log" 2>&1 \
  || { echo "FAILED: path F rollback asserts (see $RESULTS/0006b.asserts.log)" >&2; tail -n 3 "$RESULTS/0006b.asserts.log" >&2; FAIL=1; }
# Expected differences only: the table ACL lines for companies, clients and deals.
UNEXPECTED="$(diff "$RESULTS/0006b.S0.snap.txt" "$RESULTS/0006b.S2.snap.txt" | grep '^[<>]' \
  | grep -v -E '^[<>] table (companies|clients|deals) ' || true)"
EXPECTED_N="$(diff "$RESULTS/0006b.S0.snap.txt" "$RESULTS/0006b.S2.snap.txt" | grep -c -E '^[<>] table (companies|clients|deals) ' || true)"
if [ -n "$UNEXPECTED" ]; then
  echo "FAILED: path F 0006b_down changed objects outside the expected grant set:" >&2; echo "$UNEXPECTED" >&2; FAIL=1
elif [ "$EXPECTED_N" -eq 0 ]; then
  echo "FAILED: path F expected the intentional grant difference and saw none (the check is blind)" >&2; FAIL=1
else
  echo "observed (expected): 0006b_down restores all objects except $EXPECTED_N table ACL line(s) for companies, clients, deals"
fi
# Reapply 0006b and rerun. S3 must equal S1 exactly, so the migration is idempotent after a rollback.
run gtm_local_0006b "$SUPA/migrations/0006b_gtm_rls_completion.sql" || { echo "FAILED: path F 0006b reapply" >&2; exit 1; }
snap S3
if diff -u "$RESULTS/0006b.S1.snap.txt" "$RESULTS/0006b.S3.snap.txt"; then
  echo "passed: path F reapply reproduces the post-0006b state exactly"
else
  echo "FAILED: path F reapply differs from the first post-0006b state" >&2; FAIL=1
fi
run_suite gtm_local_0006b "$SUPA/tests/gtm_scope_rls.sql" "$MD5_F" 0006b-reapplied || FAIL=1
run_suite gtm_local_0006b "$HERE/30_gtm_completion_tests.sql" "$MD5_F" 0006b-reapplied || FAIL=1
run_suite gtm_local_0006b "$HERE/31_crm_role_matrix_tests.sql" "$MD5_F" 0006b-reapplied || FAIL=1
run_suite gtm_local_0006b "$HERE/39_f2_clients_deals_matrix.sql" "$MD5_F" 0006b-reapplied || FAIL=1

# Path G: 0010 least-privilege round trip and test 36, on a copy of the production-shaped surface. The copy is
# taken from path E's final state, which is rolled back, so it has no 0009 or 0010 objects.
"${PSQL[@]}" -d postgres -c "drop database if exists gtm_local_0010 with (force);"
"${PSQL[@]}" -d postgres -c "create database gtm_local_0010 template gtm_local_prod_surface;" || { echo "FAILED: path G copy" >&2; exit 1; }
MD5_G="$(baseline_md5 gtm_local_0010)"
# Scale to production's table count with the fixture (names only, RLS on, no grants beyond the surface defaults).
run gtm_local_0010 "$HERE/fixtures/production_table_names.sql" || { echo "FAILED: path G fixture" >&2; exit 1; }
# Suite 30 is not run here: it asserts the 0006b grant state (no REFERENCES or TRIGGER for authenticated on the GTM tables),
# which production does not have yet. Path F runs it against 0006b.
# Target order: 0009 (anon hardening) then 0010 (TRUNCATE). The copy is taken with production's grants restored, so 0009 is
# what removes anon's privileges here. 0010 then removes authenticated's TRUNCATE. The ACL compare starts from the state after 0009.
"${PSQL[@]}" -1 -d gtm_local_0010 -f "$PROP" || { echo "FAILED: path G 0009 apply" >&2; exit 1; }
run_suite gtm_local_0010 "$HERE/36_least_privilege_tests.sql" "$MD5_G" pre-0010 && { echo "UNEXPECTED: 36 passed before 0010" >&2; FAIL=1; } || echo "observed (expected): 36 fails before 0010 (authenticated still holds TRUNCATE)"
"${PSQL[@]}" -At -d gtm_local_0010 -f "$FSNAP" > "$RESULTS/0010.acl.pre.txt"
"${PSQL[@]}" -1 -d gtm_local_0010 -f "$SUPA/reviews/0010_gtm_least_privilege_proposed.sql" || { echo "FAILED: path G 0010 apply" >&2; exit 1; }
"${PSQL[@]}" -At -d gtm_local_0010 -f "$FSNAP" > "$RESULTS/0010.acl.post.txt"
python3 "$HERE/compare_0010_acl.py" "$RESULTS/0010.acl.pre.txt" "$RESULTS/0010.acl.post.txt" 56 || { echo "FAILED: path G ACL compare (SELECT/INSERT/UPDATE/DELETE must be unchanged)" >&2; FAIL=1; }
run_suite gtm_local_0010 "$HERE/36_least_privilege_tests.sql" "$MD5_G" post-0010 || FAIL=1
run_suite gtm_local_0010 "$HERE/33_anon_hardening_tests.sql" "$MD5_G" post-0010 || FAIL=1
for s in gtm_scope_rls.sql:"$SUPA/tests/gtm_scope_rls.sql" 31_crm_role_matrix_tests.sql:"$HERE/31_crm_role_matrix_tests.sql" 32_clients_readiness_tests.sql:"$HERE/32_clients_readiness_tests.sql" 34_anon_rpc_compat_tests.sql:"$HERE/34_anon_rpc_compat_tests.sql"; do
  run_suite gtm_local_0010 "${s#*:}" "$MD5_G" post-0010 || FAIL=1
done
"${PSQL[@]}" -1 -d gtm_local_0010 -f "$SUPA/reviews/0010_gtm_least_privilege_rollback.sql" >/dev/null 2>&1 && { echo "UNEXPECTED: 0010 rollback ran without confirmation" >&2; FAIL=1; } || echo "observed (expected): 0010 rollback refuses without confirmation"
{ echo "select set_config('gtm.confirm_reopen_truncate', 'yes', true);"; cat "$SUPA/reviews/0010_gtm_least_privilege_rollback.sql"; } > "$RESULTS/0010_rollback_confirmed.sql"
"${PSQL[@]}" -1 -d gtm_local_0010 -f "$RESULTS/0010_rollback_confirmed.sql" || { echo "FAILED: path G 0010 rollback" >&2; exit 1; }
"${PSQL[@]}" -1 -d gtm_local_0010 -f "$SUPA/reviews/0010_gtm_least_privilege_proposed.sql" || { echo "FAILED: path G 0010 reapply" >&2; exit 1; }
run_suite gtm_local_0010 "$HERE/36_least_privilege_tests.sql" "$MD5_G" post-reapply || FAIL=1

# Path H: step 4 of 0009 on its own (rls_auto_enable EXECUTE removed from PUBLIC and anon). Nothing else from 0009.
# Control first: without the fixture, 38 must fail. Then the fixture, 38 and 34 must pass.
new_db_from_template() { "${PSQL[@]}" -d postgres -c "drop database if exists $1 with (force);" -c "create database $1 template gtm_local_prod_surface;"; }
new_db_from_template gtm_local_rls_step4
MD5_H="$(baseline_md5 gtm_local_rls_step4)"
run_suite gtm_local_rls_step4 "$HERE/38_rls_auto_enable_standalone.sql" "$MD5_H" control && { echo "UNEXPECTED: 38 passed before the step 4 change" >&2; FAIL=1; } || echo "observed (expected): 38 fails before the step 4 change"
run gtm_local_rls_step4 "$HERE/fixtures/0009_step4_only.sql" || { echo "FAILED: path H step 4 apply" >&2; exit 1; }
run_suite gtm_local_rls_step4 "$HERE/38_rls_auto_enable_standalone.sql" "$MD5_H" step4-only || FAIL=1
run_suite gtm_local_rls_step4 "$HERE/34_anon_rpc_compat_tests.sql" "$MD5_H" step4-only || FAIL=1

exit $FAIL
