import { Notice } from "@/components/ui";
import { explainCrmError } from "@/lib/crm/errors";

// Shown in place of a list or detail when a read fails. A failed read is never shown as an empty
// list, so a missing column or policy is visible to the user and to the admin.
export function QueryNotice({ error }: { error: unknown }) {
  const message =
    error instanceof Error && "code" in error
      ? explainCrmError(error as Error & { code?: string })
      : "This information could not be loaded. Please refresh the page.";
  return <Notice tone="warning">{message}</Notice>;
}
