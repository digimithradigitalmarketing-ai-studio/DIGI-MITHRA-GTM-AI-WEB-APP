import { createClient } from "@/lib/supabase/server";

// Read-side data access for the Automation Dashboard. Every query is scoped to one workspace
// and runs through the signed-in user's client, so RLS (workflows_read, workflow_runs_read and
// friends) is the enforcement. The workspace filter is for correctness, not for security.

export type WorkflowRow = {
  id: string;
  tenant_id: string;
  workspace_id: string;
  name: string;
  trigger_type: string;
  status: string;
  version: number;
  definition: unknown;
  updated_at: string;
};

export type RunRow = {
  id: string;
  workflow_id: string;
  version: number;
  status: string;
  trigger_payload: Record<string, unknown>;
  dedupe_key: string | null;
  error: string | null;
  started_at: string;
  finished_at: string | null;
  retry_of: string | null;
  attempt: number;
};

export type StepRow = {
  id: string;
  run_id: string;
  position: number;
  node_type: string;
  status: string;
  output: Record<string, unknown> | null;
};

export type AutomationTaskRow = {
  id: string;
  title: string;
  due_at: string | null;
  priority: string;
  lead_id: string | null;
  automation_key: string;
};

const RUN_COLUMNS =
  "id, workflow_id, version, status, trigger_payload, dedupe_key, error, started_at, finished_at, retry_of, attempt";

export async function listWorkflows(workspaceId: string): Promise<WorkflowRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflows")
    .select("id, tenant_id, workspace_id, name, trigger_type, status, version, definition, updated_at")
    .eq("workspace_id", workspaceId)
    .order("updated_at", { ascending: false });
  if (error) throw new Error(`workflows read failed: ${error.message}`);
  return (data ?? []) as WorkflowRow[];
}

export async function getWorkflow(workflowId: string): Promise<WorkflowRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflows")
    .select("id, tenant_id, workspace_id, name, trigger_type, status, version, definition, updated_at")
    .eq("id", workflowId)
    .maybeSingle();
  if (error) throw new Error(`workflow read failed: ${error.message}`);
  return (data as WorkflowRow | null) ?? null;
}

export async function listRuns(
  workspaceId: string,
  options: { workflowId?: string; status?: string; limit?: number } = {},
): Promise<RunRow[]> {
  const supabase = await createClient();
  let query = supabase
    .from("workflow_runs")
    .select(RUN_COLUMNS)
    .eq("workspace_id", workspaceId)
    .order("started_at", { ascending: false })
    .limit(options.limit ?? 25);
  if (options.workflowId) query = query.eq("workflow_id", options.workflowId);
  if (options.status) query = query.eq("status", options.status);
  const { data, error } = await query;
  if (error) throw new Error(`workflow_runs read failed: ${error.message}`);
  return (data ?? []) as RunRow[];
}

export async function getRun(runId: string): Promise<{ run: RunRow; workspaceId: string; tenantId: string } | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflow_runs")
    .select(`${RUN_COLUMNS}, workspace_id, tenant_id`)
    .eq("id", runId)
    .maybeSingle();
  if (error) throw new Error(`workflow run read failed: ${error.message}`);
  if (!data) return null;
  const { workspace_id, tenant_id, ...run } = data as RunRow & { workspace_id: string; tenant_id: string };
  return { run: run as RunRow, workspaceId: workspace_id, tenantId: tenant_id };
}

export async function getRunSteps(runId: string): Promise<StepRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflow_steps")
    .select("id, run_id, position, node_type, status, output")
    .eq("run_id", runId)
    .order("position", { ascending: true });
  if (error) throw new Error(`workflow_steps read failed: ${error.message}`);
  return (data ?? []) as StepRow[];
}

// Retries that point at the given runs. Used to decide whether a failed run can still be retried.
export async function listRetriesOf(runIds: string[]): Promise<{ retry_of: string; status: string }[]> {
  if (runIds.length === 0) return [];
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflow_runs")
    .select("retry_of, status")
    .in("retry_of", runIds);
  if (error) throw new Error(`retry read failed: ${error.message}`);
  return (data ?? []) as { retry_of: string; status: string }[];
}

// Open follow-up tasks that automations created in this workspace, soonest due first.
export async function listPendingAutomationTasks(workspaceId: string, limit = 20): Promise<AutomationTaskRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tasks")
    .select("id, title, due_at, priority, lead_id, automation_key")
    .eq("workspace_id", workspaceId)
    .not("automation_key", "is", null)
    .eq("status", "open")
    .order("due_at", { ascending: true, nullsFirst: false })
    .limit(limit);
  if (error) throw new Error(`tasks read failed: ${error.message}`);
  return (data ?? []) as AutomationTaskRow[];
}

// Counts for the last `windowDays` days. The window start is computed inside this server function,
// not during render, so the dashboard component stays pure.
export async function countAutomationStats(workspaceId: string, windowDays: number) {
  const supabase = await createClient();
  const sinceIso = new Date(Date.now() - windowDays * 24 * 60 * 60 * 1000).toISOString();
  const [activeWorkflows, runsSince, failedSince, pendingTasks] = await Promise.all([
    supabase
      .from("workflows")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId)
      .eq("status", "active")
      .then((r) => ({ count: r.count, error: r.error })),
    supabase
      .from("workflow_runs")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId)
      .gte("started_at", sinceIso)
      .then((r) => ({ count: r.count, error: r.error })),
    supabase
      .from("workflow_runs")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId)
      .eq("status", "failed")
      .gte("started_at", sinceIso)
      .then((r) => ({ count: r.count, error: r.error })),
    supabase
      .from("tasks")
      .select("id", { count: "exact", head: true })
      .eq("workspace_id", workspaceId)
      .not("automation_key", "is", null)
      .eq("status", "open")
      .then((r) => ({ count: r.count, error: r.error })),
  ]);

  for (const r of [activeWorkflows, runsSince, failedSince, pendingTasks]) {
    if (r.error) throw new Error(`automation stats read failed: ${r.error.message}`);
  }
  return {
    activeWorkflows: activeWorkflows.count ?? 0,
    runsSince: runsSince.count ?? 0,
    failedSince: failedSince.count ?? 0,
    pendingTasks: pendingTasks.count ?? 0,
  };
}
