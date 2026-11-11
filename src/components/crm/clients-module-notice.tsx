import { Notice } from "@/components/ui";
import {
  CLIENTS_NOT_CONFIGURED_BODY,
  CLIENTS_NOT_CONFIGURED_TITLE,
  CLIENTS_UNAVAILABLE_BODY,
} from "@/lib/crm/readiness-state";

// Shown in place of Clients data when the readiness check fails. It carries no flags, table names
// or SQL, only the generic message.
export function ClientsModuleNotice({ state }: { state: "not_configured" | "unavailable" }) {
  if (state === "unavailable") return <Notice tone="warning">{CLIENTS_UNAVAILABLE_BODY}</Notice>;
  return (
    <Notice tone="warning">
      <span className="block font-semibold">{CLIENTS_NOT_CONFIGURED_TITLE}</span>
      <span className="mt-1 block">{CLIENTS_NOT_CONFIGURED_BODY}</span>
    </Notice>
  );
}
