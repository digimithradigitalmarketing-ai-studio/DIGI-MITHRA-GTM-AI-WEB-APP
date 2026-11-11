"use server";

import type { CrmActionState, CrmFormState } from "@/lib/crm/state";
import { createRow, setArchived, updateRow, type Scope } from "@/lib/crm/mutations";
import { loadClientsReadiness } from "@/lib/crm/readiness";
import { clientsWriteBlockMessage } from "@/lib/crm/readiness-state";
import { validateClient } from "@/lib/crm/validation";

const SCOPE: Scope = {
  table: "clients",
  capability: "clients.write",
  listPath: "/clients",
  detailPath: (id) => `/clients/${id}`,
  label: "client",
};

// Every client write checks readiness first. If the clients policies are missing, the write is refused
// before it reaches the database, and the message carries no details about the setup.
async function writeBlocked(): Promise<string | null> {
  return clientsWriteBlockMessage(await loadClientsReadiness());
}

// Only workspace admins manage clients, matching the clients_* policies in migration 0006b. A
// company can have one client record, and the database enforces that with a unique index.
export async function createClientRecord(workspaceId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  const blocked = await writeBlocked();
  if (blocked) return { error: blocked };
  return createRow(SCOPE, workspaceId, Object.fromEntries(formData.entries()), validateClient);
}

export async function updateClient(clientId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  const blocked = await writeBlocked();
  if (blocked) return { error: blocked };
  return updateRow(SCOPE, clientId, Object.fromEntries(formData.entries()), validateClient);
}

export async function archiveClient(clientId: string, archived: boolean): Promise<CrmActionState> {
  const blocked = await writeBlocked();
  if (blocked) return { error: blocked };
  return setArchived(SCOPE, clientId, archived, "clients.write");
}
