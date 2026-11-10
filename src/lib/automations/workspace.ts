import type { Membership } from "@/lib/access";

// Workspace access rules for automations. These mirror app_private.ws_role in the database:
// a tenant owner or admin manages every workspace in that tenant, and anyone else needs the
// admin or manager role in the workspace. The database still enforces this on every write.

export type WorkspaceAccess = {
  tenantId: string;
  tenantName: string;
  workspaceId: string;
  workspaceName: string;
  tenantRole: string;
  workspaceRole: string;
  canManage: boolean;
};

const TENANT_MANAGER_ROLES = ["owner", "admin"];
const WORKSPACE_MANAGER_ROLES = ["admin", "manager"];

export function canManageWorkflows(tenantRole: string, workspaceRole: string): boolean {
  return TENANT_MANAGER_ROLES.includes(tenantRole) || WORKSPACE_MANAGER_ROLES.includes(workspaceRole);
}

export function listWorkspaceAccess(memberships: Membership[]): WorkspaceAccess[] {
  return memberships.flatMap((m) =>
    m.workspaces.map((w) => ({
      tenantId: m.tenantId,
      tenantName: m.tenantName,
      workspaceId: w.id,
      workspaceName: w.name,
      tenantRole: m.tenantRole,
      workspaceRole: w.role,
      canManage: canManageWorkflows(m.tenantRole, w.role),
    })),
  );
}

export function findWorkspaceAccess(memberships: Membership[], workspaceId: string): WorkspaceAccess | null {
  return listWorkspaceAccess(memberships).find((w) => w.workspaceId === workspaceId) ?? null;
}

// Picks the workspace a page should show: the requested one when the user can see it, otherwise
// the first workspace they belong to. Returns null when they belong to none.
export function pickWorkspace(all: WorkspaceAccess[], requestedId?: string | null): WorkspaceAccess | null {
  if (all.length === 0) return null;
  return all.find((w) => w.workspaceId === requestedId) ?? all[0];
}
