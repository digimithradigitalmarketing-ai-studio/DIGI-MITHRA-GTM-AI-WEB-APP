import { describe, expect, it } from "vitest";
import {
  CLIENTS_READINESS_FLAGS,
  classifyClientList,
  clientsWriteBlockMessage,
  evaluateClientsReadiness,
  type ClientsReadiness,
  type ClientsReadinessFlags,
} from "./readiness-state";

function flags(overrides: Partial<ClientsReadinessFlags> = {}): ClientsReadinessFlags {
  const base: ClientsReadinessFlags = {
    table_exists: true,
    rls_enabled: true,
    policy_select: true,
    policy_insert: true,
    policy_update: true,
    policy_delete: true,
    grant_select: true,
    grant_insert: true,
    grant_update: true,
    grant_delete: true,
    anon_has_any_privilege: false,
  };
  return { ...base, ...overrides };
}

const READY: ClientsReadiness = { state: "ready" };
const NOT_CONFIGURED: ClientsReadiness = { state: "not_configured" };
const UNAVAILABLE: ClientsReadiness = { state: "unavailable" };

describe("evaluateClientsReadiness", () => {
  it("is ready when the table, RLS, all four policies and grants are present", () => {
    expect(evaluateClientsReadiness(flags())).toEqual(READY);
  });

  it("is not configured when a write policy is missing", () => {
    for (const key of ["policy_insert", "policy_update", "policy_delete", "policy_select"] as const) {
      expect(evaluateClientsReadiness(flags({ [key]: false }))).toEqual(NOT_CONFIGURED);
    }
  });

  it("is not configured when RLS is disabled or the table is missing", () => {
    expect(evaluateClientsReadiness(flags({ rls_enabled: false }))).toEqual(NOT_CONFIGURED);
    expect(evaluateClientsReadiness(flags({ table_exists: false }))).toEqual(NOT_CONFIGURED);
  });

  it("is not configured when an authenticated grant was revoked", () => {
    expect(evaluateClientsReadiness(flags({ grant_insert: false }))).toEqual(NOT_CONFIGURED);
  });

  it("is not configured when anon holds any privilege on clients", () => {
    expect(evaluateClientsReadiness(flags({ anon_has_any_privilege: true }))).toEqual(NOT_CONFIGURED);
  });

  it("is unavailable, not ready, when the payload is malformed", () => {
    expect(evaluateClientsReadiness(null)).toEqual(UNAVAILABLE);
    expect(evaluateClientsReadiness("ok")).toEqual(UNAVAILABLE);
    expect(evaluateClientsReadiness([])).toEqual(UNAVAILABLE);
    const missing: Partial<ClientsReadinessFlags> = { ...flags() };
    delete missing.policy_delete;
    expect(evaluateClientsReadiness(missing)).toEqual(UNAVAILABLE);
    expect(evaluateClientsReadiness({ ...flags(), rls_enabled: "true" })).toEqual(UNAVAILABLE);
  });

  it("covers every flag the SQL function returns", () => {
    expect(CLIENTS_READINESS_FLAGS).toHaveLength(11);
  });
});

describe("clientsWriteBlockMessage", () => {
  it("lets writes through only when ready", () => {
    expect(clientsWriteBlockMessage(READY)).toBeNull();
  });
  it("blocks writes with the not-configured title", () => {
    expect(clientsWriteBlockMessage(NOT_CONFIGURED)).toBe("Clients module not configured");
  });
  it("blocks writes with a generic message when the check is unavailable", () => {
    expect(clientsWriteBlockMessage(UNAVAILABLE)).toMatch(/could not be checked/);
  });
});

describe("classifyClientList", () => {
  const base = { readiness: READY, hasAccess: true, listError: null, rowCount: 3 };

  it("shows the list when ready and rows exist", () => {
    expect(classifyClientList(base)).toBe("list");
  });

  it("treats a clean zero-row read as genuinely empty only when ready", () => {
    expect(classifyClientList({ ...base, rowCount: 0 })).toBe("empty");
  });

  it("reports missing configuration even when the read returns zero rows", () => {
    // Without the readiness check, a missing policy would look like this same empty state.
    expect(classifyClientList({ ...base, readiness: NOT_CONFIGURED, rowCount: 0 })).toBe("not_configured");
    expect(classifyClientList({ ...base, readiness: NOT_CONFIGURED, rowCount: 5 })).toBe("not_configured");
  });

  it("reports unavailable when the readiness check itself failed", () => {
    expect(classifyClientList({ ...base, readiness: UNAVAILABLE })).toBe("unavailable");
  });

  it("reports permission denied for a user with no workspace role", () => {
    expect(classifyClientList({ ...base, hasAccess: false, rowCount: 0 })).toBe("permission_denied");
  });

  it("reports permission denied on a 42501 list error", () => {
    expect(classifyClientList({ ...base, listError: { code: "42501" }, rowCount: 0 })).toBe("permission_denied");
  });

  it("reports unavailable for any other list error, never empty", () => {
    expect(classifyClientList({ ...base, listError: { code: "57014" }, rowCount: 0 })).toBe("unavailable");
  });
});
