import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { ListSkeleton } from "@/components/crm/list-skeleton";
import { QueryNotice } from "@/components/crm/query-notice";
import { RecordForm } from "@/components/crm/record-form";
import { Notice, PageHeader, Panel } from "@/components/ui";
import { loadWorkspaceAccess } from "@/lib/automations/context";
import { isUuid } from "@/lib/automations/ids";
import { contactDefaults, contactFields } from "@/lib/crm/form-fields";
import { companyOptions, getContact } from "@/lib/crm/queries";
import { can, effectiveRole } from "@/lib/crm/roles";
import { settle } from "@/lib/crm/settle";
import { crmHref } from "@/lib/crm/url";
import { updateContact } from "../../actions";

export const metadata: Metadata = { title: "Edit contact" };

type Params = Promise<{ id: string }>;

export default function EditContactPage({ params }: { params: Params }) {
  return (
    <Suspense fallback={<ListSkeleton label="form" />}>
      <EditContactForm params={params} />
    </Suspense>
  );
}

async function EditContactForm({ params }: { params: Params }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const contact = await settle(() => getContact(id));
  if (contact.error) return <QueryNotice error={contact.error} />;
  if (!contact.value) notFound();
  const access = await loadWorkspaceAccess(contact.value.workspace_id);
  if (!access) notFound();

  const detailHref = crmHref(`/contacts/${id}`, { workspace: contact.value.workspace_id });
  if (!can(effectiveRole(access.tenantRole, access.workspaceRole), "contacts.write")) {
    return (
      <>
        <PageHeader title="Edit contact" description={contact.value.name} />
        <Notice tone="warning">Your role can view this contact but cannot change it.</Notice>
      </>
    );
  }

  const companies = await settle(() => companyOptions(contact.value!.workspace_id, { keepId: contact.value!.company_id }));
  if (companies.error) return <QueryNotice error={companies.error} />;

  return (
    <>
      <PageHeader title="Edit contact" description={contact.value.name} />
      <Panel>
        <RecordForm
          action={updateContact.bind(null, id)}
          fields={contactFields(companies.value ?? [])}
          defaults={contactDefaults(contact.value)}
          submitLabel="Save changes"
          pendingLabel="Saving…"
          cancelHref={detailHref}
        />
      </Panel>
    </>
  );
}
