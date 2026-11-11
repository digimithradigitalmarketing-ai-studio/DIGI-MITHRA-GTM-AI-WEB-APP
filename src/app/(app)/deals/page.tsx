import type { Metadata } from "next";
import { DemoBanner } from "@/components/demo-banner";
import { Badge, EmptyState, Notice, PageHeader, Panel } from "@/components/ui";
import { AS_OF, deals, tasks } from "@/lib/data";
import { DEAL_STAGES, dueTodayOrLater, overdueTasks } from "@/lib/metrics";
import { formatDate, formatINR } from "@/lib/format";
import { dealStageBadge } from "@/lib/status";

export const metadata: Metadata = { title: "Deals" };

export default function DealsPage() {
  const overdue = overdueTasks(tasks, AS_OF);
  const upcoming = dueTodayOrLater(tasks, AS_OF);

  return (
    <>
      <DemoBanner />
      <PageHeader
        title="Deals"
        description="Deals grouped by stage with totals. Moving a deal between stages arrives in Phase 4."
      />

      <div className="mb-6">
        <Notice>
          Stage totals are computed on the page from the demo records. Phase 4 moves this logic to the
          server and checks each stage change.
        </Notice>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-5">
        {DEAL_STAGES.map((stage) => {
          const inStage = deals.filter((d) => d.stage === stage);
          const total = inStage.reduce((sum, d) => sum + d.amount, 0);
          const badge = dealStageBadge(stage);
          return (
            <section
              key={stage}
              aria-labelledby={`stage-${stage}`}
              className="flex flex-col rounded-xl border border-line bg-panel p-4 shadow-sm"
            >
              <header className="mb-3 flex items-center justify-between gap-2">
                <h2 id={`stage-${stage}`} className="text-sm font-semibold text-ink">
                  {stage}
                </h2>
                <Badge tone={badge.tone}>{inStage.length}</Badge>
              </header>
              <p className="mb-3 text-lg font-semibold tabular-nums">{formatINR(total)}</p>
              {inStage.length === 0 ? (
                <p className="text-sm text-ink-muted">No deals in this stage.</p>
              ) : (
                <ul className="space-y-2">
                  {inStage.map((d) => (
                    <li key={d.id} className="rounded-lg border border-line bg-canvas px-3 py-2 text-sm">
                      <p className="font-medium text-ink">{d.title}</p>
                      <p className="text-xs text-ink-muted">
                        {d.leadName} · {d.owner}
                      </p>
                      <p className="mt-1 text-xs text-ink-muted">
                        {formatINR(d.amount)} · close {formatDate(d.expectedClose)}
                      </p>
                    </li>
                  ))}
                </ul>
              )}
            </section>
          );
        })}
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel title="Overdue tasks" description="Open tasks whose due date has passed">
          {overdue.length === 0 ? (
            <EmptyState title="Nothing overdue" body="Every open task is on schedule." />
          ) : (
            <ul className="space-y-2 text-sm">
              {overdue.map((t) => (
                <li key={t.id} className="flex flex-col rounded-lg border border-rose-100 bg-rose-50/60 px-3 py-2">
                  <span className="font-medium">{t.title}</span>
                  <span className="text-xs text-ink-muted">
                    {t.owner} · was due {formatDate(t.due)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        <Panel title="Upcoming tasks" description="Open tasks due today or later">
          {upcoming.length === 0 ? (
            <EmptyState title="No open tasks" body="Add a task from a lead or deal once Phase 4 is built." />
          ) : (
            <ul className="space-y-2 text-sm">
              {upcoming.map((t) => (
                <li key={t.id} className="flex flex-col rounded-lg border border-line px-3 py-2">
                  <span className="font-medium">{t.title}</span>
                  <span className="text-xs text-ink-muted">
                    {t.owner} · due {formatDate(t.due)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>
    </>
  );
}
