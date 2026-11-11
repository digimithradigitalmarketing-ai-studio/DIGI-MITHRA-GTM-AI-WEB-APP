import type { Metadata } from "next";
import { Suspense } from "react";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { RecordForm } from "@/components/crm/record-form";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { leadDefaults, leadFields } from "@/lib/crm/form-fields";
import { companyOptions, contactOptions, stageOptions } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { createLead } from "../actions";

export const metadata: Metadata = { title: "New lead" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function NewLeadPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <NewLeadForm searchParams={searchParams} />
    </Suspense>
  );
}

async function NewLeadForm({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { current } = await loadAutomationContext(sp.workspace);
  if (!current) return <Notice tone="warning">Your account is not a member of a workspace.</Notice>;

  if (!can(effectiveRole(current.tenantRole, current.workspaceRole), "leads.write")) {
    return (
      <>
        <PageHeader title="New lead" />
        <Notice tone="warning">Your role cannot add leads. Ask a workspace member with editor access or above.</Notice>
      </>
    );
  }

  const [contacts, companies, stages] = await Promise.all([
    settle(() => contactOptions(current.workspaceId)),
    settle(() => companyOptions(current.workspaceId)),
    settle(() => stageOptions(current.workspaceId)),
  ]);
  const failed = contacts.error ?? companies.error ?? stages.error;
  if (failed) return <QueryNotice error={failed} />;

  const companyId = sp.company && isUuid(sp.company) ? sp.company : undefined;
  const contactId = sp.contact && isUuid(sp.contact) ? sp.contact : undefined;

  return (
    <>
      <PageHeader title="New lead" description="Record an enquiry. Saving it can start an active follow-up automation." />
      <Panel>
        <RecordForm
          action={createLead.bind(null, current.workspaceId)}
          fields={leadFields({ contacts: contacts.value ?? [], companies: companies.value ?? [], stages: stages.value ?? [] })}
          defaults={leadDefaults(null, { companyId, contactId })}
          submitLabel="Create lead"
          pendingLabel="Creating…"
          cancelHref={crmHref("/leads", { workspace: current.workspaceId })}
        />
      </Panel>
    </>
  );
}
