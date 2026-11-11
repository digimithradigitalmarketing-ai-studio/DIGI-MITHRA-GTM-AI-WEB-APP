import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { explainCrmError } from "./errors";
import { visibleRow, writableWorkspace } from "./guard";
import type { CrmActionState, CrmFormState } from "./state";
import type { CrmCapability } from "./roles";
import { createClient } from "@/lib/supabase/server";
import type { Parsed } from "./validation";

// One write path for every CRM module. The module actions supply the table, the capability,
// the validator and the paths to revalidate. The order is fixed:
//   1. find the record and its workspace through RLS (an invisible record is "not found")
//   2. check the caller's role for that workspace
//   3. validate the values
//   4. write, then check the returned rows, because RLS filters an unauthorised update to zero rows
// Tenant and workspace are never read from the form.

export type Scope = {
  table: string;
  capability: CrmCapability;
  listPath: string;
  detailPath: (id: string) => string;
  label: string;
};

export async function createRow<T extends object>(
  scope: Scope,
  workspaceId: string,
  raw: Record<string, unknown>,
  parse: (raw: Record<string, unknown>) => Parsed<T>,
  extra: Record<string, unknown> = {},
): Promise<CrmFormState> {
  const ws = await writableWorkspace(workspaceId, scope.capability);
  if ("error" in ws) return { error: ws.error };
  const parsed = parse(raw);
  if (!parsed.ok) return { errors: parsed.errors };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from(scope.table)
    .insert({ tenant_id: ws.access.tenantId, workspace_id: ws.access.workspaceId, ...extra, ...parsed.value })
    .select("id")
    .single();
  if (error || !data) return { error: explainCrmError(error ?? { message: "no row returned" }) };

  revalidatePath(scope.listPath);
  redirect(scope.detailPath(data.id));
}

export async function updateRow<T extends object>(
  scope: Scope,
  rowId: string,
  raw: Record<string, unknown>,
  parse: (raw: Record<string, unknown>) => Parsed<T>,
): Promise<CrmFormState> {
  const row = await visibleRow<{ id: string; workspace_id: string }>(scope.table, rowId, "id, workspace_id");
  if (!row) return { error: `That ${scope.label} no longer exists.` };
  const ws = await writableWorkspace(row.workspace_id, scope.capability);
  if ("error" in ws) return { error: ws.error };
  const parsed = parse(raw);
  if (!parsed.ok) return { errors: parsed.errors };

  const supabase = await createClient();
  const { data, error } = await supabase.from(scope.table).update(parsed.value).eq("id", rowId).select("id");
  if (error) return { error: explainCrmError(error) };
  if (!data || data.length === 0) return { error: `You do not have permission to change this ${scope.label}.` };

  revalidatePath(scope.listPath);
  revalidatePath(scope.detailPath(rowId));
  redirect(scope.detailPath(rowId));
}

export async function deleteRow(scope: Scope, rowId: string): Promise<CrmActionState> {
  const row = await visibleRow<{ id: string; workspace_id: string }>(scope.table, rowId, "id, workspace_id");
  if (!row) return { error: `That ${scope.label} no longer exists.` };
  const ws = await writableWorkspace(row.workspace_id, scope.capability);
  if ("error" in ws) return { error: ws.error };

  const supabase = await createClient();
  const { data, error } = await supabase.from(scope.table).delete().eq("id", rowId).select("id");
  if (error) return { error: explainCrmError(error) };
  if (!data || data.length === 0) return { error: `You do not have permission to delete this ${scope.label}.` };

  revalidatePath(scope.listPath);
  return { ok: true, message: "Deleted.", redirectTo: `${scope.listPath}?workspace=${row.workspace_id}` };
}

// Archive and restore. The archive guard trigger allows these only for workspace admins, so
// the check here gives a message and the trigger is the final check.
export async function setArchived(
  scope: Scope,
  rowId: string,
  archived: boolean,
  capability: CrmCapability,
): Promise<CrmActionState> {
  const row = await visibleRow<{ id: string; workspace_id: string }>(scope.table, rowId, "id, workspace_id");
  if (!row) return { error: `That ${scope.label} no longer exists.` };
  const ws = await writableWorkspace(row.workspace_id, capability);
  if ("error" in ws) return { error: ws.error };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from(scope.table)
    .update({ archived_at: archived ? new Date().toISOString() : null })
    .eq("id", rowId)
    .select("id");
  if (error) return { error: explainCrmError(error) };
  if (!data || data.length === 0) return { error: `You do not have permission to change this ${scope.label}.` };

  revalidatePath(scope.listPath);
  revalidatePath(scope.detailPath(rowId));
  return { ok: true, message: archived ? `Archived. It is hidden from the default list.` : "Restored." };
}
