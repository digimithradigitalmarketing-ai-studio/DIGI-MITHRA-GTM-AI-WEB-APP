import { createClient } from "@/lib/supabase/server";

export type Membership = {
  tenantId: string;
  tenantName: string;
  tenantRole: string;
  workspaces: { id: string; name: string; role: string }[];
};

// Loads the signed-in user's tenants and workspaces through the authenticated
// client. Every query runs under RLS (tenants_read, workspace_members via
// is_member, workspaces_read via app_private.ws_role). This function never uses
// a service key and never filters by tenant on the client to grant access.
export async function getMemberships(): Promise<Membership[] | null> {
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userId = claimsData?.claims?.sub;
  if (!userId) return null;

  const [tenantRes, workspaceRes] = await Promise.all([
    supabase
      .from("tenant_members")
      .select("tenant_id, role, tenants(id, name)")
      .eq("user_id", userId),
    supabase
      .from("workspace_members")
      .select("tenant_id, workspace_id, role, workspaces(id, name)")
      .eq("user_id", userId),
  ]);

  if (tenantRes.error) throw new Error(`tenant_members read failed: ${tenantRes.error.message}`);
  if (workspaceRes.error) throw new Error(`workspace_members read failed: ${workspaceRes.error.message}`);

  return (tenantRes.data ?? []).map((t) => {
    const tenant = t.tenants as unknown as { id: string; name: string } | null;
    return {
      tenantId: t.tenant_id,
      tenantName: tenant?.name ?? "",
      tenantRole: t.role,
      workspaces: (workspaceRes.data ?? [])
        .filter((w) => w.tenant_id === t.tenant_id)
        .map((w) => {
          const ws = w.workspaces as unknown as { id: string; name: string } | null;
          return { id: w.workspace_id, name: ws?.name ?? "", role: w.role };
        }),
    };
  });
}
