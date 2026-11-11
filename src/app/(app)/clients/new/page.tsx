import type { Metadata } from "next";
import { Suspense } from "react";
import { ClientsModuleNotice } from "@/components/crm/clients-module-notice";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { RecordForm } from "@/components/crm/record-form";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { clientDefaults, clientFields } from "@/lib/crm/form-fields";
import { companyOptions, contactOptions } from "@/lib/crm/queries";
import { loadClientsReadiness } from "@/lib/crm/readiness";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { createClientRecord } from "../actions";

export const metadata: Metadata = { title: "New client" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function NewClientPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <NewClientForm searchParams={searchParams} />
    </Suspense>
  );
}

async function NewClientForm({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const readiness = await loadClientsReadiness();
  if (readiness.state !== "ready") {
    return (
      <>
        <PageHeader title="New client" />
        <ClientsModuleNotice state={readiness.state} />
      </>
    );
  }
  const { current } = await loadAutomationContext(sp.workspace);
  if (!current) return <Notice tone="warning">Your account is not a member of a workspace.</Notice>;

  if (!can(effectiveRole(current.tenantRole, current.workspaceRole), "clients.write")) {
    return (
      <>
        <PageHeader title="New client" />
        <Notice tone="warning">Only workspace admins can add clients.</Notice>
      </>
    );
  }

  const [companies, contacts] = await Promise.all([
    settle(() => companyOptions(current.workspaceId, { excludeWithClient: true })),
    settle(() => contactOptions(current.workspaceId)),
  ]);
  const failed = companies.error ?? contacts.error;
  if (failed) return <QueryNotice error={failed} />;

  const companyId = sp.company && isUuid(sp.company) ? sp.company : undefined;

  return (
    <>
      <PageHeader title="New client" description="Turn a company into a client. Each company can have one client record." />
      {(companies.value ?? []).length === 0 ? (
        <Notice tone="info">Every company in this workspace already has a client record, or there are no companies yet. Add a company first.</Notice>
      ) : null}
      <Panel>
        <RecordForm
          action={createClientRecord.bind(null, current.workspaceId)}
          fields={clientFields({ companies: companies.value ?? [], contacts: contacts.value ?? [] })}
          defaults={clientDefaults(null, companyId)}
          submitLabel="Create client"
          pendingLabel="Creating…"
          cancelHref={crmHref("/clients", { workspace: current.workspaceId })}
        />
      </Panel>
    </>
  );
}
