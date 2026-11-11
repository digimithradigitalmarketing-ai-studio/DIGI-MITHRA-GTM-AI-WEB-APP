import type { FieldSpec } from "@/components/crm/record-form";
import type { ClientRow, CompanyRow, ContactRow, LeadRow, Option } from "./queries";
import { CLIENT_STATUSES, COMPANY_LIFECYCLES } from "./validation";

// Field definitions for the CRM forms. Each module's new and edit pages share one definition,
// so the two forms cannot drift apart.

const opt = (values: readonly string[]) => values.map((v) => ({ value: v, label: v.charAt(0).toUpperCase() + v.slice(1) }));

export function companyFields(): FieldSpec[] {
  return [
    { kind: "text", name: "name", label: "Company name", required: true, maxLength: 200 },
    { kind: "text", name: "domain", label: "Website domain", help: "For example example.com. Used to avoid duplicate companies.", maxLength: 253 },
    { kind: "text", name: "industry", label: "Industry", maxLength: 100 },
    { kind: "text", name: "city", label: "City", maxLength: 100 },
    { kind: "select", name: "lifecycle", label: "Lifecycle", options: opt(COMPANY_LIFECYCLES) },
    { kind: "textarea", name: "notes", label: "Notes", maxLength: 2000 },
  ];
}

export function contactFields(companies: Option[]): FieldSpec[] {
  return [
    { kind: "text", name: "name", label: "Full name", required: true, maxLength: 200 },
    { kind: "email", name: "email", label: "Email", maxLength: 254 },
    { kind: "tel", name: "phone", label: "Phone", help: "Digits with optional + and spaces, 7 to 20 digits." },
    { kind: "text", name: "handle", label: "Social handle", maxLength: 100 },
    { kind: "select", name: "company_id", label: "Company", placeholder: "No company", options: companies.map((c) => ({ value: c.id, label: c.name })) },
    { kind: "text", name: "source", label: "Source", help: "For example Instagram, walk-in or referral.", maxLength: 100 },
    { kind: "text", name: "tags", label: "Tags", help: "Separate with commas." },
    { kind: "checkbox", name: "marketing_consent", label: "Consent to marketing messages" },
    { kind: "textarea", name: "notes", label: "Notes", maxLength: 2000 },
  ];
}

export function leadFields(input: { contacts: Option[]; companies: Option[]; stages: Option[] }): FieldSpec[] {
  return [
    { kind: "text", name: "title", label: "Lead title", required: true, maxLength: 200, help: "For example: Monthly membership enquiry." },
    {
      kind: "select",
      name: "contact_id",
      label: "Contact",
      placeholder: "No contact",
      options: input.contacts.map((c) => ({ value: c.id, label: c.name })),
    },
    {
      kind: "select",
      name: "company_id",
      label: "Company",
      placeholder: "No company",
      options: input.companies.map((c) => ({ value: c.id, label: c.name })),
    },
    {
      kind: "select",
      name: "stage_id",
      label: "Pipeline stage",
      placeholder: "No stage",
      options: input.stages.map((s) => ({ value: s.id, label: s.name })),
    },
    { kind: "number", name: "value_inr", label: "Estimated value (INR)", min: 0, max: 100000000, step: 1 },
    { kind: "text", name: "source", label: "Source", maxLength: 100 },
    { kind: "date", name: "event_date", label: "Event or enquiry date" },
    { kind: "textarea", name: "notes", label: "Notes", maxLength: 2000 },
  ];
}

export function clientFields(input: { companies: Option[]; contacts: Option[] }): FieldSpec[] {
  return [
    {
      kind: "select",
      name: "company_id",
      label: "Company",
      help: "Each company can have one client record.",
      options: input.companies.map((c) => ({ value: c.id, label: c.name })),
    },
    {
      kind: "select",
      name: "primary_contact_id",
      label: "Primary contact",
      placeholder: "No primary contact",
      options: input.contacts.map((c) => ({ value: c.id, label: c.name })),
    },
    { kind: "select", name: "status", label: "Status", options: opt(CLIENT_STATUSES) },
    { kind: "text", name: "services", label: "Services", help: "For example monthly membership, photography package.", maxLength: 500 },
    { kind: "number", name: "retainer_inr", label: "Monthly retainer (INR)", min: 0, max: 100000000, step: 1 },
    { kind: "date", name: "started_on", label: "Start date" },
    { kind: "date", name: "ended_on", label: "End date" },
    { kind: "textarea", name: "notes", label: "Notes", maxLength: 2000 },
  ];
}

// ---- Default values for edit forms and blank forms -------------------------------
// Form values are strings. Empty means "not set", which the validators read as null.


const s = (v: string | number | null | undefined): string => (v === null || v === undefined ? "" : String(v));

export function companyDefaults(row?: CompanyRow | null): Record<string, string> {
  return {
    name: s(row?.name),
    domain: s(row?.domain),
    industry: s(row?.industry),
    city: s(row?.city),
    lifecycle: row?.lifecycle ?? "prospect",
    notes: s(row?.notes),
  };
}

export function contactDefaults(row?: ContactRow | null, companyId?: string): Record<string, string> {
  return {
    name: s(row?.name),
    email: s(row?.email),
    phone: s(row?.phone),
    handle: s(row?.handle),
    company_id: s(row?.company_id ?? companyId ?? null),
    source: s(row?.source),
    tags: (row?.tags ?? []).join(", "),
    marketing_consent: row?.marketing_consent ? "on" : "",
    notes: s(row?.notes),
  };
}

export function leadDefaults(row?: LeadRow | null, prefill: { companyId?: string; contactId?: string } = {}): Record<string, string> {
  return {
    title: s(row?.title),
    contact_id: s(row?.contact_id ?? prefill.contactId ?? null),
    company_id: s(row?.company_id ?? prefill.companyId ?? null),
    stage_id: s(row?.stage_id ?? null),
    value_inr: row ? String(row.value_inr) : "0",
    source: s(row?.source),
    event_date: s(row?.event_date),
    notes: s(row?.notes),
  };
}

export function clientDefaults(row?: ClientRow | null, companyId?: string): Record<string, string> {
  return {
    company_id: s(row?.company_id ?? companyId ?? null),
    primary_contact_id: s(row?.primary_contact_id ?? null),
    status: row?.status ?? "onboarding",
    services: s(row?.services),
    retainer_inr: s(row?.retainer_inr ?? null),
    started_on: s(row?.started_on),
    ended_on: s(row?.ended_on),
    notes: s(row?.notes),
  };
}
