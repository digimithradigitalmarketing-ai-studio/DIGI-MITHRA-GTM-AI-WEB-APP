import { beforeEach, describe, expect, it, vi } from "vitest";

// The loader calls the caller's own Supabase client. The mock replaces it, so the tests cover
// only how the loader maps RPC outcomes to states.
const rpc = vi.fn();
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ rpc }),
}));

import { loadClientsReadiness } from "./readiness";

const GOOD_FLAGS = {
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
  function_security_invoker: true,
  anon_has_any_privilege: false,
  anon_or_public_policy: false,
  public_execute: false,
  anon_execute: false,
};

beforeEach(() => {
  rpc.mockReset();
});

describe("loadClientsReadiness", () => {
  it("is ready when the RPC returns a correctly configured payload", async () => {
    rpc.mockResolvedValue({ data: GOOD_FLAGS, error: null });
    await expect(loadClientsReadiness()).resolves.toEqual({ state: "ready" });
    expect(rpc).toHaveBeenCalledWith("clients_readiness");
  });

  it("is not configured when the RPC is missing from the schema (PostgREST PGRST202)", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "PGRST202", message: "Could not find the function" } });
    await expect(loadClientsReadiness()).resolves.toEqual({ state: "not_configured" });
  });

  it("is not configured when the RPC is missing at the database level (SQLSTATE 42883)", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "42883", message: "function does not exist" } });
    await expect(loadClientsReadiness()).resolves.toEqual({ state: "not_configured" });
  });

  it("is unavailable, not ready, on any other RPC failure", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "XX000", message: "internal" } });
    await expect(loadClientsReadiness()).resolves.toEqual({ state: "unavailable" });
  });

  it("is unavailable when the payload has an unexpected shape", async () => {
    rpc.mockResolvedValue({ data: { table_exists: true }, error: null });
    await expect(loadClientsReadiness()).resolves.toEqual({ state: "unavailable" });
  });

  it("is not configured when anon can still execute the function", async () => {
    rpc.mockResolvedValue({ data: { ...GOOD_FLAGS, anon_execute: true }, error: null });
    await expect(loadClientsReadiness()).resolves.toEqual({ state: "not_configured" });
  });
});
