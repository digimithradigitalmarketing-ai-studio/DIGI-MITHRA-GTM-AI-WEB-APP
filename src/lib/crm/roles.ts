// Role rules for the CRM screens. These mirror the RLS policies in migrations 0006 and 0006b.
// The UI uses them only to show or hide controls. Every write is checked again by RLS, and the
// archive guard trigger checks it a third time.
//
// app_private.ws_role maps a tenant owner or admin to "admin" and otherwise returns the
// workspace role. effectiveRole does the same mapping on the client.

export type CrmCapability =
  | "companies.write"
  | "companies.archive"
  | "contacts.write"
  | "leads.write"
  | "clients.write";

const ALLOWED: Record<CrmCapability, readonly string[]> = {
  "companies.write": ["admin", "manager", "editor"],
  "companies.archive": ["admin"],
  "contacts.write": ["admin", "manager", "editor", "support"],
  "leads.write": ["admin", "manager", "editor", "support"],
  "clients.write": ["admin"],
};

export function effectiveRole(tenantRole: string, workspaceRole: string | null | undefined): string | null {
  if (tenantRole === "owner" || tenantRole === "admin") return "admin";
  return workspaceRole ?? null;
}

export function can(role: string | null, capability: CrmCapability): boolean {
  return role !== null && ALLOWED[capability].includes(role);
}
