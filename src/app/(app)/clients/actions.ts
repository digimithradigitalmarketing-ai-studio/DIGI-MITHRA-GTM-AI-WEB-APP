"use server";

import type { CrmActionState, CrmFormState } from "@/lib/crm/state";
import { createRow, setArchived, updateRow, type Scope } from "@/lib/crm/mutations";
import { validateClient } from "@/lib/crm/validation";

const SCOPE: Scope = {
  table: "clients",
  capability: "clients.write",
  listPath: "/clients",
  detailPath: (id) => `/clients/${id}`,
  label: "client",
};

// Only workspace admins manage clients, matching the clients_* policies in migration 0006b. A
// company can have one client record, and the database enforces that with a unique index.
export async function createClientRecord(workspaceId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return createRow(SCOPE, workspaceId, Object.fromEntries(formData.entries()), validateClient);
}

export async function updateClient(clientId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return updateRow(SCOPE, clientId, Object.fromEntries(formData.entries()), validateClient);
}

export async function archiveClient(clientId: string, archived: boolean): Promise<CrmActionState> {
  return setArchived(SCOPE, clientId, archived, "clients.write");
}
