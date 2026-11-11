import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ListControls } from "@/components/crm/list-controls";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { WorkspaceSwitcher } from "@/components/crm/workspace-switcher";
import { DataTable, EmptyState, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { listLeads, namesById, stageOptions } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { pageCount, parsePage, sanitizeSearch } from "@/lib/crm/search";
import { crmHref } from "@/lib/crm/url";
import { formatDate, formatINR } from "@/lib/format";

export const metadata: Metadata = { title: "Leads" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function LeadsPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="leads" />}>
      <LeadList searchParams={searchParams} />
    </Suspense>
  );
}

async function LeadList({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { workspaces, current } = await loadAutomationContext(sp.workspace);
  const description = "Prospects who enquired by Instagram, walk-in, website, referral or WhatsApp. New leads start the follow-up automation when one is active.";

  if (!current) {
    return (
      <>
        <PageHeader title="Leads" description={description} />
        <EmptyState title="No workspace yet" body="Your account is not a member of a workspace. Ask an admin to add you." />
      </>
    );
  }

  const role = effectiveRole(current.tenantRole, current.workspaceRole);
  const canWrite = can(role, "leads.write");
  const stageFilter = sp.stage && isUuid(sp.stage) ? sp.stage : "";
  const params = { q: sanitizeSearch(sp.q), page: parsePage(sp.page) };

  const [result, stages] = await Promise.all([
    settle(() => listLeads(current.workspaceId, { ...params, filter: "", archived: "active", stageId: stageFilter || undefined })),
    settle(() => stageOptions(current.workspaceId)),
  ]);
  const rows = result.value?.rows ?? [];
  const [contacts, companies] = await Promise.all([
    settle(() => namesById("contacts", rows.map((r) => r.contact_id))),
    settle(() => namesById("companies", rows.map((r) => r.company_id))),
  ]);
  const stageName = (id: string | null) => stages.value?.find((s) => s.id === id)?.name ?? "—";

  return (
    <>
      <PageHeader
        title="Leads"
        description={description}
        actions={
          canWrite ? (
            <Link href={crmHref("/leads/new", { workspace: current.workspaceId })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">
              New lead
            </Link>
          ) : null
        }
      />
      <WorkspaceSwitcher basePath="/leads" workspaces={workspaces} currentId={current.workspaceId} />

      <Panel>
        <ListControls
          basePath="/leads"
          workspaceId={current.workspaceId}
          q={params.q}
          searchLabel="Search by title"
          searchPlaceholder="Lead title"
          filters={[
            {
              name: "stage",
              label: "Pipeline stage",
              value: stageFilter,
              options: [{ value: "", label: "All stages" }, ...(stages.value ?? []).map((s) => ({ value: s.id, label: s.name }))],
            },
          ]}
          page={params.page}
          pageCount={pageCount(result.value?.total ?? 0)}
          total={result.value?.total ?? 0}
        />

        <div className="mt-5">
          {result.error ? (
            <QueryNotice error={result.error} />
          ) : (
            <DataTable
              caption="Leads"
              headers={["Lead", "Contact", "Company", "Stage", "Value", "Updated", ""]}
              emptyMessage={params.q || stageFilter ? "No leads match these filters." : "No leads yet. Add one or wait for an enquiry."}
              rightAlignColumns={[4]}
              rows={rows.map((l) => [
                <span key="t" className="font-medium">{l.title}</span>,
                l.contact_id ? contacts.value?.get(l.contact_id) ?? "Unavailable" : "—",
                l.company_id ? companies.value?.get(l.company_id) ?? "Unavailable" : "—",
                stageName(l.stage_id),
                formatINR(l.value_inr),
                formatDate(l.updated_at),
                <Link key="o" href={crmHref(`/leads/${l.id}`, { workspace: current.workspaceId })} className="font-medium text-brand-700 hover:underline">Open</Link>,
              ])}
            />
          )}
        </div>
      </Panel>
    </>
  );
}
