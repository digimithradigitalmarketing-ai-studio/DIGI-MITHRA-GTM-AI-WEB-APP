import { createClient } from "@/lib/supabase/server";
import { CrmQueryError } from "./query-error";
import { likePattern, pageRange, sanitizeSearch, type ListParams } from "./search";
import { COMPANY_LIFECYCLES, CLIENT_STATUSES } from "./validation";

// Read side of the CRM. Each query runs through the caller's client, so RLS (companies_read,
// contacts_read, leads_read, clients_read) decides what comes back. The workspace filter is for
// correctness only. It is not an access control.

export type ListResult<T> = { rows: T[]; total: number };

export type CompanyRow = {
  id: string;
  workspace_id: string;
  name: string;
  domain: string | null;
  industry: string | null;
  city: string | null;
  lifecycle: string;
  notes: string | null;
  archived_at: string | null;
  updated_at: string;
};

export type ContactRow = {
  id: string;
  workspace_id: string;
  name: string;
  email: string | null;
  phone: string | null;
  handle: string | null;
  source: string | null;
  tags: string[];
  marketing_consent: boolean;
  notes: string | null;
  company_id: string | null;
  utm_source: string | null;
  utm_medium: string | null;
  utm_campaign: string | null;
  created_at: string;
};

export type LeadRow = {
  id: string;
  workspace_id: string;
  title: string;
  value_inr: number;
  source: string | null;
  event_date: string | null;
  notes: string | null;
  contact_id: string | null;
  company_id: string | null;
  stage_id: string | null;
  created_at: string;
  updated_at: string;
};

export type ClientRow = {
  id: string;
  workspace_id: string;
  company_id: string;
  primary_contact_id: string | null;
  status: string;
  services: string | null;
  retainer_inr: number | null;
  started_on: string | null;
  ended_on: string | null;
  notes: string | null;
  archived_at: string | null;
  updated_at: string;
};

export type Option = { id: string; name: string };

const COMPANY_COLUMNS = "id, workspace_id, name, domain, industry, city, lifecycle, notes, archived_at, updated_at";
const CONTACT_COLUMNS =
  "id, workspace_id, name, email, phone, handle, source, tags, marketing_consent, notes, company_id, utm_source, utm_medium, utm_campaign, created_at";
const LEAD_COLUMNS =
  "id, workspace_id, title, value_inr, source, event_date, notes, contact_id, company_id, stage_id, created_at, updated_at";
const CLIENT_COLUMNS =
  "id, workspace_id, company_id, primary_contact_id, status, services, retainer_inr, started_on, ended_on, notes, archived_at, updated_at";

function fail(scope: string, error: { code?: string; message: string } | null): never {
  throw new CrmQueryError(scope, error ?? { message: "unknown error" });
}

function applyArchived<Q extends { is: (c: string, v: null) => Q; not: (c: string, op: string, v: null) => Q }>(
  query: Q,
  archived: ListParams["archived"],
): Q {
  if (archived === "active") return query.is("archived_at", null);
  if (archived === "archived") return query.not("archived_at", "is", null);
  return query;
}

// ---- Companies -----------------------------------------------------------------

export async function listCompanies(workspaceId: string, params: ListParams): Promise<ListResult<CompanyRow>> {
  const supabase = await createClient();
  const term = sanitizeSearch(params.q);
  const { from, to } = pageRange(params.page);
  let query = supabase
    .from("companies")
    .select(COMPANY_COLUMNS, { count: "exact" })
    .eq("workspace_id", workspaceId);
  query = applyArchived(query, params.archived);
  if ((COMPANY_LIFECYCLES as readonly string[]).includes(params.filter)) query = query.eq("lifecycle", params.filter);
  if (term) query = query.ilike("name", likePattern(term));
  const { data, error, count } = await query.order("name", { ascending: true }).range(from, to);
  if (error) fail("companies", error);
  return { rows: (data ?? []) as unknown as CompanyRow[], total: count ?? 0 };
}

export async function getCompany(companyId: string): Promise<CompanyRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("companies").select(COMPANY_COLUMNS).eq("id", companyId).maybeSingle();
  if (error) fail("company", error);
  return (data as unknown as CompanyRow | null) ?? null;
}

// ---- Contacts ------------------------------------------------------------------

export async function listContacts(workspaceId: string, params: ListParams & { companyId?: string }): Promise<ListResult<ContactRow>> {
  const supabase = await createClient();
  const term = sanitizeSearch(params.q);
  const { from, to } = pageRange(params.page);
  let query = supabase.from("contacts").select(CONTACT_COLUMNS, { count: "exact" }).eq("workspace_id", workspaceId);
  if (params.companyId) query = query.eq("company_id", params.companyId);
  if (term) query = query.ilike("name", likePattern(term));
  const { data, error, count } = await query.order("name", { ascending: true }).range(from, to);
  if (error) fail("contacts", error);
  return { rows: (data ?? []) as unknown as ContactRow[], total: count ?? 0 };
}

export async function getContact(contactId: string): Promise<ContactRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("contacts").select(CONTACT_COLUMNS).eq("id", contactId).maybeSingle();
  if (error) fail("contact", error);
  return (data as unknown as ContactRow | null) ?? null;
}

// ---- Leads ---------------------------------------------------------------------

