"use server";

import type { CrmActionState, CrmFormState } from "@/lib/crm/state";
import { createRow, deleteRow, updateRow, type Scope } from "@/lib/crm/mutations";
import { validateContact } from "@/lib/crm/validation";

const SCOPE: Scope = {
  table: "contacts",
  capability: "contacts.write",
  listPath: "/contacts",
  detailPath: (id) => `/contacts/${id}`,
  label: "contact",
};

export async function createContact(workspaceId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return createRow(SCOPE, workspaceId, Object.fromEntries(formData.entries()), validateContact);
}

export async function updateContact(contactId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return updateRow(SCOPE, contactId, Object.fromEntries(formData.entries()), validateContact);
}

// Contacts are deleted. Leads and clients keep their records and clear the link (the foreign
// keys use ON DELETE SET NULL for contact_id).
export async function deleteContact(contactId: string): Promise<CrmActionState> {
  return deleteRow(SCOPE, contactId);
}
