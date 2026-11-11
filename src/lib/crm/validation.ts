// Server-side validation for CRM records. Pure functions with no I/O, so they are unit tested.
// The database enforces the same limits where it can (CHECK constraints on names, status values,
// non-negative retainers and date order). These messages run first so the user sees field errors.

export type FieldErrors = Record<string, string>;
export type Parsed<T> = { ok: true; value: T } | { ok: false; errors: FieldErrors };

export const LIMITS = {
  name: 200,
  text: 2000,
  short: 100,
  url: 253,
  email: 254,
  tagCount: 20,
  tagLength: 40,
  maxValueInr: 100_000_000,
} as const;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const DOMAIN = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const PHONE = /^\+?[0-9][0-9 ()-]{5,18}[0-9]$/;

export const COMPANY_LIFECYCLES = ["prospect", "customer", "former"] as const;
export const CLIENT_STATUSES = ["onboarding", "active", "paused", "churned"] as const;
export type CompanyLifecycle = (typeof COMPANY_LIFECYCLES)[number];
export type ClientStatus = (typeof CLIENT_STATUSES)[number];

// Form values arrive as strings. Empty strings mean "not set".
type Raw = Record<string, unknown>;

function str(raw: Raw, key: string): string {
  const v = raw[key];
  return typeof v === "string" ? v.trim() : "";
}

function optional(raw: Raw, key: string): string | null {
  const v = str(raw, key);
  return v === "" ? null : v;
}

function isUuid(v: string): boolean {
  return UUID.test(v);
}

function optionalUuid(raw: Raw, key: string, errors: FieldErrors, label: string): string | null {
  const v = optional(raw, key);
  if (v === null) return null;
  if (!isUuid(v)) errors[key] = `${label} is not a valid record.`;
  return v;
}

function checkLength(value: string | null, max: number, key: string, label: string, errors: FieldErrors) {
  if (value !== null && value.length > max) errors[key] = `${label} must be ${max} characters or fewer.`;
}

