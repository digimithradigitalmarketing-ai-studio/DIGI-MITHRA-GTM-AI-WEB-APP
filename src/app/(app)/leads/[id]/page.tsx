import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CrmActionButton } from "@/components/crm/action-button";
import { DetailList } from "@/components/crm/detail";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { getLead, namesById } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { formatDate, formatINR } from "@/lib/format";
import { deleteLead } from "../actions";

export const metadata: Metadata = { title: "Lead" };

type Params = Promise<{ id: string }>;

export default function LeadDetailPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="lead" />}>
      <LeadDetail params={params} />
    </Suspense>
  );
}

async function LeadDetail({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const lead = await settle(() => getLead(id));
  if (lead.error) {
    return (
      <>
        <PageHeader title="Lead" />
        <QueryNotice error={lead.error} />
      </>
    );
  }
  const row = lead.value;
  if (!row) notFound();
  const access = await loadWorkspaceAccess(row.workspace_id);
  if (!access) notFound();

  const ws = row.workspace_id;
  const canWrite = can(effectiveRole(access.tenantRole, access.workspaceRole), "leads.write");
  const [contacts, companies, stages] = await Promise.all([
    settle(() => namesById("contacts", [row.contact_id])),
    settle(() => namesById("companies", [row.company_id])),
    settle(() => namesById("pipeline_stages", [row.stage_id])),
  ]);
  const contactName = row.contact_id ? contacts.value?.get(row.contact_id) : undefined;
  const companyName = row.company_id ? companies.value?.get(row.company_id) : undefined;
  const stageName = row.stage_id ? stages.value?.get(row.stage_id) : undefined;

  return (
    <>
      <PageHeader
        title={row.title}
        description={`${formatINR(row.value_inr)} estimated`}
        actions={
          <>
            <Link href={crmHref("/leads", { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg border border-line px-4 text-sm font-medium text-ink hover:bg-slate-50">Back to list</Link>
            {canWrite ? (
              <Link href={crmHref(`/leads/${id}/edit`, { workspace: ws })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">Edit</Link>
            ) : null}
          </>
        }
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Panel title="Details">
          <DetailList
            items={[
              { label: "Contact", value: row.contact_id ? (
                <Link href={crmHref(`/contacts/${row.contact_id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{contactName ?? "Open contact"}</Link>
              ) : null },
              { label: "Company", value: row.company_id ? (
                <Link href={crmHref(`/companies/${row.company_id}`, { workspace: ws })} className="font-medium text-brand-700 hover:underline">{companyName ?? "Open company"}</Link>
              ) : null },
              { label: "Pipeline stage", value: stageName ?? null },
              { label: "Estimated value", value: formatINR(row.value_inr) },
              { label: "Source", value: row.source },
              { label: "Event or enquiry date", value: row.event_date ? formatDate(row.event_date) : null },
              { label: "Created", value: formatDate(row.created_at) },
              { label: "Last updated", value: formatDate(row.updated_at) },
            ]}
          />
          {row.notes ? <p className="mt-5 whitespace-pre-line text-sm text-ink">{row.notes}</p> : null}
          {canWrite ? (
            <div className="mt-6 border-t border-line pt-5">
              <CrmActionButton
                action={deleteLead.bind(null, id)}
                label="Delete lead"
                pendingLabel="Deleting…"
                tone="danger"
                confirm="Delete this lead? Its deals and tasks keep their record but lose this link. This cannot be undone."
              />
            </div>
          ) : null}
        </Panel>
      </div>
    </>
  );
}
