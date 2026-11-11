import { describe, expect, it } from "vitest";
import { can, effectiveRole } from "./roles";

describe("effectiveRole", () => {
  it("maps tenant owners and admins to admin in every workspace", () => {
    expect(effectiveRole("owner", "viewer")).toBe("admin");
    expect(effectiveRole("admin", null)).toBe("admin");
  });
  it("uses the workspace role for other tenant members", () => {
    expect(effectiveRole("member", "manager")).toBe("manager");
    expect(effectiveRole("member", null)).toBeNull();
  });
});

describe("can", () => {
  it("lets admin, manager and editor write companies but not archive them", () => {
    expect(can("manager", "companies.write")).toBe(true);
    expect(can("editor", "companies.write")).toBe(true);
    expect(can("manager", "companies.archive")).toBe(false);
    expect(can("admin", "companies.archive")).toBe(true);
  });
  it("lets support write contacts and leads, but not clients", () => {
    expect(can("support", "contacts.write")).toBe(true);
    expect(can("support", "leads.write")).toBe(true);
    expect(can("support", "clients.write")).toBe(false);
  });
  it("restricts client writes to admin", () => {
    expect(can("admin", "clients.write")).toBe(true);
    expect(can("manager", "clients.write")).toBe(false);
  });
  it("denies viewers, analysts, approvers and missing roles", () => {
    for (const role of ["viewer", "analyst", "approver", null]) {
      expect(can(role, "contacts.write")).toBe(false);
      expect(can(role, "companies.write")).toBe(false);
    }
  });
});