function validDate(v: string): boolean {
  if (!DATE.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

function optionalDate(raw: Raw, key: string, label: string, errors: FieldErrors): string | null {
  const v = optional(raw, key);
  if (v === null) return null;
  if (!validDate(v)) errors[key] = `${label} must be a real date in YYYY-MM-DD format.`;
  return v;
}

function optionalInt(raw: Raw, key: string, label: string, min: number, max: number, errors: FieldErrors): number | null {
  const v = optional(raw, key);
  if (v === null) return null;
  if (!/^\d+$/.test(v)) {
    errors[key] = `${label} must be a whole number.`;
    return null;
  }
  const n = Number(v);
  if (n < min || n > max) {
    errors[key] = `${label} must be between ${min.toLocaleString("en-IN")} and ${max.toLocaleString("en-IN")}.`;
    return null;
  }
  return n;
}

function requiredName(raw: Raw, key: string, label: string, errors: FieldErrors): string {
  const v = str(raw, key);
  if (v === "") errors[key] = `${label} is required.`;
  else if (v.length > LIMITS.name) errors[key] = `${label} must be ${LIMITS.name} characters or fewer.`;
  return v;
}

// ---- Companies -----------------------------------------------------------------

export type CompanyInput = {
  name: string;
  domain: string | null;
  industry: string | null;
  city: string | null;
  lifecycle: CompanyLifecycle;
  notes: string | null;
};

export function normalizeDomain(input: string): string {
  return input
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .replace(/^www\./, "")
    .replace(/\/.*$/, "");
}

export function validateCompany(raw: Raw): Parsed<CompanyInput> {
  const errors: FieldErrors = {};
  const name = requiredName(raw, "name", "Company name", errors);
  const domainRaw = optional(raw, "domain");
  const domain = domainRaw === null ? null : normalizeDomain(domainRaw);
  if (domain !== null && !DOMAIN.test(domain)) errors.domain = "Enter a domain such as example.com.";
  const lifecycle = str(raw, "lifecycle") || "prospect";
  if (!(COMPANY_LIFECYCLES as readonly string[]).includes(lifecycle)) errors.lifecycle = "Choose a valid lifecycle stage.";
  const industry = optional(raw, "industry");
  const city = optional(raw, "city");
  const notes = optional(raw, "notes");
  checkLength(industry, LIMITS.short, "industry", "Industry", errors);
  checkLength(city, LIMITS.short, "city", "City", errors);
  checkLength(notes, LIMITS.text, "notes", "Notes", errors);
  if (Object.keys(errors).length) return { ok: false, errors };
  return {
    ok: true,
    value: { name, domain, industry, city, lifecycle: lifecycle as CompanyLifecycle, notes },
  };
}

// ---- Contacts ------------------------------------------------------------------

export type ContactInput = {
  name: string;
  email: string | null;
  phone: string | null;
  handle: string | null;
  source: string | null;
  tags: string[];
  marketing_consent: boolean;
  notes: string | null;
  company_id: string | null;
};

export function parseTags(input: string): string[] {
  return [...new Set(input.split(",").map((t) => t.trim()).filter(Boolean))];
}

export function validateContact(raw: Raw): Parsed<ContactInput> {
  const errors: FieldErrors = {};
  const name = requiredName(raw, "name", "Name", errors);
  const email = optional(raw, "email");
  if (email !== null && (email.length > LIMITS.email || !EMAIL.test(email))) errors.email = "Enter a valid email address.";
  const phone = optional(raw, "phone");
  if (phone !== null && !PHONE.test(phone)) errors.phone = "Enter a phone number with 7 to 20 digits.";
  const handle = optional(raw, "handle");
  const source = optional(raw, "source");
  checkLength(handle, LIMITS.short, "handle", "Handle", errors);
  checkLength(source, LIMITS.short, "source", "Source", errors);
  const tags = parseTags(str(raw, "tags"));
  if (tags.length > LIMITS.tagCount) errors.tags = `Use ${LIMITS.tagCount} tags or fewer.`;
  else if (tags.some((t) => t.length > LIMITS.tagLength)) errors.tags = `Each tag must be ${LIMITS.tagLength} characters or fewer.`;
  const notes = optional(raw, "notes");
  checkLength(notes, LIMITS.text, "notes", "Notes", errors);
  const company_id = optionalUuid(raw, "company_id", errors, "Company");
  const marketing_consent = raw["marketing_consent"] === "on" || raw["marketing_consent"] === "true";
  if (Object.keys(errors).length) return { ok: false, errors };
  return {
    ok: true,
    value: { name, email, phone, handle, source, tags, marketing_consent, notes, company_id },
  };
}

// ---- Leads ---------------------------------------------------------------------

export type LeadInput = {
  title: string;
  value_inr: number;
  source: string | null;
  event_date: string | null;
  notes: string | null;
  contact_id: string | null;
  company_id: string | null;
  stage_id: string | null;
};

export function validateLead(raw: Raw): Parsed<LeadInput> {
  const errors: FieldErrors = {};
  const title = requiredName(raw, "title", "Lead title", errors);
  const value = optionalInt(raw, "value_inr", "Value", 0, LIMITS.maxValueInr, errors);
  const source = optional(raw, "source");
  checkLength(source, LIMITS.short, "source", "Source", errors);
  const event_date = optionalDate(raw, "event_date", "Event date", errors);
  const notes = optional(raw, "notes");
  checkLength(notes, LIMITS.text, "notes", "Notes", errors);
  const contact_id = optionalUuid(raw, "contact_id", errors, "Contact");
  const company_id = optionalUuid(raw, "company_id", errors, "Company");
  const stage_id = optionalUuid(raw, "stage_id", errors, "Stage");
  if (Object.keys(errors).length) return { ok: false, errors };
  return {
    ok: true,
    value: {
      title,
      value_inr: value ?? 0,
      source,
      event_date,
      notes,
      contact_id,
      company_id,
      stage_id,
    },
  };
}

// ---- Clients -------------------------------------------------------------------

export type ClientInput = {
  company_id: string;
  primary_contact_id: string | null;
  status: ClientStatus;
  services: string | null;
  retainer_inr: number | null;
  started_on: string | null;
  ended_on: string | null;
  notes: string | null;
};

export function validateClient(raw: Raw): Parsed<ClientInput> {
  const errors: FieldErrors = {};
  const company_id = optionalUuid(raw, "company_id", errors, "Company") ?? "";
  if (company_id === "") errors.company_id = "Choose the company this client belongs to.";
  const primary_contact_id = optionalUuid(raw, "primary_contact_id", errors, "Primary contact");
  const status = str(raw, "status") || "onboarding";
  if (!(CLIENT_STATUSES as readonly string[]).includes(status)) errors.status = "Choose a valid status.";
  const services = optional(raw, "services");
  checkLength(services, 500, "services", "Services", errors);
  const retainer_inr = optionalInt(raw, "retainer_inr", "Retainer", 0, LIMITS.maxValueInr, errors);
  const started_on = optionalDate(raw, "started_on", "Start date", errors);
  const ended_on = optionalDate(raw, "ended_on", "End date", errors);
  if (started_on && ended_on && ended_on < started_on) errors.ended_on = "End date cannot be before the start date.";
  const notes = optional(raw, "notes");
  checkLength(notes, LIMITS.text, "notes", "Notes", errors);
  if (Object.keys(errors).length) return { ok: false, errors };
  return {
    ok: true,
    value: {
      company_id,
      primary_contact_id,
      status: status as ClientStatus,
      services,
      retainer_inr,
      started_on,
      ended_on,
      notes,
    },
  };
}
