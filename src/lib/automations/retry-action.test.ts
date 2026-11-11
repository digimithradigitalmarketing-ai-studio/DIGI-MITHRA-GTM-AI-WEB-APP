import { beforeEach, describe, expect, it, vi } from "vitest";

// retryRun is a server action. These tests replace only its boundaries (the session, the caller's
// Supabase client and Next's cache), so they check what the action does with each RPC outcome.
const rpc = vi.fn();
const maybeSingle = vi.fn();
const getMemberships = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    rpc,
    from: () => ({ select: () => ({ eq: () => ({ maybeSingle }) }) }),
  }),
}));
vi.mock("@/lib/access", () => ({ getMemberships: () => getMemberships() }));
vi.mock("next/cache", () => ({ revalidatePath: vi.fn() }));
vi.mock("next/navigation", () => ({ redirect: vi.fn() }));

import { retryRun } from "@/app/(app)/automations/actions";
import { RETRY_UNAVAILABLE_MESSAGE } from "./errors";

const RUN_ID = "11111111-1111-4111-8111-111111111111";
const WORKSPACE_ID = "22222222-2222-4222-8222-222222222222";

beforeEach(() => {
  rpc.mockReset();
  maybeSingle.mockReset();
  getMemberships.mockReset();
  maybeSingle.mockResolvedValue({ data: { id: RUN_ID, workspace_id: WORKSPACE_ID }, error: null });
  getMemberships.mockResolvedValue([
    {
      tenantId: "33333333-3333-4333-8333-333333333333",
      tenantName: "Test tenant",
      tenantRole: "member",
      workspaces: [{ id: WORKSPACE_ID, name: "Test workspace", role: "manager" }],
    },
  ]);
});

describe("retryRun when retry_workflow_run is not installed", () => {
  it("reports retry as unavailable when PostgREST cannot find the function (PGRST202)", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "PGRST202", message: "Could not find the function" } });
    await expect(retryRun(RUN_ID)).resolves.toEqual({ error: RETRY_UNAVAILABLE_MESSAGE, unavailable: true });
  });

  it("reports retry as unavailable when the database does not know the function (42883)", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "42883", message: "function does not exist" } });
    await expect(retryRun(RUN_ID)).resolves.toEqual({ error: RETRY_UNAVAILABLE_MESSAGE, unavailable: true });
  });

  it("never reports the run as failed again or claims a retry was recorded", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "42883", message: "function does not exist" } });
    const result = await retryRun(RUN_ID);
    expect(result).not.toHaveProperty("ok");
    expect(result).not.toHaveProperty("message");
  });
});

describe("retryRun when the function is installed", () => {
  it("passes a refusal from the database through without marking retry unavailable", async () => {
    rpc.mockResolvedValue({ data: null, error: { code: "22023", message: "Only failed runs can be retried" } });
    await expect(retryRun(RUN_ID)).resolves.toEqual({ error: "Only failed runs can be retried" });
  });

  it("records the retry when the database accepts it", async () => {
    rpc.mockResolvedValue({ data: "44444444-4444-4444-8444-444444444444", error: null });
    const result = await retryRun(RUN_ID);
    expect(rpc).toHaveBeenCalledWith("retry_workflow_run", { p_run: RUN_ID });
    expect(result).toEqual({
      ok: true,
      message: "Retry recorded as run 44444444. The original failure is kept.",
    });
  });
});
