#!/usr/bin/env bash
# Two-session race for exactly-once task creation. LOCAL ONLY.
# Two real sessions run app_private.run_workflow with the SAME dedupe key (the same lead event delivered twice).
# Session A holds its transaction open for 3s. Session B starts 1s later, so A already holds the unique
# (workflow_id, dedupe_key) row. Pass criteria: exactly one run for that key, exactly one automation task, and
# session B did not create a second task or a second run.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SUPA="$(cd "$HERE/../.." && pwd)"
PGHOST="${PGHOST:-/tmp}"
PGPORT="${PGPORT:-54329}"
DB=gtm_local_concurrency_dedupe

case "$PGHOST" in /*|localhost|127.0.0.1) ;; *) echo "refusing: PGHOST must be local" >&2; exit 1 ;; esac

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U postgres)
SESS=(psql -X -q -h "$PGHOST" -p "$PGPORT" -U postgres)
RESULTS="$HERE/results"; mkdir -p "$RESULTS"

"${PSQL[@]}" -d postgres -c "drop database if exists $DB with (force);"
"${PSQL[@]}" -d postgres -c "create database $DB;"
for f in 00_auth_shim.sql 01_base_schema.sql; do "${PSQL[@]}" -d "$DB" -f "$HERE/$f"; done
for m in 0002_gtm_scope_keys 0003_gtm_scoped_crm_foreign_keys 0004_gtm_companies_clients_deals 0005_gtm_company_links 0004b_gtm_archive_columns 0006b_gtm_rls_completion 0007a_gtm_workflow_baseline 0007_gtm_automation_engine; do
  "${PSQL[@]}" -d "$DB" -f "$SUPA/migrations/$m.sql" >/dev/null
done

# Committed seed: an active workflow with one create_task node. No lead is needed for this path.
"${PSQL[@]}" -d "$DB" <<'SQL'
insert into public.tenants (id, name, slug, kind) values ('d1000000-0000-4000-8000-00000000000d', 'Dedupe Tenant', 'dedupe-tenant', 'agency');
insert into public.workspaces (id, tenant_id, name, slug) values ('d2000000-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-00000000000d', 'D1', 'd1-dedupe');
insert into public.workflows (id, tenant_id, workspace_id, name, trigger_type, status, definition) values
  ('d3000000-0000-4000-8000-0000000000d1', 'd1000000-0000-4000-8000-00000000000d', 'd2000000-0000-4000-8000-0000000000d1',
   'Dedupe follow-up', 'lead_created', 'active', '{"nodes":[{"type":"create_task","config":{"title":"Dedupe task","due_in_hours":24}},{"type":"end"}]}');
SQL

WF='d3000000-0000-4000-8000-0000000000d1'
PAYLOAD='{"name":"Race","channel":"web"}'
KEY='lead-event-duplicate-1'

cat > "$RESULTS/dedupe_a.sql" <<SQL
begin;
select 'A_RESULT ' || coalesce(app_private.run_workflow('$WF', '$PAYLOAD'::jsonb, '$KEY')::text, 'null');
select pg_sleep(3);
commit;
SQL

cat > "$RESULTS/dedupe_b.sql" <<SQL
select clock_timestamp() as t0 \gset
select 'B_RESULT ' || coalesce(app_private.run_workflow('$WF', '$PAYLOAD'::jsonb, '$KEY')::text, 'null');
select 'B_WAIT_SECONDS ' || round(extract(epoch from clock_timestamp() - :'t0')::numeric, 2);
SQL

"${SESS[@]}" -d "$DB" -f "$RESULTS/dedupe_a.sql" > "$RESULTS/dedupe_a.out" 2>&1 &
PID_A=$!
sleep 1
"${SESS[@]}" -d "$DB" -f "$RESULTS/dedupe_b.sql" > "$RESULTS/dedupe_b.out" 2>&1 || true
wait "$PID_A" || true

RUNS="$("${PSQL[@]}" -d "$DB" -tA -c "select count(*) from public.workflow_runs where workflow_id = '$WF' and dedupe_key = '$KEY';")"
TASKS="$("${PSQL[@]}" -d "$DB" -tA -c "select count(*) from public.tasks where automation_key like 'wf:$WF:%';")"

FAIL=0
grep -q "A_RESULT [0-9a-f-]\{36\}" "$RESULTS/dedupe_a.out" || { echo "FAILED: session A did not create the run (see $RESULTS/dedupe_a.out)" >&2; FAIL=1; }
grep -q "B_RESULT null" "$RESULTS/dedupe_b.out" || { echo "FAILED: session B did not return the no-op result (see $RESULTS/dedupe_b.out)" >&2; FAIL=1; }
grep -q "duplicate key value violates unique constraint" "$RESULTS/dedupe_b.out" && { echo "FAILED: session B hit a unique violation instead of a no-op" >&2; FAIL=1; }
[ "$RUNS" = "1" ] || { echo "FAILED: expected exactly 1 run for the dedupe key, found $RUNS" >&2; FAIL=1; }
[ "$TASKS" = "1" ] || { echo "FAILED: expected exactly 1 automation task, found $TASKS" >&2; FAIL=1; }

# A holds the key for 3s and B starts at about 1s, so B must have waited for A to commit (about 2s). Without this check,
# B could pass by finding the row already committed from an earlier run, which would not test the race.
WAIT="$(grep -o 'B_WAIT_SECONDS [0-9.]*' "$RESULTS/dedupe_b.out" | awk '{print $2}')"
awk -v w="${WAIT:-0}" 'BEGIN { exit !(w >= 1.5) }' || { echo "FAILED: session B did not wait for A's lock (waited ${WAIT:-none}s)" >&2; FAIL=1; }

if [ "$FAIL" = 0 ]; then
  echo "passed (B waited ${WAIT}s on A's lock): concurrent task creation: one run and one task for the dedupe key; second session was a no-op after waiting"
fi
exit $FAIL
