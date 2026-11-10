import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ActionButton } from "@/components/automations/action-button";
import { Badge, DataTable, EmptyState, Notice, PageHeader, Panel, SkeletonBlock } from "@/components/ui";
import { runWorkflowManually, setWorkflowStatus } from "../actions";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import {
  TRIGGER_LABELS,
  describeNode,
  followUpInputFromDefinition,
  parseDefinition,
} from "@/lib/automations/definition";
import { isUuid } from "@/lib/automations/ids";
import { getWorkflow, listRuns } from "@/lib/automations/queries";
import { nextStatusFor, runStatusBadge, workflowStatusBadge } from "@/lib/automations/run-status";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Automation" };

export default function AutomationDetailPage({ params }: { params: Promise<{ id: string }> }) {
  return (
    <Suspense fallback={<SkeletonBlock className="h-96" />}>
      <Detail params={params} />
    </Suspense>
  );
}

async function Detail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();

  const wf = await getWorkflow(id);
  if (!wf) notFound();

  const access = await loadWorkspaceAccess(wf.workspace_id);
  if (!access) notFound();

  const [runs, definition] = await Promise.all([
    listRuns(wf.workspace_id, { workflowId: id, limit: 20 }),
    Promise.resolve(parseDefinition(wf.definition)),
  ]);

  const badge = workflowStatusBadge(wf.status);
  const transition = nextStatusFor(wf.status);
  const editable = definition ? followUpInputFromDefinition(definition) !== null : false;

  return (
    <>
      <PageHeader
        title={wf.name}
        description={`${TRIGGER_LABELS[wf.trigger_type as keyof typeof TRIGGER_LABELS] ?? wf.trigger_type} · version ${wf.version} · ${access.workspaceName}`}
        actions={
          <>
            <Badge tone={badge.tone}>{badge.label}</Badge>
            <Link href="/automations" className="rounded-lg px-3 py-2 text-sm font-medium text-ink-muted hover:text-ink">Back to automations</Link>
          </>
        }
      />

      {!access.canManage ? (
        <div className="mb-6">
          <Notice tone="warning">You can view this automation. Only workspace admins and managers can change it.</Notice>
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-4">
        <Panel title="Steps" description="Runs in order. The follow-up task is created once per lead.">
          {definition && definition.nodes.length > 0 ? (
            <ol className="space-y-2 text-sm text-ink">
              {definition.nodes.map((node, i) => (
                <li key={i} className="flex gap-3 rounded-lg border border-line px-3 py-2">
                  <span className="font-mono text-xs text-ink-muted">{i + 1}</span>
                  <span>{describeNode(node)}</span>
                </li>
              ))}
            </ol>
          ) : (
            <Notice tone="warning">This automation has no readable steps.</Notice>
          )}
          {definition && !editable ? (
            <p className="mt-3 text-xs text-ink-muted">This automation has steps the form cannot edit, so it is shown read-only.</p>
          ) : null}
        </Panel>

        {access.canManage ? (
          <Panel title="Controls" description="Pause stops new leads from triggering this automation. A manual run tests it on demand.">
            <div className="flex flex-wrap items-start gap-6">
              {transition ? (
                <ActionButton
                  action={setWorkflowStatus.bind(null, id, transition.target as "active" | "paused")}
                  label={transition.action === "pause" ? "Pause" : transition.action === "resume" ? "Resume" : "Activate"}
                  pendingLabel="Saving…"
                  variant={transition.action === "pause" ? "secondary" : "primary"}
                />
              ) : null}
              <ActionButton action={runWorkflowManually.bind(null, id)} label="Run manually" pendingLabel="Running…" />
              {editable ? (
                <Link href={`/automations/${id}/edit`} className="rounded-lg border border-line bg-panel px-3.5 py-2 text-sm font-medium text-ink hover:bg-slate-50">
                  Edit
                </Link>
              ) : null}
            </div>
          </Panel>
        ) : null}

        <Panel title="Run history" description="Newest first. Each run keeps its steps and any error.">
          {runs.length === 0 ? (
            <EmptyState title="No runs yet" body="Runs appear when a lead arrives or when you run this automation manually." />
          ) : (
            <DataTable
              caption="Runs for this automation"
              headers={["Started", "Status", "Attempt", "Error", ""]}
              rows={runs.map((run) => {
                const rb = runStatusBadge(run.status);
                return [
                  formatDate(run.started_at),
                  <Badge key="s" tone={rb.tone}>{rb.label}</Badge>,
                  run.attempt > 1 ? `Retry ${run.attempt - 1}` : "First attempt",
                  <span key="e" className="line-clamp-1 max-w-xs text-xs text-rose-800">{run.error ?? "—"}</span>,
                  <Link key="o" href={`/automations/runs/${run.id}`} className="font-medium text-brand-700 hover:underline">Details</Link>,
                ];
              })}
            />
          )}
        </Panel>
      </div>
    </>
  );
}
