import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ActionButton } from "@/components/automations/action-button";
import { Badge, DataTable, EmptyState, Notice, PageHeader, Panel, SkeletonBlock, StatCard } from "@/components/ui";
import { retryRun } from "./actions";
import { loadAutomationContext } from "@/lib/automations/context";
import { TRIGGER_LABELS } from "@/lib/automations/definition";
import { countAutomationStats, listPendingAutomationTasks, listRetriesOf, listRuns, listWorkflows } from "@/lib/automations/queries";
import { canRetryRun, runStatusBadge, workflowStatusBadge } from "@/lib/automations/run-status";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Automations" };

export default function AutomationsPage({ searchParams }: { searchParams: Promise<{ workspace?: string }> }) {
  return (
    <Suspense fallback={<DashboardSkeleton />}>
      <Dashboard searchParams={searchParams} />
    </Suspense>
  );
}

async function Dashboard({ searchParams }: { searchParams: Promise<{ workspace?: string }> }) {
  const { workspace } = await searchParams;
  const { workspaces, current } = await loadAutomationContext(workspace);

  if (!current) {
    return (
      <>
        <PageHeader title="Automations" description="Follow-up workflows that run when leads arrive." />
        <EmptyState title="No workspace yet" body="Your account is not a member of a workspace. Ask an admin to add you." />
      </>
    );
  }

  const [stats, workflows, runs, failed, pending] = await Promise.all([
    countAutomationStats(current.workspaceId, 7),
    listWorkflows(current.workspaceId),
    listRuns(current.workspaceId, { limit: 20 }),
    listRuns(current.workspaceId, { status: "failed", limit: 10 }),
    listPendingAutomationTasks(current.workspaceId),
  ]);
  const retries = await listRetriesOf(failed.map((r) => r.id));

  const workflowName = (id: string) => workflows.find((w) => w.id === id)?.name ?? "Deleted automation";

  return (
    <>
      <PageHeader
        title="Automations"
        description={`Follow-up workflows for ${current.workspaceName}. Each lead creates at most one follow-up task per step.`}
        actions={
          current.canManage ? (
            <Link href={`/automations/new?workspace=${current.workspaceId}`} className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700">
              New automation
            </Link>
          ) : null
        }
      />

      {workspaces.length > 1 ? (
        <nav aria-label="Workspaces" className="mb-6 flex flex-wrap gap-2 text-sm">
          {workspaces.map((w) => (
            <Link
              key={w.workspaceId}
              href={`/automations?workspace=${w.workspaceId}`}
              aria-current={w.workspaceId === current.workspaceId ? "page" : undefined}
              className={`rounded-full px-3 py-1 ${w.workspaceId === current.workspaceId ? "bg-brand-100 text-brand-900" : "bg-slate-100 text-ink-muted hover:text-ink"}`}
            >
              {w.workspaceName}
            </Link>
          ))}
        </nav>
      ) : null}

      {!current.canManage ? (
        <div className="mb-6">
          <Notice tone="warning">You can view automations here. Only workspace admins and managers can change them.</Notice>
        </div>
      ) : null}

      <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Active automations" value={String(stats.activeWorkflows)} />
        <StatCard label="Runs, last 7 days" value={String(stats.runsSince)} />
        <StatCard label="Failed runs, last 7 days" value={String(stats.failedSince)} hint={stats.failedSince > 0 ? "Review below" : undefined} />
        <StatCard label="Open automation tasks" value={String(stats.pendingTasks)} />
      </div>

      <div className="grid grid-cols-1 gap-4">
        <Panel title="Automations" description="Newest first. Pause stops new leads from triggering a workflow.">
          {workflows.length === 0 ? (
            <EmptyState title="No automations yet" body="Create one to add a follow-up task when a lead arrives." />
          ) : (
            <DataTable
              caption="Automations"
              headers={["Name", "Trigger", "Status", "Version", ""]}
              rows={workflows.map((w) => {
                const badge = workflowStatusBadge(w.status);
                return [
                  <span key="n" className="font-medium">{w.name}</span>,
                  TRIGGER_LABELS[w.trigger_type as keyof typeof TRIGGER_LABELS] ?? w.trigger_type,
                  <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                  `v${w.version}`,
                  <Link key="o" href={`/automations/${w.id}`} className="font-medium text-brand-700 hover:underline">Open</Link>,
                ];
              })}
            />
          )}
        </Panel>

        <Panel title="Failed runs" description="A failed run keeps its error and steps. Retrying creates a new linked run, and tasks are not duplicated.">
          <DataTable
            caption="Failed automation runs"
            headers={["Started", "Automation", "Error", "Action"]}
            emptyMessage="No failed runs. Nothing needs a retry."
            rows={failed.map((run) => {
              const runRetries = retries.filter((r) => r.retry_of === run.id);
              const retryable = canRetryRun(run, runRetries);
              return [
                formatDate(run.started_at),
                workflowName(run.workflow_id),
                <span key="e" className="line-clamp-2 max-w-xs text-xs text-rose-800">{run.error ?? "Unknown error"}</span>,
                retryable && current.canManage ? (
                  <ActionButton key="a" action={retryRun.bind(null, run.id)} label="Retry" pendingLabel="Retrying…" />
                ) : runRetries.length > 0 ? (
                  <span key="a" className="text-xs text-ink-muted">Retried</span>
                ) : (
                  <Link key="a" href={`/automations/runs/${run.id}`} className="text-xs font-medium text-brand-700 hover:underline">View run</Link>
                ),
              ];
            })}
          />
        </Panel>

        <Panel title="Open automation tasks" description="Follow-up tasks created by automations, soonest due first.">
          <DataTable
            caption="Open automation tasks"
            headers={["Task", "Priority", "Due", "Lead"]}
            emptyMessage="No open automation tasks."
            rows={pending.map((t) => [
              <span key="t" className="font-medium">{t.title}</span>,
              <Badge key="p" tone={t.priority === "urgent" || t.priority === "high" ? "warning" : "neutral"}>{t.priority}</Badge>,
              t.due_at ? formatDate(t.due_at) : "No due date",
              t.lead_id ? <code key="l" className="font-mono text-xs">{t.lead_id.slice(0, 8)}</code> : "Manual run",
            ])}
          />
        </Panel>

        <Panel title="Run log" description="Newest first. Select a run for its steps.">
          <DataTable
            caption="Automation run log"
            headers={["Started", "Automation", "Status", "Attempt", ""]}
            emptyMessage="No runs yet. Runs appear when a lead arrives or someone runs an automation manually."
            rows={runs.map((run) => {
              const badge = runStatusBadge(run.status);
              return [
                formatDate(run.started_at),
                workflowName(run.workflow_id),
                <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                run.attempt > 1 ? `Retry ${run.attempt - 1}` : "First attempt",
                <Link key="o" href={`/automations/runs/${run.id}`} className="font-medium text-brand-700 hover:underline">Details</Link>,
              ];
            })}
          />
        </Panel>
      </div>
    </>
  );
}

function DashboardSkeleton() {
  return (
    <div className="space-y-4" aria-busy="true" aria-label="Loading automations">
      <SkeletonBlock className="h-10 w-64" />
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {Array.from({ length: 4 }, (_, i) => <SkeletonBlock key={i} className="h-24" />)}
      </div>
      <SkeletonBlock className="h-64" />
    </div>
  );
}
