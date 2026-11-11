"use server";

import type { CrmActionState, CrmFormState } from "@/lib/crm/state";
import { createRow, deleteRow, updateRow, type Scope } from "@/lib/crm/mutations";
import { validateLead } from "@/lib/crm/validation";

const SCOPE: Scope = {
  table: "leads",
  capability: "leads.write",
  listPath: "/leads",
  detailPath: (id) => `/leads/${id}`,
  label: "lead",
};

// Creating a lead fires trg_on_lead. Active lead_created automations run inside the database
// transaction, and each run creates at most one follow-up task per lead. The CRM does not
// trigger automations itself.
export async function createLead(workspaceId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return createRow(SCOPE, workspaceId, Object.fromEntries(formData.entries()), validateLead);
}

export async function updateLead(leadId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return updateRow(SCOPE, leadId, Object.fromEntries(formData.entries()), validateLead);
}

export async function deleteLead(leadId: string): Promise<CrmActionState> {
  return deleteRow(SCOPE, leadId);
}
