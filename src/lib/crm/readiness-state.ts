// Clients readiness, pure logic. No server imports, so unit tests load this file directly.
//
// The database answers through public.clients_readiness() (migration 0008). It returns booleans only.
// This module turns them into a state the screens can act on. It never shows the flags or any SQL.
//
// Why it matters: if the clients policies are missing, reads return zero rows with no error, which
// looks exactly like a workspace with no clients. The readiness check keeps those apart.

// Flags that must be true for the module to be ready.
export const CLIENTS_READINESS_REQUIRED_TRUE = [
  "table_exists",
  "rls_enabled",
  "policy_select",
  "policy_insert",
  "policy_update",
  "policy_delete",
  "grant_select",
  "grant_insert",
  "grant_update",
  "grant_delete",
  "function_security_invoker",
] as const;

// Flags that must be false. Each one is a hole that lets anonymous callers in.
export const CLIENTS_READINESS_MUST_BE_FALSE = [
  "anon_has_any_privilege",
  "anon_or_public_policy",
  "public_execute",
  "anon_execute",
] as const;

export const CLIENTS_READINESS_FLAGS = [...CLIENTS_READINESS_REQUIRED_TRUE, ...CLIENTS_READINESS_MUST_BE_FALSE] as const;

export type ClientsReadinessFlags = Record<(typeof CLIENTS_READINESS_FLAGS)[number], boolean>;

export type ClientsReadiness =
  | { state: "ready" }
  // A required piece is missing, or an anonymous path is open. Shown as "Clients module not configured".
  | { state: "not_configured" }
  // The check failed or returned an unexpected shape. Fail closed, and do not claim the module is unset.
  | { state: "unavailable" };

export const CLIENTS_NOT_CONFIGURED_TITLE = "Clients module not configured";
export const CLIENTS_NOT_CONFIGURED_BODY =
  "The clients table is not ready for this workspace yet. Ask an administrator to finish the database setup. Client records cannot be created, changed or archived until then.";
export const CLIENTS_UNAVAILABLE_BODY = "Clients could not be checked right now. Try again in a moment.";

function isFlagRecord(raw: unknown): raw is ClientsReadinessFlags {
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) return false;
  const record = raw as Record<string, unknown>;
  return CLIENTS_READINESS_FLAGS.every((key) => typeof record[key] === "boolean");
}

// Pure. Every flag must be a boolean. Anything else is "unavailable", never "ready".
export function evaluateClientsReadiness(raw: unknown): ClientsReadiness {
  if (!isFlagRecord(raw)) return { state: "unavailable" };
  const required = CLIENTS_READINESS_REQUIRED_TRUE.every((key) => raw[key] === true);
  const blocked = CLIENTS_READINESS_MUST_BE_FALSE.some((key) => raw[key] === true);
  return required && !blocked ? { state: "ready" } : { state: "not_configured" };
}

// Pure. Returns the message a write action should show, or null when the write may proceed.
export function clientsWriteBlockMessage(readiness: ClientsReadiness): string | null {
  if (readiness.state === "ready") return null;
  return readiness.state === "not_configured" ? CLIENTS_NOT_CONFIGURED_TITLE : CLIENTS_UNAVAILABLE_BODY;
}

export type ClientListState = "not_configured" | "unavailable" | "permission_denied" | "empty" | "list";

// Pure. Decides what a Clients list should show. Order matters:
//   1. Readiness first. A missing policy must never look like empty data.
//   2. No workspace role means this user cannot read the workspace's clients (checked separately from data).
//   3. A 42501 on the list read is a permission refusal. Any other error is a generic failure.
//   4. Only a clean read with zero rows is "empty".
export function classifyClientList(input: {
  readiness: ClientsReadiness;
  hasAccess: boolean;
  listError: { code?: string } | null;
  rowCount: number;
}): ClientListState {
  if (input.readiness.state === "not_configured") return "not_configured";
  if (input.readiness.state === "unavailable") return "unavailable";
  if (!input.hasAccess || input.listError?.code === "42501") return "permission_denied";
  if (input.listError) return "unavailable";
  return input.rowCount === 0 ? "empty" : "list";
}