export async function listLeads(workspaceId: string, params: ListParams & { stageId?: string }): Promise<ListResult<LeadRow>> {
  const supabase = await createClient();
  const term = sanitizeSearch(params.q);
  const { from, to } = pageRange(params.page);
  let query = supabase.from("leads").select(LEAD_COLUMNS, { count: "exact" }).eq("workspace_id", workspaceId);
  if (params.stageId) query = query.eq("stage_id", params.stageId);
  if (term) query = query.ilike("title", likePattern(term));
  const { data, error, count } = await query.order("updated_at", { ascending: false }).range(from, to);
  if (error) fail("leads", error);
  return { rows: (data ?? []) as unknown as LeadRow[], total: count ?? 0 };
}

export async function getLead(leadId: string): Promise<LeadRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("leads").select(LEAD_COLUMNS).eq("id", leadId).maybeSingle();
  if (error) fail("lead", error);
  return (data as unknown as LeadRow | null) ?? null;
}

// ---- Clients -------------------------------------------------------------------

export async function listClients(
  workspaceId: string,
  params: ListParams,
): Promise<ListResult<ClientRow>> {
  const supabase = await createClient();
  const term = sanitizeSearch(params.q);
  const { from, to } = pageRange(params.page);
  let query = supabase.from("clients").select(CLIENT_COLUMNS, { count: "exact" }).eq("workspace_id", workspaceId);
  query = applyArchived(query, params.archived);
  if ((CLIENT_STATUSES as readonly string[]).includes(params.filter)) query = query.eq("status", params.filter);
  if (term) {
    // Clients are searched by their company name, so resolve matching companies first.
    const { data: matches, error: matchError } = await supabase
      .from("companies")
      .select("id")
      .eq("workspace_id", workspaceId)
      .ilike("name", likePattern(term))
      .limit(500);
    if (matchError) fail("companies", matchError);
    const ids = (matches ?? []).map((m) => m.id);
    if (ids.length === 0) return { rows: [], total: 0 };
    query = query.in("company_id", ids);
  }
  const { data, error, count } = await query.order("updated_at", { ascending: false }).range(from, to);
  if (error) fail("clients", error);
  return { rows: (data ?? []) as unknown as ClientRow[], total: count ?? 0 };
}

export async function getClient(clientId: string): Promise<ClientRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("clients").select(CLIENT_COLUMNS).eq("id", clientId).maybeSingle();
  if (error) fail("client", error);
  return (data as unknown as ClientRow | null) ?? null;
}

export async function clientForCompany(companyId: string): Promise<ClientRow | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.from("clients").select(CLIENT_COLUMNS).eq("company_id", companyId).maybeSingle();
  if (error) fail("client", error);
  return (data as unknown as ClientRow | null) ?? null;
}

// ---- Relations and lookups -----------------------------------------------------

export async function contactsOfCompany(companyId: string, limit = 50): Promise<ContactRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("contacts")
    .select(CONTACT_COLUMNS)
    .eq("company_id", companyId)
    .order("name", { ascending: true })
    .limit(limit);
  if (error) fail("contacts", error);
  return (data ?? []) as unknown as ContactRow[];
}

export async function leadsOfCompany(companyId: string, limit = 50): Promise<LeadRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leads")
    .select(LEAD_COLUMNS)
    .eq("company_id", companyId)
    .order("updated_at", { ascending: false })
    .limit(limit);
  if (error) fail("leads", error);
  return (data ?? []) as unknown as LeadRow[];
}

export async function leadsOfContact(contactId: string, limit = 50): Promise<LeadRow[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leads")
    .select(LEAD_COLUMNS)
    .eq("contact_id", contactId)
    .order("updated_at", { ascending: false })
    .limit(limit);
  if (error) fail("leads", error);
  return (data ?? []) as unknown as LeadRow[];
}

// Id-to-name map for a set of rows. One query per table, with no embedded joins, so the
// relationship logic does not depend on PostgREST's foreign-key resolution.
export async function namesById(
  table: "companies" | "contacts" | "pipeline_stages",
  ids: (string | null | undefined)[],
): Promise<Map<string, string>> {
  const unique = [...new Set(ids.filter((id): id is string => !!id))];
  const map = new Map<string, string>();
  if (unique.length === 0) return map;
  const supabase = await createClient();
  const { data, error } = await supabase.from(table).select("id, name").in("id", unique);
  if (error) fail(table, error);
  for (const row of (data ?? []) as Option[]) map.set(row.id, row.name);
  return map;
}

export async function companyOptions(
  workspaceId: string,
  opts: { excludeWithClient?: boolean; keepId?: string | null } = {},
): Promise<Option[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("companies")
    .select("id, name")
    .eq("workspace_id", workspaceId)
    .is("archived_at", null)
    .order("name", { ascending: true })
    .limit(500);
  if (error) fail("companies", error);
  let options = (data ?? []) as Option[];
  if (opts.excludeWithClient && options.length > 0) {
    const { data: clients, error: clientError } = await supabase
      .from("clients")
      .select("company_id")
      .eq("workspace_id", workspaceId)
      .is("archived_at", null);
    if (clientError) fail("clients", clientError);
    const taken = new Set((clients ?? []).map((c) => c.company_id));
    options = options.filter((o) => o.id === opts.keepId || !taken.has(o.id));
  }
  return options;
}

export async function contactOptions(workspaceId: string): Promise<Option[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("contacts")
    .select("id, name")
    .eq("workspace_id", workspaceId)
    .order("name", { ascending: true })
    .limit(500);
  if (error) fail("contacts", error);
  return (data ?? []) as Option[];
}

export async function stageOptions(workspaceId: string): Promise<Option[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("pipeline_stages")
    .select("id, name")
    .eq("workspace_id", workspaceId)
    .order("position", { ascending: true });
  if (error) fail("pipeline stages", error);
  return (data ?? []) as Option[];
}
