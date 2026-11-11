import type { ReactNode } from "react";

// Label and value pairs for a record's details. Renders as a description list, which screen
// readers announce as term and definition pairs.
export function DetailList({ items }: { items: { label: string; value: ReactNode }[] }) {
  return (
    <dl className="grid gap-x-6 gap-y-4 sm:grid-cols-2">
      {items.map((item) => (
        <div key={item.label} className="min-w-0">
          <dt className="text-xs font-medium uppercase tracking-wide text-ink-muted">{item.label}</dt>
          <dd className="mt-1 break-words text-sm text-ink">{item.value ?? "—"}</dd>
        </div>
      ))}
    </dl>
  );
}
