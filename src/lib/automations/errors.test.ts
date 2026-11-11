import { describe, expect, it } from "vitest";
import { explainError, isFunctionMissing, RETRY_UNAVAILABLE_MESSAGE } from "./errors";

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

describe("isFunctionMissing", () => {
  it("treats a missing function as missing, from PostgREST or the database", () => {
    expect(isFunctionMissing({ code: "PGRST202", message: "Could not find the function" })).toBe(true);
    expect(isFunctionMissing({ code: "42883", message: "function retry_workflow_run does not exist" })).toBe(true);
  });

  it("does not treat a refused or failed call as a missing function", () => {
    expect(isFunctionMissing({ code: "42501", message: "permission denied" })).toBe(false);
    expect(isFunctionMissing({ code: "22023", message: "Only failed runs can be retried" })).toBe(false);
    expect(isFunctionMissing({ message: "connection reset" })).toBe(false);
  });

  it("explains that retry is unavailable, not that the run failed again", () => {
    expect(RETRY_UNAVAILABLE_MESSAGE).toContain("Automation retry is unavailable");
  });
});
