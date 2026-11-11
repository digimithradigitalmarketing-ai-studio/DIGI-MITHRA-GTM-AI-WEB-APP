import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { RecordForm } from "@/components/crm/record-form";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { can, effectiveRole } from "@/lib/crm/roles";
import { companyDefaults, companyFields } from "@/lib/crm/form-fields";
import { getCompany } from "@/lib/crm/queries";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { updateCompany } from "../../actions";

export const metadata: Metadata = { title: "Edit company" };

type Params = Promise<{ id: string }>;

export default function EditCompanyPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <EditCompanyForm params={params} />
    </Suspense>
  );
}

async function EditCompanyForm({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const { value: company, error } = await settle(() => getCompany(id));
  if (error) return <QueryNotice error={error} />;
  if (!company) notFound();
  const access = await loadWorkspaceAccess(company.workspace_id);
  if (!access) notFound();

  const detailHref = crmHref(`/companies/${id}`, { workspace: company.workspace_id });
  if (!can(effectiveRole(access.tenantRole, access.workspaceRole), "companies.write")) {
    return (
      <>
        <PageHeader title="Edit company" description={company.name} />
        <Notice tone="warning">Your role can view this company but cannot change it.</Notice>
      </>
    );
  }

  return (
    <>
      <PageHeader title="Edit company" description={company.name} />
      <Panel>
        <RecordForm
          action={updateCompany.bind(null, id)}
          fields={companyFields()}
          defaults={companyDefaults(company)}
          submitLabel="Save changes"
          pendingLabel="Saving…"
          cancelHref={detailHref}
        />
      </Panel>
    </>
  );
}
