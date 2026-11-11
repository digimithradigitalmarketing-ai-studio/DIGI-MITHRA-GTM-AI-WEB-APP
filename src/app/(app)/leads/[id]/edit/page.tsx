import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { RecordForm } from "@/components/crm/record-form";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { leadDefaults, leadFields } from "@/lib/crm/form-fields";
import { companyOptions, contactOptions, getLead, stageOptions } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { updateLead } from "../../actions";

export const metadata: Metadata = { title: "Edit lead" };

type Params = Promise<{ id: string }>;

export default function EditLeadPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <EditLeadForm params={params} />
    </Suspense>
  );
}

async function EditLeadForm({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const lead = await settle(() => getLead(id));
  if (lead.error) return <QueryNotice error={lead.error} />;
  const row = lead.value;
  if (!row) notFound();
  const access = await loadWorkspaceAccess(row.workspace_id);
  if (!access) notFound();

  if (!can(effectiveRole(access.tenantRole, access.workspaceRole), "leads.write")) {
    return (
      <>
        <PageHeader title="Edit lead" description={row.title} />
        <Notice tone="warning">Your role can view this lead but cannot change it.</Notice>
      </>
    );
  }

  const [contacts, companies, stages] = await Promise.all([
    settle(() => contactOptions(row.workspace_id)),
    settle(() => companyOptions(row.workspace_id, { keepId: row.company_id })),
    settle(() => stageOptions(row.workspace_id)),
  ]);
  const failed = contacts.error ?? companies.error ?? stages.error;
  if (failed) return <QueryNotice error={failed} />;

  return (
    <>
      <PageHeader title="Edit lead" description={row.title} />
      <Panel>
        <RecordForm
          action={updateLead.bind(null, id)}
          fields={leadFields({ contacts: contacts.value ?? [], companies: companies.value ?? [], stages: stages.value ?? [] })}
          defaults={leadDefaults(row)}
          submitLabel="Save changes"
          pendingLabel="Saving…"
          cancelHref={crmHref(`/leads/${id}`, { workspace: row.workspace_id })}
        />
      </Panel>
    </>
  );
}
