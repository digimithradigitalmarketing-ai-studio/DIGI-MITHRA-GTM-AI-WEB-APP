// Builds CRM list and detail links. Empty values and the default archive filter are dropped, so
// the address bar stays short. "all" and "archived" are kept, because they change the result.
export function crmHref(path: string, params: Record<string, string | number | undefined | null>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null || value === "") continue;
    if (key === "archived" && value === "active") continue;
    search.set(key, String(value));
  }
  const qs = search.toString();
  return qs ? `${path}?${qs}` : path;
}
