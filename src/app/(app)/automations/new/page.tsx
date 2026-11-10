import type { Metadata } from "next";
import { Suspense } from "react";
import { WorkflowForm } from "@/components/automations/workflow-form";
import { EmptyState, Notice, PageHeader, Panel, SkeletonBlock } from "@/components/ui";
import { createWorkflow } from "../actions";
import { loadAutomationContext } from "@/lib/automations/context";

export const metadata: Metadata = { title: "New automation" };

export default function NewAutomationPage({ searchParams }: { searchParams: Promise<{ workspace?: string }> }) {
  return (
    <>
      <PageHeader title="New automation" description="When a lead is created, add a follow-up task. The automation starts as a draft; activate it from its page." />
      <Suspense fallback={<SkeletonBlock className="h-96" />}>
        <NewForm searchParams={searchParams} />
      </Suspense>
    </>
  );
}

async function NewForm({ searchParams }: { searchParams: Promise<{ workspace?: string }> }) {
  const { workspace } = await searchParams;
  const { current } = await loadAutomationContext(workspace);

  if (!current) {
    return <EmptyState title="No workspace yet" body="Your account is not a member of a workspace." />;
  }
  if (!current.canManage) {
    return (
      <Notice tone="warning">
        Only workspace admins and managers can create automations in {current.workspaceName}.
      </Notice>
    );
  }

  return (
    <Panel title="Follow-up task" description={`Workspace: ${current.workspaceName}`}>
      <WorkflowForm
        action={createWorkflow.bind(null, current.workspaceId)}
        defaults={{ name: "", title: "Follow up with {{name}}", description: "", dueInHours: "24", priority: "normal" }}
        submitLabel="Create automation"
        pendingLabel="Creating…"
        cancelHref="/automations"
      />
    </Panel>
  );
}
