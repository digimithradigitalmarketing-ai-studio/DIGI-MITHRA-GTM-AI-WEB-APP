import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ClientsModuleNotice } from "@/components/crm/clients-module-notice";
import { ListControls } from "@/components/crm/list-controls";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { WorkspaceSwitcher } from "@/components/crm/workspace-switcher";
import { Badge, DataTable, EmptyState, Notice, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { clientStatusBadge } from "@/lib/crm/badges";
import { listClients, namesById } from "@/lib/crm/queries";
import { loadClientsReadiness } from "@/lib/crm/readiness";
import { classifyClientList } from "@/lib/crm/readiness-state";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { CLIENT_STATUSES } from "@/lib/crm/validation";
import { pageCount, parseArchived, parsePage, pickOptional, sanitizeSearch } from "@/lib/crm/search";
import { crmHref } from "@/lib/crm/url";
import { formatDate, formatINR, titleCase } from "@/lib/format";

export const metadata: Metadata = { title: "Clients" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function ClientsPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="clients" />}>
      <ClientList searchParams={searchParams} />
    </Suspense>
  );
}

async function ClientList({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { workspaces, current } = await loadAutomationContext(sp.workspace);
  const description = "Customers you run programmes or campaigns for. A client is one company record with its status and retainer.";

  if (!current) {
    return (
      <>
        <PageHeader title="Clients" description={description} />
        <EmptyState title="No workspace yet" body="Your account is not a member of a workspace. Ask an admin to add you." />
      </>
    );
  }

  const role = effectiveRole(current.tenantRole, current.workspaceRole);
  const hasAccess = role !== null;
  const readiness = await loadClientsReadiness();
  // Writes need a ready module and the clients.write capability. Reads run only when the module is ready,
  // so a missing policy never shows as an empty list.
  const canWrite = readiness.state === "ready" && can(role, "clients.write");
  const params = {
    q: sanitizeSearch(sp.q),
    page: parsePage(sp.page),
    filter: pickOptional(sp.status, CLIENT_STATUSES),
    archived: parseArchived(sp.archived),
  };
  const result = readiness.state === "ready" && hasAccess
    ? await settle(() => listClients(current.workspaceId, params))
    : { value: null, error: null };
  const rows = result.value?.rows ?? [];
  const companies = await settle(() => namesById("companies", rows.map((r) => r.company_id)));
  const contacts = await settle(() => namesById("contacts", rows.map((r) => r.primary_contact_id)));
  const state = classifyClientList({
    readiness,
    hasAccess,
    listError: result.error ? (result.error as { code?: string }) : null,
    rowCount: result.value?.total ?? 0,
  });

  return (
    <>
      <PageHeader
        title="Clients"
        description={description}
        actions={
          canWrite ? (
            <Link href={crmHref("/clients/new", { workspace: current.workspaceId })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">
              New client
            </Link>
          ) : null
        }
      />
      <WorkspaceSwitcher basePath="/clients" workspaces={workspaces} currentId={current.workspaceId} />

      {state === "not_configured" || state === "unavailable" ? (
        <ClientsModuleNotice state={state} />
      ) : state === "permission_denied" ? (
        <Notice tone="info">You do not have access to the clients in this workspace. Ask an admin for a role that includes clients.</Notice>
      ) : (
        <>
          {!canWrite ? (
            <div className="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900">
              You can view clients here. Only workspace admins can add or change them.
            </div>
          ) : null}

          <Panel>
            <ListControls
              basePath="/clients"
              workspaceId={current.workspaceId}
              q={params.q}
              searchLabel="Search by company name"
              searchPlaceholder="Company name"
              filters={[
                {
                  name: "status",
                  label: "Status",
                  value: params.filter,
                  options: [{ value: "", label: "All statuses" }, ...CLIENT_STATUSES.map((v) => ({ value: v, label: titleCase(v) }))],
                },
              ]}
              archived={params.archived}
              page={params.page}
              pageCount={pageCount(result.value?.total ?? 0)}
              total={result.value?.total ?? 0}
            />

            <div className="mt-5">
              {result.error ? (
                <QueryNotice error={result.error} />
              ) : (
                <DataTable
                  caption="Client accounts"
                  headers={["Company", "Status", "Primary contact", "Services", "Retainer", "Started", ""]}
                  emptyMessage={params.q || params.filter ? "No clients match these filters." : "No clients yet. Clients appear here once a company is set up as one."}
                  rightAlignColumns={[4]}
                  rows={rows.map((c) => {
                    const badge = clientStatusBadge(c.status);
                    return [
                      <span key="c" className="flex flex-wrap items-center gap-2 font-medium">
                        {companies.value?.get(c.company_id) ?? "Unavailable"}
                        {c.archived_at ? <Badge tone="warning">Archived</Badge> : null}
                      </span>,
                      <Badge key="s" tone={badge.tone}>{badge.label}</Badge>,
                      c.primary_contact_id ? contacts.value?.get(c.primary_contact_id) ?? "Unavailable" : "—",
                      c.services ?? "—",
                      c.retainer_inr ? formatINR(c.retainer_inr) : "Not set",
                      c.started_on ? formatDate(c.started_on) : "—",
                      <Link key="o" href={crmHref(`/clients/${c.id}`, { workspace: current.workspaceId })} className="font-medium text-brand-700 hover:underline">Open</Link>,
                    ];
                  })}
                />
              )}
            </div>
          </Panel>
        </>
      )}
    </>
  );
}
