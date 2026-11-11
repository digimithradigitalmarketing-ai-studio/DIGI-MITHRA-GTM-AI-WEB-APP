// Clients readiness. The database answers one read-only question through public.clients_readiness()
// (migration 0008): is the table present, is RLS on, do the policies and grants exist. The function
// returns booleans only. This module turns those booleans into a state the screens can act on, and
// it never shows the flags or any SQL to users.
//
// Why it matters: if the clients policies are missing, reads return zero rows with no error. A page
// would show "No clients yet" for a workspace that actually has clients. The readiness check keeps
// that case separate from real empty data.

export const CLIENTS_READINESS_FLAGS = [
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
  "anon_has_any_privilege",
] as const;

export type ClientsReadinessFlags = Record<(typeof CLIENTS_READINESS_FLAGS)[number], boolean>;

export type ClientsReadiness =
  | { state: "ready" }
  // Something required is missing or too open: the table, RLS, a policy, a grant, or an anon privilege.
  | { state: "not_configured" }
  // The check itself failed or returned an unexpected shape. Fail closed, but do not claim the module is unset.
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

// Pure. Requires every flag to be a boolean; anything else is "unavailable", not "ready".
export function evaluateClientsReadiness(raw: unknown): ClientsReadiness {
  if (!isFlagRecord(raw)) return { state: "unavailable" };
  const f = raw;
  const required = [
    f.table_exists,
    f.rls_enabled,
    f.policy_select,
    f.policy_insert,
    f.policy_update,
    f.policy_delete,
    f.grant_select,
    f.grant_insert,
    f.grant_update,
    f.grant_delete,
  ];
  if (!required.every(Boolean)) return { state: "not_configured" };
  // anon must hold no table privilege on clients. Any grant there is a configuration problem.
  if (f.anon_has_any_privilege) return { state: "not_configured" };
  return { state: "ready" };
}

// Pure. Returns the message a write action should show, or null when the write may proceed.
export function clientsWriteBlockMessage(readiness: ClientsReadiness): string | null {
  if (readiness.state === "ready") return null;
  return readiness.state === "not_configured" ? CLIENTS_NOT_CONFIGURED_TITLE : CLIENTS_UNAVAILABLE_BODY;
}

export type ClientListState = "not_configured" | "unavailable" | "permission_denied" | "empty" | "list";

// Pure. Decides what a Clients list should show. Order matters:
//   1. Readiness first. A missing policy must never look like empty data.
//   2. No workspace role means the user cannot read this workspace's clients.
//   3. A database error on the list read is either a permission refusal (42501) or a generic failure.
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
