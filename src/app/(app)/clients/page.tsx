import type { Metadata } from "next";
import { Badge, DataTable, EmptyState, PageHeader, Panel } from "@/components/ui";
import { clients } from "@/lib/data";
import { formatDate, formatINR } from "@/lib/format";
import { clientStatusBadge } from "@/lib/status";

export const metadata: Metadata = { title: "Clients" };

export default function ClientsPage() {
  const sorted = [...clients].sort((a, b) => a.name.localeCompare(b.name));
  const monthlyRecurring = clients
    .filter((c) => c.status === "active")
    .reduce((sum, c) => sum + c.monthlyFee, 0);

  return (
    <>
      <PageHeader
        title="Clients"
        description="Members, families and corporate accounts. Records are read-only until the Phase 3 CRUD build."
      />

      <div className="mb-6 grid grid-cols-2 gap-3 sm:gap-4 md:max-w-md">
        <Panel>
          <p className="text-sm text-ink-muted">Accounts</p>
          <p className="mt-1 text-2xl font-semibold tabular-nums">{clients.length}</p>
        </Panel>
        <Panel>
          <p className="text-sm text-ink-muted">Monthly recurring</p>
          <p className="mt-1 text-2xl font-semibold tabular-nums">{formatINR(monthlyRecurring)}</p>
        </Panel>
      </div>

      <Panel title="All clients" description="Sorted by name">
        {sorted.length === 0 ? (
          <EmptyState title="No clients yet" body="Clients appear here once a lead converts." />
        ) : (
          <DataTable
            caption="Client accounts"
            headers={["Name", "Type", "Plan", "Status", "Owner", "Since", "Monthly fee"]}
            rightAlignColumns={[6]}
            rows={sorted.map((c) => {
              const badge = clientStatusBadge(c.status);
              return [
                <span key="n" className="font-medium">{c.name}</span>,
                c.type,
                c.plan,
                <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                c.owner,
                formatDate(c.since),
                c.monthlyFee === 0 ? "Not billed" : formatINR(c.monthlyFee),
              ];
            })}
          />
        )}
      </Panel>
    </>
  );
}
