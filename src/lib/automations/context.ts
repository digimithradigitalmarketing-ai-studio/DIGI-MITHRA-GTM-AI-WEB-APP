import { redirect } from "next/navigation";
import { getMemberships } from "@/lib/access";
import {
  findWorkspaceAccess,
  listWorkspaceAccess,
  pickWorkspace,
  type WorkspaceAccess,
} from "@/lib/automations/workspace";

// Loads the signed-in user's workspaces for an automation page and picks the one to show.
// Signed-out visitors are sent to /login. Call this inside a <Suspense> boundary, because it
// reads cookies (cacheComponents is enabled).
export async function loadAutomationContext(requestedWorkspaceId?: string | null): Promise<{
  workspaces: WorkspaceAccess[];
  current: WorkspaceAccess | null;
}> {
  const memberships = await getMemberships();
  if (!memberships) redirect("/login");
  const workspaces = listWorkspaceAccess(memberships);
  return { workspaces, current: pickWorkspace(workspaces, requestedWorkspaceId) };
}

// Access for one workspace, or null when the caller is not a member of it.
export async function loadWorkspaceAccess(workspaceId: string): Promise<WorkspaceAccess | null> {
  const memberships = await getMemberships();
  if (!memberships) redirect("/login");
  return findWorkspaceAccess(memberships, workspaceId);
}
