import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ActionButton } from "@/components/automations/action-button";
import { Badge, DataTable, Notice, PageHeader, Panel, SkeletonBlock, StatCard } from "@/components/ui";
import { retryRun } from "../../actions";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { getRun, getRunSteps, listRetriesOf } from "@/lib/automations/queries";
import { attemptLabel, canRetryRun, runStatusBadge, stepCounts } from "@/lib/automations/run-status";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Automation run" };

export default function AutomationRunPage({ params }: { params: Promise<{ runId: string }> }) {
  return (
    <Suspense fallback={<SkeletonBlock className="h-96" />}>
      <RunDetail params={params} />
    </Suspense>
  );
}

async function RunDetail({ params }: { params: Promise<{ runId: string }> }) {
  const { runId } = await params;
  if (!isUuid(runId)) notFound();

  const found = await getRun(runId);
  if (!found) notFound();

  const access = await loadWorkspaceAccess(found.workspaceId);
  if (!access) notFound();

  const [steps, retries] = await Promise.all([getRunSteps(runId), listRetriesOf([runId])]);
  const { run } = found;
  const badge = runStatusBadge(run.status);
  const counts = stepCounts(steps);
  const retryable = canRetryRun(run, retries);
  const leadId = typeof run.trigger_payload?.lead_id === "string" ? run.trigger_payload.lead_id : null;

  return (
    <>
      <PageHeader
        title="Automation run"
        description={`Started ${formatDate(run.started_at)} · ${attemptLabel(run.attempt)}`}
        actions={
          <>
            <Badge tone={badge.tone}>{badge.label}</Badge>
            <Link href={`/automations/${run.workflow_id}`} className="rounded-lg px-3 py-2 text-sm font-medium text-ink-muted hover:text-ink">
              Back to automation
            </Link>
          </>
        }
      />

      {run.error ? (
        <div className="mb-6">
          <Notice tone="warning">
            <span className="font-medium">Failed:</span> {run.error}
          </Notice>
        </div>
      ) : null}

      <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Steps completed" value={String(counts.completed)} />
        <StatCard label="Steps skipped" value={String(counts.skipped)} />
        <StatCard label="Steps failed" value={String(counts.failed)} />
        <StatCard label="Lead" value={leadId ? leadId.slice(0, 8) : "None"} hint={run.dedupe_key ?? undefined} />
      </div>

      <div className="grid grid-cols-1 gap-4">
        <Panel title="Steps" description="In the order they ran. A retry reports completed task steps as created = false, so nothing is duplicated.">
          <DataTable
            caption="Run steps"
            headers={["#", "Step", "Status", "Output"]}
            emptyMessage="No steps were recorded for this run."
            rows={steps.map((s) => {
              const sb = runStatusBadge(s.status === "completed" ? "completed" : s.status === "failed" ? "failed" : "skipped");
              return [
                String(s.position),
                <code key="n" className="font-mono text-xs">{s.node_type}</code>,
                <Badge key="s" tone={sb.tone}>{sb.label}</Badge>,
                <span key="o" className="block max-w-md break-words font-mono text-xs text-ink-muted">
                  {s.output ? JSON.stringify(s.output).slice(0, 240) : "—"}
                </span>,
              ];
            })}
          />
        </Panel>

        {access.canManage && (retryable || run.status === "failed") ? (
          <Panel title="Retry" description="Retrying creates a new linked run. Tasks that already exist are not created again.">
            {retryable ? (
              <ActionButton action={retryRun.bind(null, runId)} label="Retry this run" pendingLabel="Retrying…" variant="primary" />
            ) : (
              <p className="text-sm text-ink-muted">This run already has a retry. Open the automation to see its history.</p>
            )}
          </Panel>
        ) : null}
      </div>
    </>
  );
}
