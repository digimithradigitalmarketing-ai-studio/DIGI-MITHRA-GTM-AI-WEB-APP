// Route ids are checked before they reach the database. Without this, /automations/runs would be
// read as a workflow id and fail with a Postgres type error instead of a clean 404.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: string): boolean {
  return UUID.test(value);
}
