import type { Metadata } from "next";
import { DemoBanner } from "@/components/demo-banner";
import { Badge, DataTable, Notice, PageHeader, Panel } from "@/components/ui";
import { campaigns } from "@/lib/data";
import { campaignsAwaitingApproval } from "@/lib/metrics";
import { campaignStatusBadge } from "@/lib/status";

export const metadata: Metadata = { title: "Campaigns" };

export default function CampaignsPage() {
  const awaiting = campaignsAwaitingApproval(campaigns);

  return (
    <>
      <DemoBanner />
      <PageHeader
        title="Campaigns"
        description="Draft campaigns, target segments and approval status. Nothing is sent from this screen."
      />

      <div className="mb-6 space-y-3">
        <Notice tone="warning">
          Sending is disabled by default. In the MVP, campaigns are drafted and approved here, then exported
          manually. Opt-out and suppression checks are added in Phase 7.
        </Notice>
        <p className="text-sm text-ink-muted">
          {awaiting} campaign{awaiting === 1 ? "" : "s"} waiting for approval.
        </p>
      </div>

      <Panel title="All campaigns">
        <DataTable
          caption="Campaign drafts and approval status"
          headers={["Campaign", "Channel", "Segment", "Audience", "Status", "Approved by"]}
          rightAlignColumns={[3]}
          rows={campaigns.map((c) => {
            const badge = campaignStatusBadge(c.status);
            return [
              <span key="n" className="font-medium">{c.name}</span>,
              c.channel,
              c.segment,
              String(c.audience),
              <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
              c.approvedBy ?? "Not yet approved",
            ];
          })}
        />
      </Panel>
    </>
  );
}
