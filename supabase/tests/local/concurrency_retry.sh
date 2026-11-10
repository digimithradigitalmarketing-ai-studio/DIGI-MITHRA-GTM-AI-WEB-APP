#!/usr/bin/env bash
# Two-session race test for retry_workflow_run. LOCAL ONLY.
# Builds gtm_local_concurrency, COMMITS a seed (this database is not rolled back), then runs two
# real sessions against the same failed run. Session A holds the retry while it is still open.
# Session B starts 1s later and must wait on the row lock, then be refused with 22023.
# Pass criteria: exactly one retry row exists, A succeeded, B was refused with the clean message
# (not a 23505 from the unique index, which would mean the lock was not doing its job).
#
# Usage: PGPORT=54329 PGHOST=/tmp ./concurrency_retry.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUPA="$(cd "$HERE/../.." && pwd)"
PGHOST="${PGHOST:-/tmp}"
PGPORT="${PGPORT:-54329}"
DB=gtm_local_concurrency

case "$PGHOST" in /*|localhost|127.0.0.1) ;; *) echo "refusing: PGHOST must be local" >&2; exit 1 ;; esac

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U postgres)
# Session clients do not stop on the expected error from session B.
SESS=(psql -X -q -h "$PGHOST" -p "$PGPORT" -U postgres)
RESULTS="$HERE/results"; mkdir -p "$RESULTS"

"${PSQL[@]}" -d postgres -c "drop database if exists $DB with (force);"
"${PSQL[@]}" -d postgres -c "create database $DB;"
for f in 00_auth_shim.sql 01_base_schema.sql; do "${PSQL[@]}" -d "$DB" -f "$HERE/$f"; done
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links 0004b_gtm_archive_columns 0006b_gtm_rls_completion 0007a_gtm_workflow_baseline 0007_gtm_automation_engine; do
  "${PSQL[@]}" -d "$DB" -f "$SUPA/migrations/$m.sql" >/dev/null
done

# Committed seed: tenant, workspace, a manager, a workflow, and one failed run to retry.
"${PSQL[@]}" -d "$DB" <<'SQL'
insert into auth.users (id, aud, role) values ('c0000000-0000-4000-8000-00000000c001', 'authenticated', 'authenticated');
insert into public.tenants (id, name, slug, kind) values ('c1000000-0000-4000-8000-00000000000c', 'Race Tenant', 'race-tenant', 'agency');
insert into public.workspaces (id, tenant_id, name, slug) values ('c2000000-0000-4000-8000-0000000000c1', 'c1000000-0000-4000-8000-00000000000c', 'R1', 'r1-race');
insert into public.tenant_members (tenant_id, user_id, role) values ('c1000000-0000-4000-8000-00000000000c', 'c0000000-0000-4000-8000-00000000c001', 'viewer');
insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values ('c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-00000000c001', 'manager');
insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, status, definition) values
  ('c3000000-0000-4000-8000-0000000000c1', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1',
   'Race follow-up', 'lead_created', 'draft', '{"nodes":[{"type":"create_task","config":{"title":"Race task","due_in_hours":24}},{"type":"end"}]}');
insert into public.workflow_runs (id, tenant_id, workspace_id, workflow_id, version, trigger_payload, dedupe_key, status, error, finished_at)
values ('c4000000-0000-4000-8000-0000000000c1', 'c1000000-0000-4000-8000-00000000000c', 'c2000000-0000-4000-8000-0000000000c1',
        'c3000000-0000-4000-8000-0000000000c1', 1, '{"name":"Race"}', 'seed-failed-run', 'failed', 'seed failure', now());
SQL

RUN='c4000000-0000-4000-8000-0000000000c1'
ACT="select set_config('request.jwt.claims', '{\"sub\":\"c0000000-0000-4000-8000-00000000c001\",\"role\":\"authenticated\"}', false); set role authenticated;"

# Session A: retries, keeps the transaction open for 3s, then commits.
cat > "$RESULTS/concurrency_a.sql" <<SQL
begin;
$ACT
select 'A_RESULT ' || public.retry_workflow_run('$RUN');
select pg_sleep(3);
commit;
SQL

# Session B: starts 1s later, so A already holds the lock.
cat > "$RESULTS/concurrency_b.sql" <<SQL
$ACT
select 'B_START ' || clock_timestamp();
select 'B_RESULT ' || public.retry_workflow_run('$RUN');
SQL

"${SESS[@]}" -d "$DB" -f "$RESULTS/concurrency_a.sql" > "$RESULTS/concurrency_a.out" 2>&1 &
PID_A=$!
sleep 1
"${SESS[@]}" -d "$DB" -f "$RESULTS/concurrency_b.sql" > "$RESULTS/concurrency_b.out" 2>&1 || true
wait "$PID_A" || true

CHILDREN="$("${PSQL[@]}" -d "$DB" -tA -c "select count(*) from public.workflow_runs where retry_of = '$RUN';")"
TASKS="$("${PSQL[@]}" -d "$DB" -tA -c "select count(*) from public.tasks where automation_key like 'wf:c3000000-0000-4000-8000-0000000000c1:%';")"

FAIL=0
grep -q "A_RESULT [0-9a-f-]\{36\}" "$RESULTS/concurrency_a.out" || { echo "FAILED: session A did not retry" >&2; FAIL=1; }
grep -q "ERROR:  This run was already retried" "$RESULTS/concurrency_b.out" \
  || { echo "FAILED: session B was not refused with the clean message (see $RESULTS/concurrency_b.out)" >&2; FAIL=1; }
grep -q "duplicate key value violates unique constraint" "$RESULTS/concurrency_b.out" \
  && { echo "FAILED: session B reached the unique index, so the row lock did not serialise the retries" >&2; FAIL=1; }
[ "$CHILDREN" = "1" ] || { echo "FAILED: expected exactly 1 retry row, found $CHILDREN" >&2; FAIL=1; }
[ "$TASKS" = "1" ] || { echo "FAILED: expected exactly 1 automation task, found $TASKS" >&2; FAIL=1; }

if [ "$FAIL" = 0 ]; then
  echo "passed: concurrent retry: one retry row, one task, second session refused after waiting on the lock"
fi
exit $FAIL
