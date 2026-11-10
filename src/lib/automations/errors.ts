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
