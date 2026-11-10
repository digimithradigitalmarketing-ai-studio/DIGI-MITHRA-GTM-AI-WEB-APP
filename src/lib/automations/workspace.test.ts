import { describe, expect, it } from "vitest";
import type { Membership } from "@/lib/access";
import { canManageWorkflows, findWorkspaceAccess, listWorkspaceAccess, pickWorkspace } from "./workspace";

const TENANT_A = "a1000000-0000-4000-8000-00000000000a";
const TENANT_B = "b1000000-0000-4000-8000-00000000000b";
const WS_A1 = "a2000000-0000-4000-8000-0000000000a1";
const WS_A2 = "a2000000-0000-4000-8000-0000000000a2";
const WS_B1 = "b2000000-0000-4000-8000-0000000000b1";

const memberships: Membership[] = [
  {
    tenantId: TENANT_A,
    tenantName: "Tenant A",
    tenantRole: "viewer",
    workspaces: [
      { id: WS_A1, name: "A1", role: "manager" },
      { id: WS_A2, name: "A2", role: "viewer" },
    ],
  },
  {
    tenantId: TENANT_B,
    tenantName: "Tenant B",
    tenantRole: "owner",
    workspaces: [{ id: WS_B1, name: "B1", role: "viewer" }],
  },
];

describe("canManageWorkflows", () => {
  it.each([
    ["owner", "viewer", true],
    ["admin", "viewer", true],
    ["viewer", "admin", true],
    ["viewer", "manager", true],
    ["viewer", "editor", false],
    ["viewer", "viewer", false],
    ["viewer", "support", false],
    ["member", "analyst", false],
  ])("tenant %s, workspace %s → %s", (tenantRole, workspaceRole, expected) => {
    expect(canManageWorkflows(tenantRole, workspaceRole)).toBe(expected);
  });
});

describe("listWorkspaceAccess", () => {
  it("flattens every workspace across tenants and marks who can manage", () => {
    const all = listWorkspaceAccess(memberships);
    expect(all.map((w) => [w.workspaceId, w.canManage])).toEqual([
      [WS_A1, true],
      [WS_A2, false],
      [WS_B1, true],
    ]);
  });
});

describe("findWorkspaceAccess", () => {
  it("returns the caller's access to a workspace they belong to", () => {
    expect(findWorkspaceAccess(memberships, WS_A1)?.workspaceRole).toBe("manager");
  });

  it("returns null for a workspace in another tenant, so tenant A's id yields nothing for tenant B's user", () => {
    const tenantBOnly: Membership[] = [memberships[1]];
    expect(findWorkspaceAccess(tenantBOnly, WS_A1)).toBeNull();
  });

  it("returns null for an unknown workspace", () => {
    expect(findWorkspaceAccess(memberships, "c2000000-0000-4000-8000-0000000000c1")).toBeNull();
  });
});

describe("pickWorkspace", () => {
  const all = listWorkspaceAccess(memberships);

  it("uses the requested workspace when the caller can see it", () => {
    expect(pickWorkspace(all, WS_A2)?.workspaceId).toBe(WS_A2);
  });

  it("falls back to the first workspace for an unknown or missing request", () => {
    expect(pickWorkspace(all, "c2000000-0000-4000-8000-0000000000c1")?.workspaceId).toBe(WS_A1);
    expect(pickWorkspace(all, undefined)?.workspaceId).toBe(WS_A1);
  });

  it("returns null when the caller belongs to no workspace", () => {
    expect(pickWorkspace([], undefined)).toBeNull();
  });
});
