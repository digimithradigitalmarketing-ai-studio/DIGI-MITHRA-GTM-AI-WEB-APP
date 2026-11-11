import type { Metadata } from "next";
import { DemoBanner } from "@/components/demo-banner";
import { AssistantPanel } from "@/components/assistant-panel";
import { PageHeader, Notice } from "@/components/ui";
import { deals, leads, ORGANIZATION } from "@/lib/data";

export const metadata: Metadata = { title: "AI assistant" };

export default function AiPage() {
  return (
    <>
      <DemoBanner />
      <PageHeader
        title="AI assistant"
        description="Summaries and draft messages for leads. A person reviews every draft before anything goes out."
      />

      <div className="mb-6">
        <Notice>
          Running in mock mode. Replies are built from templates, so no API key is needed and no data leaves this
          app. Provider integration with usage limits arrives in Phase 6.
        </Notice>
      </div>

      <AssistantPanel leads={leads} deals={deals} gymName={ORGANIZATION.name} />
    </>
  );
}
