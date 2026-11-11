import Link from "next/link";
import { crmHref } from "@/lib/crm/url";

export type FilterSpec = {
  name: string;
  label: string;
  value: string;
  options: { value: string; label: string }[];
};

type Props = {
  basePath: string;
  workspaceId: string;
  q: string;
  searchLabel: string;
  searchPlaceholder: string;
  filters: FilterSpec[];
  archived?: "active" | "archived" | "all";
  page: number;
  pageCount: number;
  total: number;
};

const CONTROL =
  "mt-1 block w-full min-h-11 rounded-lg border border-line bg-panel px-3 py-2 text-sm text-ink shadow-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20";

// Search, filters and pagination as a plain GET form. The page reloads with new query parameters,
// so every result is rendered on the server and no client state is needed. Changing a filter
// goes back to page 1, because the page parameter is not part of the form.
export function ListControls(props: Props) {
  const { basePath, workspaceId, q, searchLabel, searchPlaceholder, filters, archived, page, pageCount, total } = props;
  const base = { workspace: workspaceId, q, archived, ...Object.fromEntries(filters.map((f) => [f.name, f.value])) };
  const clearHref = crmHref(basePath, { workspace: workspaceId });

  return (
    <div className="space-y-4">
      <form method="get" action={basePath} role="search" className="grid gap-3 sm:grid-cols-[minmax(0,2fr)_repeat(auto-fit,minmax(10rem,1fr))_auto] sm:items-end">
        <input type="hidden" name="workspace" value={workspaceId} />
        <div className="min-w-0">
          <label htmlFor="q" className="block text-sm font-medium text-ink">{searchLabel}</label>
          <input id="q" name="q" type="search" defaultValue={q} placeholder={searchPlaceholder} maxLength={100} className={CONTROL} />
        </div>
        {filters.map((f) => (
          <div key={f.name} className="min-w-0">
            <label htmlFor={f.name} className="block text-sm font-medium text-ink">{f.label}</label>
            <select id={f.name} name={f.name} defaultValue={f.value} className={CONTROL}>
              {f.options.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
        ))}
        {archived !== undefined ? (
          <div className="min-w-0">
            <label htmlFor="archived" className="block text-sm font-medium text-ink">Records</label>
            <select id="archived" name="archived" defaultValue={archived} className={CONTROL}>
              <option value="active">Active</option>
              <option value="archived">Archived</option>
              <option value="all">All</option>
            </select>
          </div>
        ) : null}
        <div className="flex gap-2">
          <button type="submit" className="min-h-11 rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Apply</button>
          <Link href={clearHref} className="inline-flex min-h-11 items-center rounded-lg border border-line px-4 text-sm font-medium text-ink hover:bg-slate-50">Clear</Link>
        </div>
      </form>

      <nav aria-label="Pagination" className="flex items-center justify-between gap-3 text-sm text-ink-muted">
        <p>
          {total.toLocaleString("en-IN")} {total === 1 ? "result" : "results"} · page {page} of {pageCount}
        </p>
        <div className="flex gap-2">
          {page > 1 ? (
            <Link href={crmHref(basePath, { ...base, page: page - 1 })} className="inline-flex min-h-11 items-center rounded-lg border border-line px-3 font-medium text-ink hover:bg-slate-50">Previous</Link>
          ) : (
            <span aria-disabled="true" className="inline-flex min-h-11 items-center rounded-lg border border-line px-3 text-ink-muted/60">Previous</span>
          )}
          {page < pageCount ? (
            <Link href={crmHref(basePath, { ...base, page: page + 1 })} className="inline-flex min-h-11 items-center rounded-lg border border-line px-3 font-medium text-ink hover:bg-slate-50">Next</Link>
          ) : (
            <span aria-disabled="true" className="inline-flex min-h-11 items-center rounded-lg border border-line px-3 text-ink-muted/60">Next</span>
          )}
        </div>
      </nav>
    </div>
  );
}
