import { describe, expect, it } from "vitest";
import { explainError } from "./errors";

describe("explainError", () => {
  it("explains a refused permission without leaking database text", () => {
    expect(explainError({ code: "42501", message: "new row violates row-level security policy" })).toBe(
      "You do not have permission to change automations in this workspace.",
    );
  });

  it("explains a cross-tenant workspace reference", () => {
    expect(explainError({ code: "23503", message: "insert violates foreign key" })).toBe(
      "That workspace does not belong to your organisation.",
    );
  });

  it("explains a conflict and a missing run", () => {
    expect(explainError({ code: "23505", message: "duplicate key" })).toContain("conflicts");
    expect(explainError({ code: "P0002", message: "Run not found" })).toBe("That item no longer exists.");
  });

  it("passes through the database's own user-facing messages for validation and retry refusals", () => {
    expect(explainError({ code: "22023", message: "Only failed runs can be retried" })).toBe(
      "Only failed runs can be retried",
    );
  });

  it("falls back to a generic message for anything else", () => {
    expect(explainError({ message: "connection reset" })).toBe("Something went wrong. Please try again.");
  });
});
