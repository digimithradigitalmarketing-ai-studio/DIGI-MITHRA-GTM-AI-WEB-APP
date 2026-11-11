"use server";

import type { CrmActionState, CrmFormState } from "@/lib/crm/state";
import { createRow, setArchived, updateRow, type Scope } from "@/lib/crm/mutations";
import { validateCompany } from "@/lib/crm/validation";

const SCOPE: Scope = {
  table: "companies",
  capability: "companies.write",
  listPath: "/companies",
  detailPath: (id) => `/companies/${id}`,
  label: "company",
};

export async function createCompany(workspaceId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return createRow(SCOPE, workspaceId, Object.fromEntries(formData.entries()), validateCompany);
}

export async function updateCompany(companyId: string, _prev: CrmFormState, formData: FormData): Promise<CrmFormState> {
  return updateRow(SCOPE, companyId, Object.fromEntries(formData.entries()), validateCompany);
}

// Companies are archived, not deleted. Clients and deals keep a company's history, so a hard
// delete would be refused by the database anyway. Only workspace admins can archive or restore.
export async function archiveCompany(companyId: string, archived: boolean): Promise<CrmActionState> {
  return setArchived(SCOPE, companyId, archived, "companies.archive");
}
