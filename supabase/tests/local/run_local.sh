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
  run_suite "$1" "$HERE/40_automation_engine_tests.sql" "$2" final || FAIL=1
  run_suite "$1" "$HERE/41_legacy_node_regression.sql" "$2" final "$LEGACY_PRELUDE" || FAIL=1
  run_suite "$1" "$HERE/50_review_0006c_tests.sql" "$2" final "$REVIEW_PRELUDE" || FAIL=1
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

# Path D: two real sessions race a retry on a committed database (not rolled back).
PGHOST="$PGHOST" PGPORT="$PGPORT" "$HERE/concurrency_retry.sh" || FAIL=1

exit $FAIL
