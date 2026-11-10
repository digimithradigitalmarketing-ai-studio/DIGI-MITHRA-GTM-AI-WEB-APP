import type { ReactNode } from "react";

// Presentational primitives. None of these hold state, so they work in both
// server and client components.

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="mb-6 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight text-ink sm:text-3xl">{title}</h1>
        {description ? <p className="mt-1 max-w-2xl text-sm text-ink-muted">{description}</p> : null}
      </div>
      {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
    </div>
  );
}

export function Panel({
  title,
  description,
  children,
  className = "",
}: {
  title?: string;
  description?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={`min-w-0 rounded-xl border border-line bg-panel p-4 shadow-sm sm:p-5 ${className}`}>
      {title ? (
        <header className="mb-4">
          <h2 className="text-base font-semibold text-ink">{title}</h2>
          {description ? <p className="mt-0.5 text-sm text-ink-muted">{description}</p> : null}
        </header>
      ) : null}
      {children}
    </section>
  );
}

export function StatCard({
  label,
  value,
  hint,
  className = "",
}: {
  label: string;
  value: string;
  hint?: string;
  className?: string;
}) {
  return (
    <div className={`rounded-xl border border-line bg-panel p-4 shadow-sm ${className}`}>
      <p className="text-sm font-medium text-ink-muted">{label}</p>
      <p className="mt-2 text-2xl font-semibold tracking-tight text-ink sm:text-3xl">{value}</p>
      {hint ? <p className="mt-1 text-xs text-ink-muted">{hint}</p> : null}
    </div>
  );
}

export type Tone = "neutral" | "brand" | "success" | "warning" | "danger" | "info";

const TONE_CLASSES: Record<Tone, string> = {
  neutral: "bg-slate-100 text-slate-700",
  brand: "bg-brand-100 text-brand-900",
  success: "bg-emerald-100 text-emerald-800",
  warning: "bg-amber-100 text-amber-900",
  danger: "bg-rose-100 text-rose-800",
  info: "bg-sky-100 text-sky-900",
};

export function Badge({ tone = "neutral", children }: { tone?: Tone; children: ReactNode }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium whitespace-nowrap ${TONE_CLASSES[tone]}`}>
      {children}
    </span>
  );
}

/**
 * Plain table. Takes string or node cells, so it can be used from server and
 * client components alike. Scrolls horizontally on narrow screens.
 */
export function DataTable({
  caption,
  headers,
  rows,
  rightAlignColumns = [],
  emptyMessage = "Nothing to show yet.",
}: {
  caption: string;
  headers: string[];
  rows: ReactNode[][];
  rightAlignColumns?: number[];
  emptyMessage?: string;
}) {
  return (
    <div className="-mx-4 overflow-x-auto sm:mx-0">
      <table className="min-w-full text-left text-sm">
        <caption className="sr-only">{caption}</caption>
        <thead>
          <tr className="border-b border-line text-xs uppercase tracking-wide text-ink-muted">
            {headers.map((h, i) => (
              <th
                key={h}
                scope="col"
                className={`px-4 py-2.5 font-semibold sm:px-3 ${rightAlignColumns.includes(i) ? "text-right" : ""}`}
              >
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.length === 0 ? (
            <tr>
              <td colSpan={headers.length} className="px-4 py-8 text-center text-ink-muted sm:px-3">
                {emptyMessage}
              </td>
            </tr>
          ) : (
            rows.map((cells, r) => (
              <tr key={r} className="border-b border-line/70 last:border-0 hover:bg-slate-50">
                {cells.map((cell, c) => (
                  <td
                    key={c}
                    className={`px-4 py-3 align-middle text-ink sm:px-3 ${rightAlignColumns.includes(c) ? "text-right tabular-nums" : ""}`}
                  >
                    {cell}
                  </td>
                ))}
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}

export function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl border border-dashed border-line bg-panel px-6 py-10 text-center">
      <p className="text-base font-semibold text-ink">{title}</p>
      <p className="mt-1 max-w-md text-sm text-ink-muted">{body}</p>
    </div>
  );
}

export function Notice({ tone = "info", children }: { tone?: Tone; children: ReactNode }) {
  return (
    <div
      role="note"
      className={`rounded-lg border px-4 py-3 text-sm ${
        tone === "warning"
          ? "border-amber-200 bg-amber-50 text-amber-900"
          : "border-sky-200 bg-sky-50 text-sky-900"
      }`}
    >
      {children}
    </div>
  );
}

export function SkeletonBlock({ className = "" }: { className?: string }) {
  return <div aria-hidden="true" className={`animate-pulse rounded-lg bg-slate-200/80 ${className}`} />;
}
