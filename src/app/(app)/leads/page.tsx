import type { Metadata } from "next";
import { LeadTable } from "@/components/lead-table";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { leads } from "@/lib/data";

export const metadata: Metadata = { title: "Leads" };

export default function LeadsPage() {
  return (
    <>
      <PageHeader
        title="Leads"
        description="Prospects who enquired by Instagram, walk-in, website, referral or WhatsApp."
      />

      <div className="mb-6">
        <Notice>
          Lead creation and editing arrive in Phase 3. Creating a lead will also trigger the follow-up
          automation in Phase 5.
        </Notice>
      </div>

      <Panel>
        <LeadTable leads={leads} />
      </Panel>
    </>
  );
}
