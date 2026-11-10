import type { Metadata } from "next";
import { Badge, DataTable, Notice, PageHeader, Panel } from "@/components/ui";
import { automationRuns, automationRules } from "@/lib/data";
import { formatDate } from "@/lib/format";
import { automationRunBadge } from "@/lib/status";

export const metadata: Metadata = { title: "Automations" };

export default function AutomationsPage() {
  const ruleName = (id: string) => automationRules.find((r) => r.id === id)?.name ?? "Unknown rule";

  return (
    <>
      <PageHeader
        title="Automations"
        description="Server-side rules and their run history. Each run has an idempotency key, so repeated events are safe."
      />

      <div className="mb-6">
        <Notice>
          These rules and runs are read-only demo records. The automation engine that executes them arrives in
          Phase 5.
        </Notice>
      </div>

      <div className="grid grid-cols-1 gap-4">
        <Panel title="Rules" description="Trigger, action and whether the rule is on">
          <DataTable
            caption="Automation rules"
            headers={["Rule", "Trigger", "Action", "State"]}
            rows={automationRules.map((r) => [
              <span key="n" className="font-medium">{r.name}</span>,
              <code key="t" className="rounded bg-slate-100 px-1.5 py-0.5 font-mono text-xs">{r.trigger}</code>,
              r.action,
              <Badge key="s" tone={r.enabled ? "success" : "neutral"}>{r.enabled ? "Enabled" : "Off"}</Badge>,
            ])}
          />
        </Panel>

        <Panel title="Run log" description="Newest first. Failed runs show a readable reason and a retry state.">
          <DataTable
            caption="Automation run log"
            headers={["Date", "Rule", "Event key", "Result", "Detail"]}
            rows={automationRuns.map((run) => {
              const badge = automationRunBadge(run.status);
              return [
                formatDate(run.at),
                ruleName(run.ruleId),
                <code key="k" className="font-mono text-xs break-all">{run.eventKey}</code>,
                <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                run.message,
              ];
            })}
          />
        </Panel>
      </div>
    </>
  );
}
