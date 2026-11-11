// Turns database errors into messages a user can act on. SQLSTATE says which rule refused the
// change. Raw database text is shown only for check and validation errors, where the message was
// written for users. Other errors show a plain message so internal details stay out of the UI.

export type DbError = { code?: string; message: string };

export function explainCrmError(error: DbError): string {
  switch (error.code) {
    case "42501":
      return "You do not have permission to make this change.";
    case "42703":
    case "42P01":
      return "This screen needs a database update that has not been applied yet. Ask an admin to check the schema.";
    case "23503":
      return "A linked record does not belong to this workspace. Refresh the page and choose it again.";
    case "23505":
      return "This conflicts with an existing record. A company with this domain, or a company that already has a client, cannot be added again.";
    case "23514":
    case "22023":
    case "22P02":
      return "Some values are not allowed. Check the form and try again.";
    case "P0002":
      return "That record no longer exists.";
    default:
      return "Something went wrong. Please try again.";
  }
}
