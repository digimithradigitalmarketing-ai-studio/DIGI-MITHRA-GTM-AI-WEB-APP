// Turns database errors into messages a user can act on. The SQLSTATE says which rule refused the
// change: a policy or require_ws_role (42501), a composite foreign key (23503), a unique key
// (23505), a missing run (P0002), or a validator or retry rule (22023). Raw database text is shown
// only for 22023, where the database raises its own user-facing messages.

export type DbError = { code?: string; message: string };

export function explainError(error: DbError): string {
  switch (error.code) {
    case "42501":
      return "You do not have permission to change automations in this workspace.";
    case "23503":
      return "That workspace does not belong to your organisation.";
    case "23505":
      return "This change conflicts with an existing record. Refresh the page and try again.";
    case "P0002":
      return "That item no longer exists.";
    case "22023":
      return error.message;
    default:
      return "Something went wrong. Please try again.";
  }
}

// PostgREST (PGRST202) and the database (42883) both report a function that is not installed.
// Retry is the one feature that depends on retry_workflow_run, so a missing function means retry
// is unavailable in this database, not that the run is broken.
const FUNCTION_MISSING_CODES = new Set(["42883", "PGRST202"]);

export function isFunctionMissing(error: DbError): boolean {
  return FUNCTION_MISSING_CODES.has(error.code ?? "");
}

export const RETRY_UNAVAILABLE_MESSAGE =
  "Automation retry is unavailable in this workspace until the database retry function is installed. The original failure is kept, and nothing was changed.";
