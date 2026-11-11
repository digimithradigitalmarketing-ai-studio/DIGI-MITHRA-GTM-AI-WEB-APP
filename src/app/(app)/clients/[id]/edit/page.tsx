import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { RecordForm } from "@/components/crm/record-form";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { clientDefaults, clientFields } from "@/lib/crm/form-fields";
import { companyOptions, contactOptions, getClient } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { updateClient } from "../../actions";

export const metadata: Metadata = { title: "Edit client" };

type Params = Promise<{ id: string }>;

export default function EditClientPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <EditClientForm params={params} />
    </Suspense>
  );
}

async function EditClientForm({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const client = await settle(() => getClient(id));
  if (client.error) return <QueryNotice error={client.error} />;
  const row = client.value;
  if (!row) notFound();
  const access = await loadWorkspaceAccess(row.workspace_id);
  if (!access) notFound();

  if (!can(effectiveRole(access.tenantRole, access.workspaceRole), "clients.write")) {
    return (
      <>
        <PageHeader title="Edit client" />
        <Notice tone="warning">Only workspace admins can change clients.</Notice>
      </>
    );
  }

  const [companies, contacts] = await Promise.all([
    settle(() => companyOptions(row.workspace_id, { excludeWithClient: true, keepId: row.company_id })),
    settle(() => contactOptions(row.workspace_id)),
  ]);
  const failed = companies.error ?? contacts.error;
  if (failed) return <QueryNotice error={failed} />;

  return (
    <>
      <PageHeader title="Edit client" description="The company on a client record cannot be changed here. Create a new client for a different company." />
      <Panel>
        <RecordForm
          action={updateClient.bind(null, id)}
          fields={clientFields({ companies: companies.value ?? [], contacts: contacts.value ?? [] })}
          defaults={clientDefaults(row)}
          submitLabel="Save changes"
          pendingLabel="Saving…"
          cancelHref={crmHref(`/clients/${id}`, { workspace: row.workspace_id })}
        />
      </Panel>
    </>
  );
}
