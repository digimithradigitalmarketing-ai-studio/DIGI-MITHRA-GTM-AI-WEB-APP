"use client";

import { useMemo, useState } from "react";
import type { Lead, LeadSource, LeadStatus } from "@/types";
import { Badge, DataTable } from "./ui";
import { formatDate } from "@/lib/format";
import { leadStatusBadge } from "@/lib/status";

const SOURCES: LeadSource[] = ["Instagram", "Walk-in", "Website", "Referral", "WhatsApp"];
const STATUSES: LeadStatus[] = ["new", "contacted", "qualified", "lost"];

const fieldClass =
  "min-h-11 w-full rounded-lg border border-line bg-panel px-3 text-sm text-ink focus:border-brand-500";

/**
 * Searchable, filterable lead list. Filtering runs in the browser on synthetic
 * data; Phase 3 moves it to the server with pagination.
 */
export function LeadTable({ leads }: { leads: Lead[] }) {
  const [query, setQuery] = useState("");
  const [source, setSource] = useState<"all" | LeadSource>("all");
  const [status, setStatus] = useState<"all" | LeadStatus>("all");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return leads
      .filter((l) => source === "all" || l.source === source)
      .filter((l) => status === "all" || l.status === status)
      .filter((l) => q === "" || `${l.name} ${l.interest} ${l.owner}`.toLowerCase().includes(q))
      .sort((a, b) => b.createdOn.localeCompare(a.createdOn));
  }, [leads, query, source, status]);

  return (
    <div className="space-y-4">
      <form aria-label="Filter leads" className="grid grid-cols-1 gap-3 sm:grid-cols-3" onSubmit={(e) => e.preventDefault()}>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="lead-search" className="text-sm font-medium text-ink">
            Search
          </label>
          <input
            id="lead-search"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Name, interest or owner"
            autoComplete="off"
            className={fieldClass}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="lead-source" className="text-sm font-medium text-ink">
            Source
          </label>
          <select
            id="lead-source"
            value={source}
            onChange={(e) => setSource(e.target.value as "all" | LeadSource)}
            className={fieldClass}
          >
            <option value="all">All sources</option>
            {SOURCES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1.5">
          <label htmlFor="lead-status" className="text-sm font-medium text-ink">
            Status
          </label>
          <select
            id="lead-status"
            value={status}
            onChange={(e) => setStatus(e.target.value as "all" | LeadStatus)}
            className={fieldClass}
          >
            <option value="all">All statuses</option>
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {leadStatusBadge(s).label}
              </option>
            ))}
          </select>
        </div>
      </form>

      <p role="status" aria-live="polite" className="text-sm text-ink-muted">
        Showing {filtered.length} of {leads.length} leads
      </p>

      <DataTable
        caption="Leads"
        headers={["Lead", "Source", "Interest", "Owner", "Status", "Created"]}
        emptyMessage="No leads match these filters. Clear the search or choose All."
        rows={filtered.map((l) => {
          const badge = leadStatusBadge(l.status);
          return [
            <span key="n" className="font-medium">{l.name}</span>,
            l.source,
            l.interest,
            l.owner,
            <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
            formatDate(l.createdOn),
          ];
        })}
      />
    </div>
  );
}
