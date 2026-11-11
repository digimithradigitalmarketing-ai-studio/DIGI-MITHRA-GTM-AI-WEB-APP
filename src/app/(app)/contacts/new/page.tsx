import type { Metadata } from "next";
import { Suspense } from "react";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { RecordForm } from "@/components/crm/record-form";
import { QueryNotice } from "@/components/crm/query-notice";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { contactDefaults, contactFields } from "@/lib/crm/form-fields";
import { companyOptions } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { createContact } from "../actions";

export const metadata: Metadata = { title: "New contact" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function NewContactPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <NewContactForm searchParams={searchParams} />
    </Suspense>
  );
}

async function NewContactForm({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { current } = await loadAutomationContext(sp.workspace);
  if (!current) return <Notice tone="warning">Your account is not a member of a workspace.</Notice>;

  if (!can(effectiveRole(current.tenantRole, current.workspaceRole), "contacts.write")) {
    return (
      <>
        <PageHeader title="New contact" />
        <Notice tone="warning">Your role cannot add contacts. Ask a workspace member with editor access or above.</Notice>
      </>
    );
  }

  const companies = await settle(() => companyOptions(current.workspaceId));
  if (companies.error) return <QueryNotice error={companies.error} />;
  const prefill = sp.company && isUuid(sp.company) ? sp.company : undefined;

  return (
    <>
      <PageHeader title="New contact" description="Add a person. Link them to a company when you know it." />
      <Panel>
        <RecordForm
          action={createContact.bind(null, current.workspaceId)}
          fields={contactFields(companies.value ?? [])}
          defaults={contactDefaults(null, prefill)}
          submitLabel="Create contact"
          pendingLabel="Creating…"
          cancelHref={crmHref("/contacts", { workspace: current.workspaceId })}
        />
      </Panel>
    </>
  );
}
