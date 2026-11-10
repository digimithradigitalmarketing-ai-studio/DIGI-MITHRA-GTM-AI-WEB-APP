import type { Metadata } from "next";
import Link from "next/link";
import { Badge, DataTable, Notice, Panel, PageHeader, StatCard } from "@/components/ui";
import {
  AS_OF,
  automationRuns,
  automationRules,
  clients,
  deals,
  leads,
  tasks,
} from "@/lib/data";
import {
  conversionRate,
  countBy,
  DEAL_STAGES,
  dueTodayOrLater,
  openLeadCount,
  openPipelineValue,
  overdueTasks,
} from "@/lib/metrics";
import { formatDate, formatINR } from "@/lib/format";
import { automationRunBadge, leadStatusBadge } from "@/lib/status";

export const metadata: Metadata = { title: "Dashboard" };

export default function DashboardPage() {
  const activeMembers = clients.filter((c) => c.status === "active").length;
  const openLeads = openLeadCount(leads);
  const pipelineValue = openPipelineValue(deals);
  const wonCount = deals.filter((d) => d.stage === "Won").length;
  const rate = conversionRate(deals);
  const overdue = overdueTasks(tasks, AS_OF);
  const upcoming = dueTodayOrLater(tasks, AS_OF).slice(0, 5);

  const stageCounts = countBy(deals, (d) => d.stage);
  const maxStage = Math.max(1, ...DEAL_STAGES.map((s) => stageCounts[s] ?? 0));

  const recentLeads = [...leads]
    .sort((a, b) => b.createdOn.localeCompare(a.createdOn))
    .slice(0, 5);

  const enabledRules = automationRules.filter((r) => r.enabled).length;
  const failedRuns = automationRuns.filter((r) => r.status === "failed").length;

  return (
    <>
      <PageHeader
        title="Dashboard"
        description={`Overview as of ${formatDate(AS_OF)}. Every figure comes from the synthetic demo records.`}
      />

      <div className="mb-6">
        <Notice>
          Demo workspace for DigiMithra AI Gym. No real member, lead or payment data is stored.
        </Notice>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-5">
        <StatCard label="Active members" value={String(activeMembers)} hint="Status: active" />
        <StatCard label="Open leads" value={String(openLeads)} hint="Everything except lost" />
        <StatCard label="Open pipeline" value={formatINR(pipelineValue)} hint="Enquiry, trial and proposal" />
        <StatCard label="Won deals" value={String(wonCount)} hint="All time in demo data" />
        <StatCard
          label="Overdue tasks"
          value={String(overdue.length)}
          hint={rate === null ? "No closed deals yet" : `Win rate ${Math.round(rate * 100)}%`}
          className="col-span-2 lg:col-span-1"
        />
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Panel title="Pipeline by stage" description="Deal count per stage" className="lg:col-span-2">
          <ul className="space-y-3">
            {DEAL_STAGES.map((stage) => {
              const count = stageCounts[stage] ?? 0;
              const pct = Math.round((count / maxStage) * 100);
              return (
                <li key={stage} className="grid grid-cols-[6rem_1fr_2.5rem] items-center gap-3 text-sm">
                  <span className="text-ink-muted">{stage}</span>
                  <span className="h-2.5 overflow-hidden rounded-full bg-slate-100" aria-hidden="true">
                    <span className="block h-full rounded-full bg-brand-500" style={{ width: `${pct}%` }} />
                  </span>
                  <span className="text-right font-semibold tabular-nums">{count}</span>
                </li>
              );
            })}
          </ul>
          <p className="mt-4 text-sm">
            <Link href="/deals" className="font-medium text-brand-700 hover:underline">
              Open the deal board
            </Link>
          </p>
        </Panel>

        <Panel
          title="Tasks"
          description={`${overdue.length} overdue, ${upcoming.length} coming up`}
        >
          {overdue.length > 0 ? (
            <div className="mb-4">
              <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-rose-700">Overdue</p>
              <ul className="space-y-2">
                {overdue.map((t) => (
                  <li key={t.id} className="flex flex-col rounded-lg border border-rose-100 bg-rose-50/60 px-3 py-2 text-sm">
                    <span className="font-medium text-ink">{t.title}</span>
                    <span className="text-xs text-ink-muted">
                      {t.owner} · due {formatDate(t.due)}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
          <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink-muted">Next up</p>
          <ul className="space-y-2">
            {upcoming.map((t) => (
              <li key={t.id} className="flex flex-col rounded-lg border border-line px-3 py-2 text-sm">
                <span className="font-medium text-ink">{t.title}</span>
                <span className="text-xs text-ink-muted">
                  {t.owner} · due {formatDate(t.due)}
                </span>
              </li>
            ))}
          </ul>
        </Panel>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Panel title="Recent leads" className="lg:col-span-2">
          <DataTable
            caption="Five most recent leads"
            headers={["Lead", "Source", "Status", "Created"]}
            rows={recentLeads.map((l) => {
              const badge = leadStatusBadge(l.status);
              return [
                <span key="n" className="font-medium">{l.name}</span>,
                l.source,
                <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                <span key="d" className="whitespace-nowrap">{formatDate(l.createdOn)}</span>,
              ];
            })}
          />
        </Panel>

        <Panel title="Automation health" description="Server-side rules">
          <dl className="grid grid-cols-2 gap-4 text-sm">
            <div>
              <dt className="text-ink-muted">Rules enabled</dt>
              <dd className="mt-1 text-xl font-semibold tabular-nums">{enabledRules}</dd>
            </div>
            <div>
              <dt className="text-ink-muted">Failed runs</dt>
              <dd className="mt-1 text-xl font-semibold tabular-nums">{failedRuns}</dd>
            </div>
          </dl>
          <ul className="mt-4 space-y-2 text-sm">
            {automationRuns.slice(0, 3).map((run) => {
              const badge = automationRunBadge(run.status);
              return (
                <li key={run.id} className="flex items-start justify-between gap-2">
                  <span className="text-ink-muted">{formatDate(run.at)}</span>
                  <Badge tone={badge.tone}>{badge.label}</Badge>
                </li>
              );
            })}
          </ul>
          <p className="mt-4 text-sm">
            <Link href="/automations" className="font-medium text-brand-700 hover:underline">
              View automation log
            </Link>
          </p>
        </Panel>
      </div>
    </>
  );
}
