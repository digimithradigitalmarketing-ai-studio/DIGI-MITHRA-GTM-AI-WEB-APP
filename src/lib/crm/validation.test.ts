import { describe, expect, it } from "vitest";
import { normalizeDomain, parseTags, validateClient, validateCompany, validateContact, validateLead } from "./validation";

const UUID = "11111111-2222-4333-8444-555555555555";

describe("validateCompany", () => {
  it("requires a name and defaults the lifecycle to prospect", () => {
    const result = validateCompany({ name: "  Acme Fitness  ", lifecycle: "" });
    expect(result).toMatchObject({ ok: true, value: { name: "Acme Fitness", lifecycle: "prospect", domain: null } });
  });
  it("reports a missing name and an unknown lifecycle", () => {
    const result = validateCompany({ name: "   ", lifecycle: "vip" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(Object.keys(result.errors).sort()).toEqual(["lifecycle", "name"]);
  });
  it("normalises domains before checking them", () => {
    expect(normalizeDomain("https://www.Example.com/about")).toBe("example.com");
    const result = validateCompany({ name: "Acme", domain: "https://www.Example.com/about" });
    expect(result).toMatchObject({ ok: true, value: { domain: "example.com" } });
  });
  it("rejects a domain that is not a hostname", () => {
    const result = validateCompany({ name: "Acme", domain: "not a domain" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errors.domain).toBeDefined();
  });
});

describe("validateContact", () => {
  it("accepts a minimal contact and normalises tags", () => {
    const result = validateContact({ name: "Asha", tags: "vip, vip, ,gym " });
    expect(result).toMatchObject({ ok: true, value: { name: "Asha", tags: ["vip", "gym"], marketing_consent: false } });
  });
  it("validates email, phone and company id", () => {
    const result = validateContact({ name: "Asha", email: "not-an-email", phone: "12", company_id: "nope" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(Object.keys(result.errors).sort()).toEqual(["company_id", "email", "phone"]);
  });
  it("reads the marketing consent checkbox", () => {
    const result = validateContact({ name: "Asha", marketing_consent: "on" });
    expect(result).toMatchObject({ ok: true, value: { marketing_consent: true } });
  });
  it("caps the number of tags", () => {
    const tags = Array.from({ length: 21 }, (_, i) => `t${i}`).join(",");
    const result = validateContact({ name: "Asha", tags });
    expect(result.ok).toBe(false);
  });
});

describe("parseTags", () => {
  it("drops blanks and duplicates", () => {
    expect(parseTags(" a,,b, a ")).toEqual(["a", "b"]);
  });
});

describe("validateLead", () => {
  it("defaults the value to zero and accepts a valid event date", () => {
    const result = validateLead({ title: "Enquiry", event_date: "2026-12-01" });
    expect(result).toMatchObject({ ok: true, value: { value_inr: 0, event_date: "2026-12-01" } });
  });
  it("rejects impossible dates and negative values", () => {
    const result = validateLead({ title: "Enquiry", event_date: "2026-02-30", value_inr: "-5" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(Object.keys(result.errors).sort()).toEqual(["event_date", "value_inr"]);
  });
  it("accepts linked record ids", () => {
    const result = validateLead({ title: "Enquiry", contact_id: UUID, company_id: "", stage_id: UUID });
    expect(result).toMatchObject({ ok: true, value: { contact_id: UUID, company_id: null, stage_id: UUID } });
  });
});

describe("validateClient", () => {
  it("requires a company and defaults the status to onboarding", () => {
    const missing = validateClient({ status: "" });
    expect(missing.ok).toBe(false);
    const ok = validateClient({ company_id: UUID, status: "" });
    expect(ok).toMatchObject({ ok: true, value: { status: "onboarding", company_id: UUID } });
  });
  it("refuses an end date before the start date", () => {
    const result = validateClient({ company_id: UUID, started_on: "2026-05-10", ended_on: "2026-05-01" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errors.ended_on).toBeDefined();
  });
  it("accepts a retainer of zero and rejects a fractional one", () => {
    expect(validateClient({ company_id: UUID, retainer_inr: "0" })).toMatchObject({ ok: true, value: { retainer_inr: 0 } });
    const bad = validateClient({ company_id: UUID, retainer_inr: "12.5" });
    expect(bad.ok).toBe(false);
  });
});
