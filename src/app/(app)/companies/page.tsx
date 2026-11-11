import type { Metadata } from "next";
import Link from "next/link";
import { Suspense } from "react";
import { ListControls } from "@/components/crm/list-controls";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { WorkspaceSwitcher } from "@/components/crm/workspace-switcher";
import { Badge, DataTable, EmptyState, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { archivedBadge, lifecycleBadge } from "@/lib/crm/badges";
import { listCompanies } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { pageCount, parseArchived, parsePage, pickOptional, sanitizeSearch } from "@/lib/crm/search";
import { crmHref } from "@/lib/crm/url";
import { COMPANY_LIFECYCLES } from "@/lib/crm/validation";
import { formatDate, titleCase } from "@/lib/format";

export const metadata: Metadata = { title: "Companies" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function CompaniesPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="companies" />}>
      <CompanyList searchParams={searchParams} />
    </Suspense>
  );
}

async function CompanyList({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { workspaces, current } = await loadAutomationContext(sp.workspace);
  const title = "Companies";
  const description = "Prospect and customer organisations. Archive a company to hide it without losing its history.";

  if (!current) {
    return (
      <>
        <PageHeader title={title} description={description} />
        <EmptyState title="No workspace yet" body="Your account is not a member of a workspace. Ask an admin to add you." />
      </>
    );
  }

  const role = effectiveRole(current.tenantRole, current.workspaceRole);
  const canWrite = can(role, "companies.write");
  const params = {
    q: sanitizeSearch(sp.q),
    page: parsePage(sp.page),
    filter: pickOptional(sp.lifecycle, COMPANY_LIFECYCLES),
    archived: parseArchived(sp.archived),
  };
  const result = await settle(() => listCompanies(current.workspaceId, params));

  return (
    <>
      <PageHeader
        title={title}
        description={description}
        actions={
          canWrite ? (
            <Link href={crmHref("/companies/new", { workspace: current.workspaceId })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">
              New company
            </Link>
          ) : null
        }
      />
      <WorkspaceSwitcher basePath="/companies" workspaces={workspaces} currentId={current.workspaceId} />

      <Panel>
        <ListControls
          basePath="/companies"
          workspaceId={current.workspaceId}
          q={params.q}
          searchLabel="Search by name"
          searchPlaceholder="Company name"
          filters={[
            {
              name: "lifecycle",
              label: "Lifecycle",
              value: params.filter,
              options: [{ value: "", label: "All lifecycles" }, ...COMPANY_LIFECYCLES.map((v) => ({ value: v, label: titleCase(v) }))],
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
              caption="Companies"
              headers={["Name", "Domain", "Lifecycle", "Industry", "City", "Updated", ""]}
              emptyMessage={params.q || params.filter ? "No companies match these filters." : "No companies yet."}
              rows={(result.value?.rows ?? []).map((c) => {
                const life = lifecycleBadge(c.lifecycle);
                const archived = archivedBadge(c.archived_at);
                return [
                  <span key="n" className="flex flex-wrap items-center gap-2 font-medium">
                    {c.name}
                    {archived ? <Badge tone={archived.tone}>{archived.label}</Badge> : null}
                  </span>,
                  c.domain ?? "—",
                  <Badge key="l" tone={life.tone}>{life.label}</Badge>,
                  c.industry ?? "—",
                  c.city ?? "—",
                  formatDate(c.updated_at),
                  <Link key="o" href={crmHref(`/companies/${c.id}`, { workspace: current.workspaceId })} className="font-medium text-brand-700 hover:underline">Open</Link>,
                ];
              })}
            />
          )}
        </div>
      </Panel>
    </>
  );
}
