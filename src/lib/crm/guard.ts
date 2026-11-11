import { getMemberships } from "@/lib/access";
import { isUuid } from "@/lib/automations/ids";
import { findWorkspaceAccess, type WorkspaceAccess } from "@/lib/automations/workspace";
import { createClient } from "@/lib/supabase/server";
import { can, effectiveRole, type CrmCapability } from "./roles";

// Workspace checks shared by every CRM server action. These checks give a clear message and stop
// work the caller cannot do. RLS and the archive guard trigger still check each write.
// The tenant and workspace on a new row always come from the caller's membership, never from
// the form, so a crafted form cannot write into a workspace the caller does not belong to.

export type CrmAccess = WorkspaceAccess & { role: string | null };

export type WritableResult = { access: CrmAccess } | { error: string };

export async function writableWorkspace(workspaceId: string, capability: CrmCapability): Promise<WritableResult> {
  if (!isUuid(workspaceId)) return { error: "Choose a workspace and try again." };
  const memberships = await getMemberships();
  if (!memberships) return { error: "Your session has expired. Sign in again." };
  const found = findWorkspaceAccess(memberships, workspaceId);
  if (!found) return { error: "You do not have access to that workspace." };
  const role = effectiveRole(found.tenantRole, found.workspaceRole);
  if (!can(role, capability)) return { error: "Your role does not allow this change." };
  return { access: { ...found, role } };
}

// Reads one row through the caller's client. A row the caller cannot see comes back as null,
// so the response never shows whether it exists in another workspace.
export async function visibleRow<T>(table: string, id: string, columns: string): Promise<T | null> {
  if (!isUuid(id)) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.from(table).select(columns).eq("id", id).maybeSingle();
  if (error) return null;
  return (data as unknown as T | null) ?? null;
}
