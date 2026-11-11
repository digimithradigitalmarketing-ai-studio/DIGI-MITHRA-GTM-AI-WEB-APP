// Search, filter and pagination inputs for the CRM lists. Pure functions, so the rules are unit
// tested. Query-string values are untrusted, so everything passes through here before it reaches
// a database filter.

export const PAGE_SIZE = 20;
const MAX_PAGE = 1000;
const MAX_SEARCH = 100;

export type ListParams = {
  q: string;
  page: number;
  filter: string;
  archived: "active" | "archived" | "all";
};

// Keeps letters, digits, spaces and a few punctuation marks. Removes characters that have
// meaning in PostgREST filter syntax (commas, parentheses) and escapes LIKE wildcards, so user
// text cannot widen a search or change the filter structure.
export function sanitizeSearch(raw: string | undefined): string {
  if (!raw) return "";
  return raw
    .slice(0, MAX_SEARCH)
    .replace(/[(),]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function likePattern(term: string): string {
  return `%${term.replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
}

export function parsePage(raw: string | undefined): number {
  const n = Number.parseInt(raw ?? "1", 10);
  if (!Number.isFinite(n) || n < 1) return 1;
  return Math.min(n, MAX_PAGE);
}

export function pageRange(page: number, pageSize = PAGE_SIZE): { from: number; to: number } {
  const from = (page - 1) * pageSize;
  return { from, to: from + pageSize - 1 };
}

export function pageCount(total: number, pageSize = PAGE_SIZE): number {
  return Math.max(1, Math.ceil(total / pageSize));
}

// Accepts only values from the allowed list. Anything else falls back to the default.
export function pickAllowed<T extends string>(raw: string | undefined, allowed: readonly T[], fallback: T): T {
  return (allowed as readonly string[]).includes(raw ?? "") ? (raw as T) : fallback;
}

export function parseArchived(raw: string | undefined): ListParams["archived"] {
  return pickAllowed(raw, ["active", "archived", "all"] as const, "active");
}

// Like pickAllowed, but returns "" for an unknown value, which means "no filter".
export function pickOptional(raw: string | undefined, allowed: readonly string[]): string {
  return allowed.includes(raw ?? "") ? (raw as string) : "";
}
