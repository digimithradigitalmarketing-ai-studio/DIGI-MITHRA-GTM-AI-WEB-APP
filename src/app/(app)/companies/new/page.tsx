import type { Metadata } from "next";
import { Suspense } from "react";
import { RecordForm } from "@/components/crm/record-form";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadAutomationContext } from "@/lib/automations/context";
import { can, effectiveRole } from "@/lib/crm/roles";
import { companyDefaults, companyFields } from "@/lib/crm/form-fields";
import { crmHref } from "@/lib/crm/url";
import { createCompany } from "../actions";

export const metadata: Metadata = { title: "New company" };

type SearchParams = Promise<Record<string, string | undefined>>;

export default function NewCompanyPage({ searchParams }: { searchParams: SearchParams }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <NewCompanyForm searchParams={searchParams} />
    </Suspense>
  );
}

async function NewCompanyForm({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const { current } = await loadAutomationContext(sp.workspace);
  if (!current) return <Notice tone="warning">Your account is not a member of a workspace.</Notice>;

  if (!can(effectiveRole(current.tenantRole, current.workspaceRole), "companies.write")) {
    return (
      <>
        <PageHeader title="New company" />
        <Notice tone="warning">Your role cannot add companies. Ask a workspace manager or admin.</Notice>
      </>
    );
  }

  return (
    <>
      <PageHeader title="New company" description="Add a prospect or customer organisation to this workspace." />
      <Panel>
        <RecordForm
          action={createCompany.bind(null, current.workspaceId)}
          fields={companyFields()}
          defaults={companyDefaults()}
          submitLabel="Create company"
          pendingLabel="Creating…"
          cancelHref={crmHref("/companies", { workspace: current.workspaceId })}
        />
      </Panel>
    </>
  );
}
