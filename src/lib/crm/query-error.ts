// Wraps a failed read so pages can show what went wrong instead of an empty list. Without this,
// a missing column or policy would look the same as a workspace with no records yet.
export class CrmQueryError extends Error {
  readonly code: string | undefined;
  constructor(scope: string, error: { code?: string; message: string }) {
    super(`${scope} read failed: ${error.message}`);
    this.name = "CrmQueryError";
    this.code = error.code;
  }
}
