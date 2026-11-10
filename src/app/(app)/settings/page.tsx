import type { Metadata } from "next";
import { SettingsForm } from "@/components/settings-form";
import { DataTable, PageHeader, Panel } from "@/components/ui";
import { ORGANIZATION, securityChecklist, teamRoles } from "@/lib/data";

export const metadata: Metadata = { title: "Settings" };

export default function SettingsPage() {
  return (
    <>
      <PageHeader
        title="Settings"
        description="Organization details, roles and the security checklist for this build."
      />

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel title="Organization details" description="Used in campaign drafts and reports">
          <SettingsForm
            initial={{
              name: ORGANIZATION.name,
              timezone: ORGANIZATION.timezone,
              currency: ORGANIZATION.currency,
            }}
          />
        </Panel>

        <Panel title="Roles" description="Who can do what once sign-in is live">
          <DataTable
            caption="Roles and scope"
            headers={["Role", "Scope"]}
            rows={teamRoles.map((r) => [<span key="r" className="font-medium">{r.role}</span>, r.scope])}
          />
        </Panel>
      </div>

      <div className="mt-6">
        <Panel title="Security checklist" description="What is done now and what each later phase adds">
          <DataTable
            caption="Security checklist status"
            headers={["Control", "Status"]}
            rows={securityChecklist.map((c) => [c.item, c.status])}
          />
        </Panel>
      </div>
    </>
  );
}
