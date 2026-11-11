import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CrmActionButton } from "@/components/crm/action-button";
import { DetailList } from "@/components/crm/detail";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { Badge, DataTable, Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { archivedBadge, clientStatusBadge, lifecycleBadge } from "@/lib/crm/badges";
import { can, effectiveRole } from "@/lib/crm/roles";
import { clientForCompany, contactsOfCompany, getCompany, leadsOfCompany } from "@/lib/crm/queries";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { formatDate, formatINR } from "@/lib/format";
import { archiveCompany } from "../actions";

export const metadata: Metadata = { title: "Company" };

type Params = Promise<{ id: string }>;

export default function CompanyDetailPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="company" />}>
      <CompanyDetail params={params} />
    </Suspense>
  );
}

async function CompanyDetail({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();

  const { value: company, error } = await settle(() => getCompany(id));
  if (error) {
    return (
      <>
        <PageHeader title="Company" />
        <QueryNotice error={error} />
      </>
    );
  }
  if (!company) notFound();

  const access = await loadWorkspaceAccess(company.workspace_id);
  if (!access) notFound();
  const role = effectiveRole(access.tenantRole, access.workspaceRole);
  const ws = company.workspace_id;
  const canWrite = can(role, "companies.write");
  const canArchive = can(role, "companies.archive");
  const canWriteContacts = can(role, "contacts.write");
  const canWriteLeads = can(role, "leads.write");
  const canWriteClients = can(role, "clients.write");

  const [contacts, leads, client] = await Promise.all([
    settle(() => contactsOfCompany(id)),
    settle(() => leadsOfCompany(id)),
    settle(() => clientForCompany(id)),
  ]);

  const life = lifecycleBadge(company.lifecycle);
  const archived = archivedBadge(company.archived_at);

  return (
    <>
      <PageHeader
        title={company.name}
        description={`${life.label}${company.industry ? ` · ${company.industry}` : ""}${company.city ? ` · ${company.city}` : ""}`}
        actions={
          <>
            <Link href={crmHref("/companies", { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg border border-line px-4 text-sm font-medium text-ink hover:bg-slate-50">Back to list</Link>
            {canWrite ? (
              <Link href={crmHref(`/companies/${id}/edit`, { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Edit</Link>
            ) : null}
          </>
        }
      />

      {archived ? (
        <div className="mb-6">
          <Notice tone="warning">This company is archived. It is hidden from the default list, and its history is kept.</Notice>
        </div>
      ) : null}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
        <Panel title="Details">
          <div className="mb-4 flex flex-wrap gap-2">
            <Badge tone={life.tone}>{life.label}</Badge>
            {archived ? <Badge tone={archived.tone}>{archived.label}</Badge> : null}
          </div>
          <DetailList
            items={[
              { label: "Domain", value: company.domain },
              { label: "Industry", value: company.industry },
              { label: "City", value: company.city },
              { label: "Last updated", value: formatDate(company.updated_at) },
            ]}
          />
          {company.notes ? <p className="mt-5 whitespace-pre-line text-sm text-ink">{company.notes}</p> : null}
          {canArchive ? (
            <div className="mt-6 border-t border-line pt-5">
              <CrmActionButton
                action={archiveCompany.bind(null, id, company.archived_at === null)}
                label={company.archived_at ? "Restore company" : "Archive company"}
                pendingLabel="Saving…"
                tone={company.archived_at ? "secondary" : "danger"}
                confirm={company.archived_at ? undefined : "Archive this company? It will be hidden from the default list."}
              />
            </div>
          ) : null}
        </Panel>

        <Panel title="Client">
          {client.error ? (
            <QueryNotice error={client.error} />
          ) : client.value ? (
            <div className="space-y-3">
              <div className="flex flex-wrap items-center gap-2">
                <Badge tone={clientStatusBadge(client.value.status).tone}>{clientStatusBadge(client.value.status).label}</Badge>
                <span className="text-sm text-ink-muted">{client.value.retainer_inr ? `${formatINR(client.value.retainer_inr)} a month` : "No retainer set"}</span>
              </div>
              <Link href={crmHref(`/clients/${client.value.id}`, { workspace: ws })} className="inline-flex min-h-11 items-center text-sm font-medium text-brand-700 hover:underline">Open client record</Link>
            </div>
          ) : canWriteClients ? (
            <div className="space-y-3">
              <p className="text-sm text-ink-muted">This company is not a client yet.</p>
              <Link href={crmHref("/clients/new", { workspace: ws, company: id })} className="inline-flex min-h-11 items-center text-sm font-medium text-brand-700 hover:underline">Create client record</Link>
            </div>
          ) : (
            <p className="text-sm text-ink-muted">This company is not a client yet.</p>
          )}
        </Panel>

        <Panel title="Contacts" description="People at this company, A to Z.">
          {contacts.error ? (
            <QueryNotice error={contacts.error} />
          ) : (
            <>
              <DataTable
                caption="Contacts at this company"
                headers={["Name", "Email", "Phone"]}
                emptyMessage="No contacts linked to this company."
                rows={(contacts.value ?? []).map((c) => [
                  <Link key="n" href={crmHref(`/contacts/${c.id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{c.name}</Link>,
                  c.email ?? "—",
                  c.phone ?? "—",
                ])}
              />
              {canWriteContacts ? (
                <Link href={crmHref("/contacts/new", { workspace: ws, company: id })} className="mt-4 inline-flex min-h-11 items-center text-sm font-medium text-brand-700 hover:underline">Add a contact</Link>
              ) : null}
            </>
          )}
        </Panel>

        <Panel title="Leads" description="Enquiries linked to this company.">
          {leads.error ? (
            <QueryNotice error={leads.error} />
          ) : (
            <>
              <DataTable
                caption="Leads for this company"
                headers={["Lead", "Value", "Updated"]}
                emptyMessage="No leads linked to this company."
                rightAlignColumns={[1]}
                rows={(leads.value ?? []).map((l) => [
                  <Link key="t" href={crmHref(`/leads/${l.id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{l.title}</Link>,
                  formatINR(l.value_inr),
                  formatDate(l.updated_at),
                ])}
              />
              {canWriteLeads ? (
                <Link href={crmHref("/leads/new", { workspace: ws, company: id })} className="mt-4 inline-flex min-h-11 items-center text-sm font-medium text-brand-700 hover:underline">Add a lead</Link>
              ) : null}
            </>
          )}
        </Panel>
      </div>
    </>
  );
}
