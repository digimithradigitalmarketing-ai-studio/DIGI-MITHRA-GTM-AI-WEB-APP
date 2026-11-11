import type { Metadata } from "next";
import { DemoBanner } from "@/components/demo-banner";
import { CsvDownloadButton } from "@/components/csv-download-button";
import { Badge, DataTable, Panel, PageHeader, StatCard } from "@/components/ui";
import { AS_OF, automationRuns, deals, leads, tasks } from "@/lib/data";
import {
  conversionRate,
  countBy,
  DEAL_STAGES,
  openPipelineValue,
  overdueTasks,
} from "@/lib/metrics";
import { formatDate, formatINR } from "@/lib/format";
import { dealStageBadge, leadStatusBadge } from "@/lib/status";

export const metadata: Metadata = { title: "Reports" };

export default function ReportsPage() {
  const rate = conversionRate(deals);
  const leadCounts = countBy(leads, (l) => l.status);
  const stageCounts = countBy(deals, (d) => d.stage);
  const stageValues = DEAL_STAGES.map((stage) =>
    deals.filter((d) => d.stage === stage).reduce((sum, d) => sum + d.amount, 0),
  );
  const failedRuns = automationRuns.filter((r) => r.status === "failed").length;

  const csvRows: string[][] = [
    ["Name", "Source", "Interest", "Owner", "Status", "Created"],
    ...leads.map((l) => [l.name, l.source, l.interest, l.owner, l.status, l.createdOn]),
  ];

  return (
    <>
      <DemoBanner />
      <PageHeader
        title="Reports"
        description={`Figures as of ${formatDate(AS_OF)}. Each metric is defined below so the numbers can be checked.`}
      />

      <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
        <StatCard label="Leads" value={String(leads.length)} hint={`${leadCounts.qualified ?? 0} qualified`} />
        <StatCard label="Pipeline value" value={formatINR(openPipelineValue(deals))} hint="Open deals only" />
        <StatCard
          label="Conversion rate"
          value={rate === null ? "n/a" : `${Math.round(rate * 100)}%`}
          hint="Won ÷ (won + lost)"
        />
        <StatCard
          label="Overdue tasks"
          value={String(overdueTasks(tasks, AS_OF).length)}
          hint={`${failedRuns} failed automation run${failedRuns === 1 ? "" : "s"}`}
        />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel title="Deals by stage" description="Count and value per stage">
          <DataTable
            caption="Deals by stage"
            headers={["Stage", "Deals", "Value"]}
            rightAlignColumns={[1, 2]}
            rows={DEAL_STAGES.map((stage, i) => {
              const badge = dealStageBadge(stage);
              return [
                <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                String(stageCounts[stage] ?? 0),
                formatINR(stageValues[i]),
              ];
            })}
          />
        </Panel>

        <Panel title="Leads by status" description="Count per status">
          <DataTable
            caption="Leads by status"
            headers={["Status", "Leads"]}
            rightAlignColumns={[1]}
            rows={(["new", "contacted", "qualified", "lost"] as const).map((status) => {
              const badge = leadStatusBadge(status);
              return [
                <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                String(leadCounts[status] ?? 0),
              ];
            })}
          />
        </Panel>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel title="Export" description="Exports the lead list shown in this report. Only signed-in users with access can export in later phases.">
          <CsvDownloadButton filename="digimithra-leads.csv" rows={csvRows} label="Download leads CSV" />
        </Panel>

        <Panel title="Metric definitions">
          <dl className="space-y-3 text-sm">
            <div>
              <dt className="font-semibold text-ink">Conversion rate</dt>
              <dd className="text-ink-muted">Won deals divided by closed deals (won plus lost). Shown as n/a until a deal closes.</dd>
            </div>
            <div>
              <dt className="font-semibold text-ink">Pipeline value</dt>
              <dd className="text-ink-muted">Sum of amounts for deals in Enquiry, Trial or Proposal.</dd>
            </div>
            <div>
              <dt className="font-semibold text-ink">Overdue tasks</dt>
              <dd className="text-ink-muted">Open tasks whose due date is before the report date.</dd>
            </div>
          </dl>
        </Panel>
      </div>
    </>
  );
}
