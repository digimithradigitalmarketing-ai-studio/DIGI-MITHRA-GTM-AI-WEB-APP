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
import { companyOptions, listContacts, namesById } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { pageCount, parsePage, sanitizeSearch } from "@/lib/crm/search";
import { crmHref } from "@/lib/crm/url";
import { formatDate } from "@/lib/format";

export const metadata: Metadata = { title: "Contacts" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function ContactsPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="contacts" />}>
      <ContactList searchParams={searchParams} />
    </Suspense>
  );
}

async function ContactList({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { workspaces, current } = await loadAutomationContext(sp.workspace);
  const description = "People who enquired, joined or buy from you. Each contact can belong to a company.";

  if (!current) {
    return (
      <>
        <PageHeader title="Contacts" description={description} />
        <EmptyState title="No workspace yet" body="Your account is not a member of a workspace. Ask an admin to add you." />
      </>
    );
  }

  const role = effectiveRole(current.tenantRole, current.workspaceRole);
  const canWrite = can(role, "contacts.write");
  const companyFilter = sp.company && isUuid(sp.company) ? sp.company : "";
  const params = { q: sanitizeSearch(sp.q), page: parsePage(sp.page), archived: "active" as const };

  const [result, companies] = await Promise.all([
    settle(() => listContacts(current.workspaceId, { ...params, filter: "", companyId: companyFilter || undefined })),
    settle(() => companyOptions(current.workspaceId)),
  ]);
  const companyNames = result.value
    ? await settle(() => namesById("companies", result.value?.rows.map((r) => r.company_id) ?? []))
    : { value: new Map<string, string>(), error: null };

  return (
    <>
      <PageHeader
        title="Contacts"
        description={description}
        actions={
          canWrite ? (
            <Link href={crmHref("/contacts/new", { workspace: current.workspaceId })} className="inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-medium text-white hover:bg-brand-700">
              New contact
            </Link>
          ) : null
        }
      />
      <WorkspaceSwitcher basePath="/contacts" workspaces={workspaces} currentId={current.workspaceId} />

      <Panel>
        <ListControls
          basePath="/contacts"
          workspaceId={current.workspaceId}
          q={params.q}
          searchLabel="Search by name"
          searchPlaceholder="Contact name"
          filters={[
            {
              name: "company",
              label: "Company",
              value: companyFilter,
              options: [{ value: "", label: "All companies" }, ...(companies.value ?? []).map((c) => ({ value: c.id, label: c.name }))],
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
              caption="Contacts"
              headers={["Name", "Email", "Phone", "Company", "Source", "Added", ""]}
              emptyMessage={params.q || companyFilter ? "No contacts match these filters." : "No contacts yet."}
              rows={(result.value?.rows ?? []).map((c) => [
                <span key="n" className="font-medium">{c.name}</span>,
                c.email ?? "—",
                c.phone ?? "—",
                c.company_id ? companyNames.value?.get(c.company_id) ?? "Unavailable" : "—",
                c.source ?? "—",
                formatDate(c.created_at),
                <Link key="o" href={crmHref(`/contacts/${c.id}`, { workspace: current.workspaceId })} className="font-medium text-brand-700 hover:underline">Open</Link>,
              ])}
            />
          )}
        </div>
      </Panel>
    </>
  );
}
