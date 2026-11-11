import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CrmActionButton } from "@/components/crm/action-button";
import { DetailList } from "@/components/crm/detail";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { ClientsModuleNotice } from "@/components/crm/clients-module-notice";
import { Badge, Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { archivedBadge, clientStatusBadge } from "@/lib/crm/badges";
import { getClient, namesById } from "@/lib/crm/queries";
import { loadClientsReadiness } from "@/lib/crm/readiness";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { formatDate, formatINR } from "@/lib/format";
import { archiveClient } from "../actions";

export const metadata: Metadata = { title: "Client" };

type Params = Promise<{ id: string }>;

export default function ClientDetailPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="client" />}>
      <ClientDetail params={params} />
    </Suspense>
  );
}

async function ClientDetail({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const readiness = await loadClientsReadiness();
  if (readiness.state !== "ready") {
    return (
      <>
        <PageHeader title="Client" />
        <ClientsModuleNotice state={readiness.state} />
      </>
    );
  }
  const client = await settle(() => getClient(id));
  if (client.error) {
    return (
      <>
        <PageHeader title="Client" />
        <QueryNotice error={client.error} />
      </>
    );
  }
  const row = client.value;
  if (!row) notFound();
  const access = await loadWorkspaceAccess(row.workspace_id);
  if (!access) notFound();

  const ws = row.workspace_id;
  const role = effectiveRole(access.tenantRole, access.workspaceRole);
  const canWrite = can(role, "clients.write");
  const [companies, contacts] = await Promise.all([
    settle(() => namesById("companies", [row.company_id])),
    settle(() => namesById("contacts", [row.primary_contact_id])),
  ]);
  const companyName = companies.value?.get(row.company_id);
  const contactName = row.primary_contact_id ? contacts.value?.get(row.primary_contact_id) : undefined;
  const status = clientStatusBadge(row.status);
  const archived = archivedBadge(row.archived_at);

  return (
    <>
      <PageHeader
        title={companyName ?? "Client"}
        description={`${status.label} client`}
        actions={
          <>
            <Link href={crmHref("/clients", { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg border border-line px-4 text-sm font-medium text-ink hover:bg-slate-50">Back to list</Link>
            {canWrite ? (
              <Link href={crmHref(`/clients/${id}/edit`, { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Edit</Link>
            ) : null}
          </>
        }
      />

      {archived ? (
        <div className="mb-6">
          <Notice tone="warning">This client is archived and hidden from the default list. Its history is kept.</Notice>
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Account">
          <div className="mb-4 flex flex-wrap gap-2">
            <Badge tone={status.tone}>{status.label}</Badge>
            {archived ? <Badge tone={archived.tone}>{archived.label}</Badge> : null}
          </div>
          <DetailList
            items={[
              { label: "Company", value: (
                <Link href={crmHref(`/companies/${row.company_id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{companyName ?? "Open company"}</Link>
              ) },
              { label: "Primary contact", value: row.primary_contact_id ? (
                <Link href={crmHref(`/contacts/${row.primary_contact_id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{contactName ?? "Open contact"}</Link>
              ) : null },
              { label: "Monthly retainer", value: row.retainer_inr ? formatINR(row.retainer_inr) : null },
              { label: "Services", value: row.services },
              { label: "Started", value: row.started_on ? formatDate(row.started_on) : null },
              { label: "Ended", value: row.ended_on ? formatDate(row.ended_on) : null },
              { label: "Last updated", value: formatDate(row.updated_at) },
            ]}
          />
          {row.notes ? <p className="mt-5 whitespace-pre-line text-sm text-ink">{row.notes}</p> : null}
          {canWrite ? (
            <div className="mt-6 border-t border-line pt-5">
              <CrmActionButton
                action={archiveClient.bind(null, id, row.archived_at === null)}
                label={row.archived_at ? "Restore client" : "Archive client"}
                pendingLabel="Saving…"
                tone={row.archived_at ? "secondary" : "danger"}
                confirm={row.archived_at ? undefined : "Archive this client? It will be hidden from the default list."}
              />
            </div>
          ) : (
            <p className="mt-6 text-sm text-ink-muted">Only workspace admins can change clients.</p>
          )}
        </Panel>
      </div>
    </>
  );
}
