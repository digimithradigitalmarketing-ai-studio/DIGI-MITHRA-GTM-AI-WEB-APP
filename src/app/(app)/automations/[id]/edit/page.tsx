import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { WorkflowForm } from "@/components/automations/workflow-form";
import { Notice, PageHeader, Panel, SkeletonBlock } from "@/components/ui";
import { updateWorkflow } from "../../actions";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { followUpInputFromDefinition, parseDefinition } from "@/lib/automations/definition";
import { isUuid } from "@/lib/automations/ids";
import { getWorkflow } from "@/lib/automations/queries";

export const metadata: Metadata = { title: "Edit automation" };

export default function EditAutomationPage({ params }: { params: Promise<{ id: string }> }) {
  return (
    <Suspense fallback={<SkeletonBlock className="h-96" />}>
      <EditForm params={params} />
    </Suspense>
  );
}

async function EditForm({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();

  const wf = await getWorkflow(id);
  if (!wf) notFound();

  const access = await loadWorkspaceAccess(wf.workspace_id);
  if (!access) notFound();

  const followUp = followUpInputFromDefinition(parseDefinition(wf.definition) ?? { nodes: [] });

  return (
    <>
      <PageHeader title="Edit automation" description={wf.name} />
      {!access.canManage ? (
        <Notice tone="warning">Only workspace admins and managers can change this automation.</Notice>
      ) : !followUp ? (
        <Notice tone="warning">
          This automation has steps the form cannot edit, so it is read-only here.
        </Notice>
      ) : (
        <Panel title="Follow-up task">
          <WorkflowForm
            action={updateWorkflow.bind(null, id)}
            defaults={{
              name: wf.name,
              title: followUp.title,
              description: followUp.description,
              dueInHours: String(followUp.dueInHours),
              priority: followUp.priority,
            }}
            submitLabel="Save changes"
            pendingLabel="Saving…"
            cancelHref={`/automations/${id}`}
          />
        </Panel>
      )}
    </>
  );
}
