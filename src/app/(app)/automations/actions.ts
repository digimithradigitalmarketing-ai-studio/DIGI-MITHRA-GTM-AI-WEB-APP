"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getMemberships } from "@/lib/access";
import {
  buildFollowUpDefinition,
  followUpInputFromDefinition,
  parseDefinition,
  validateFollowUpInput,
  type FieldErrors,
} from "@/lib/automations/definition";
import { explainError } from "@/lib/automations/errors";
import { nextStatusFor } from "@/lib/automations/run-status";
import { findWorkspaceAccess, type WorkspaceAccess } from "@/lib/automations/workspace";
import { createClient } from "@/lib/supabase/server";

// Bound actions receive (prevState, formData) from useActionState. Only the bound arguments are
// declared here, because these actions never read the form itself.
//
// Every action re-checks who is calling. The database checks again on each write (RLS and
// require_ws_role), so a skipped check here cannot widen access, but these checks give clear
// messages and keep the action from doing work the caller is not allowed to do.

export type WorkflowFormState = { error?: string; errors?: FieldErrors };
export type ActionState = { ok?: boolean; message?: string; error?: string } | null;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function writableWorkspace(workspaceId: string): Promise<{ access: WorkspaceAccess } | { error: string }> {
  if (!UUID.test(workspaceId)) return { error: "Choose a workspace and try again." };
  const memberships = await getMemberships();
  if (!memberships) return { error: "Your session has expired. Sign in again." };
  const access = findWorkspaceAccess(memberships, workspaceId);
  if (!access) return { error: "You do not have access to that workspace." };
  if (!access.canManage) return { error: "Only workspace admins and managers can change automations." };
  return { access };
}

// Reads a workflow through RLS. A workflow the caller cannot see comes back as null, so the
// response never reveals whether another tenant's workflow exists.
async function visibleWorkflow(workflowId: string) {
  if (!UUID.test(workflowId)) return null;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflows")
    .select("id, tenant_id, workspace_id, status, definition")
    .eq("id", workflowId)
    .maybeSingle();
  if (error) return null;
  return data as { id: string; tenant_id: string; workspace_id: string; status: string; definition: unknown } | null;
}

function formEntries(formData: FormData): Record<string, unknown> {
  return Object.fromEntries(formData.entries());
}

export async function createWorkflow(
  workspaceId: string,
  _prev: WorkflowFormState,
  formData: FormData,
): Promise<WorkflowFormState> {
  const ws = await writableWorkspace(workspaceId);
  if ("error" in ws) return { error: ws.error };

  const parsed = validateFollowUpInput(formEntries(formData));
  if (!parsed.ok) return { errors: parsed.errors };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflows")
    .insert({
      tenant_id: ws.access.tenantId,
      workspace_id: ws.access.workspaceId,
      name: parsed.value.name,
      trigger_type: "lead_created",
      status: "draft",
      definition: buildFollowUpDefinition(parsed.value),
    })
    .select("id")
    .single();
  if (error || !data) return { error: explainError(error ?? { message: "no row" }) };

  revalidatePath("/automations");
  redirect(`/automations/${data.id}`);
}

export async function updateWorkflow(
  workflowId: string,
  _prev: WorkflowFormState,
  formData: FormData,
): Promise<WorkflowFormState> {
  const wf = await visibleWorkflow(workflowId);
  if (!wf) return { error: "That automation no longer exists." };
  const ws = await writableWorkspace(wf.workspace_id);
  if ("error" in ws) return { error: ws.error };

  // A workflow built outside this form may hold steps the form cannot show. Refuse rather than
  // overwrite them silently.
  const current = parseDefinition(wf.definition);
  if (!current || !followUpInputFromDefinition(current)) {
    return { error: "This automation has steps this form cannot edit. Edit it in the database instead." };
  }

  const parsed = validateFollowUpInput(formEntries(formData));
  if (!parsed.ok) return { errors: parsed.errors };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflows")
    .update({ name: parsed.value.name, definition: buildFollowUpDefinition(parsed.value) })
    .eq("id", workflowId)
    .select("id");
  if (error) return { error: explainError(error) };
  // RLS filters an unauthorised update to zero rows instead of raising an error, so check the result.
  if (!data || data.length === 0) return { error: "You do not have permission to change this automation." };

  revalidatePath("/automations");
  revalidatePath(`/automations/${workflowId}`);
  redirect(`/automations/${workflowId}`);
}

export async function setWorkflowStatus(
  workflowId: string,
  target: "active" | "paused",
): Promise<ActionState> {
  const wf = await visibleWorkflow(workflowId);
  if (!wf) return { error: "That automation no longer exists." };
  const ws = await writableWorkspace(wf.workspace_id);
  if ("error" in ws) return { error: ws.error };

  const transition = nextStatusFor(wf.status);
  if (!transition || transition.target !== target) {
    return { error: "This automation is already in that state." };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("workflows")
    .update({ status: target })
    .eq("id", workflowId)
    .select("id");
  if (error) return { error: explainError(error) };
  if (!data || data.length === 0) return { error: "You do not have permission to change this automation." };

  revalidatePath("/automations");
  revalidatePath(`/automations/${workflowId}`);
  return {
    ok: true,
    message:
      target === "paused"
        ? "Paused. New leads will not trigger this automation."
        : "Live. New leads will trigger this automation.",
  };
}

export async function runWorkflowManually(workflowId: string): Promise<ActionState> {
  const wf = await visibleWorkflow(workflowId);
  if (!wf) return { error: "That automation no longer exists." };
  const ws = await writableWorkspace(wf.workspace_id);
  if ("error" in ws) return { error: ws.error };

  // The manual run uses a placeholder name and no lead, so it creates a test task with no lead attached.
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("run_workflow_test", {
    p_workflow: workflowId,
    p_payload: { name: "Manual test" },
  });
  if (error) return { error: explainError(error) };

  revalidatePath("/automations");
  revalidatePath(`/automations/${workflowId}`);
  return { ok: true, message: `Manual run recorded (run ${String(data).slice(0, 8)}). Check the run history below.` };
}

export async function retryRun(runId: string): Promise<ActionState> {
  if (!UUID.test(runId)) return { error: "That run no longer exists." };
  const supabase = await createClient();
  const { data: run, error: readError } = await supabase
    .from("workflow_runs")
    .select("id, workspace_id")
    .eq("id", runId)
    .maybeSingle();
  if (readError || !run) return { error: "That run no longer exists." };

  const ws = await writableWorkspace(run.workspace_id);
  if ("error" in ws) return { error: ws.error };

  // retry_workflow_run refuses anything but a failed run, and refuses a second successful retry.
  const { data: retryId, error } = await supabase.rpc("retry_workflow_run", { p_run: runId });
  if (error) return { error: explainError(error) };

  revalidatePath("/automations");
  revalidatePath(`/automations/runs/${runId}`);
  return { ok: true, message: `Retry recorded as run ${String(retryId).slice(0, 8)}. The original failure is kept.` };
}
