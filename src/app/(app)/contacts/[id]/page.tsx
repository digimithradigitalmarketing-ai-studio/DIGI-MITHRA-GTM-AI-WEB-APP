import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CrmActionButton } from "@/components/crm/action-button";
import { DetailList } from "@/components/crm/detail";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { DataTable, Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { getContact, leadsOfContact, namesById } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { formatDate, formatINR } from "@/lib/format";
import { deleteContact } from "../actions";

export const metadata: Metadata = { title: "Contact" };

type Params = Promise<{ id: string }>;

export default function ContactDetailPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="contact" />}>
      <ContactDetail params={params} />
    </Suspense>
  );
}

async function ContactDetail({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const contact = await settle(() => getContact(id));
  if (contact.error) {
    return (
      <>
        <PageHeader title="Contact" />
        <QueryNotice error={contact.error} />
      </>
    );
  }
  if (!contact.value) notFound();
  const row = contact.value;
  const access = await loadWorkspaceAccess(row.workspace_id);
  if (!access) notFound();

  const ws = row.workspace_id;
  const role = effectiveRole(access.tenantRole, access.workspaceRole);
  const canWrite = can(role, "contacts.write");
  const [company, leads] = await Promise.all([
    settle(() => namesById("companies", [row.company_id])),
    settle(() => leadsOfContact(id)),
  ]);
  const companyName = row.company_id ? company.value?.get(row.company_id) ?? null : null;

  return (
    <>
      <PageHeader
        title={row.name}
        description={companyName ? `Contact at ${companyName}` : "Contact"}
        actions={
          <>
            <Link href={crmHref("/contacts", { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg border border-line px-4 text-sm font-medium text-ink hover:bg-slate-50">Back to list</Link>
            {canWrite ? (
              <Link href={crmHref(`/contacts/${id}/edit`, { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Edit</Link>
            ) : null}
          </>
        }
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Details">
          <DetailList
            items={[
              { label: "Email", value: row.email },
              { label: "Phone", value: row.phone },
              { label: "Social handle", value: row.handle },
              { label: "Company", value: row.company_id ? (companyName ?? (company.error ? "Unavailable" : "Not visible")) : null },
              { label: "Source", value: row.source },
              { label: "Tags", value: row.tags.length ? row.tags.join(", ") : null },
              { label: "Marketing consent", value: row.marketing_consent ? "Yes" : "No" },
              { label: "Added", value: formatDate(row.created_at) },
            ]}
          />
          {row.notes ? <p className="mt-5 whitespace-pre-line text-sm text-ink">{row.notes}</p> : null}
          {canWrite ? (
            <div className="mt-6 border-t border-line pt-5">
              <CrmActionButton
                action={deleteContact.bind(null, id)}
                label="Delete contact"
                pendingLabel="Deleting…"
                tone="danger"
                confirm="Delete this contact? Linked leads keep their record but lose this contact. This cannot be undone."
              />
            </div>
          ) : null}
        </Panel>

        <Panel title="Leads" description="Enquiries from this contact.">
          {leads.error ? (
            <QueryNotice error={leads.error} />
          ) : (
            <DataTable
              caption="Leads for this contact"
              headers={["Lead", "Value", "Updated"]}
              emptyMessage="No leads linked to this contact."
              rightAlignColumns={[1]}
              rows={(leads.value ?? []).map((l) => [
                <Link key="t" href={crmHref(`/leads/${l.id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{l.title}</Link>,
                formatINR(l.value_inr),
                formatDate(l.updated_at),
              ])}
            />
          )}
          {canWrite ? (
            <Link href={crmHref("/leads/new", { workspace: ws, contact: id })} className="mt-4 inline-flex min-h-11 items-center text-sm font-medium text-brand-700 hover:underline">Add a lead for this contact</Link>
          ) : null}
        </Panel>

        {!canWrite ? <Notice tone="info">Your role can view contacts but cannot change them.</Notice> : null}
      </div>
    </>
  );
}
