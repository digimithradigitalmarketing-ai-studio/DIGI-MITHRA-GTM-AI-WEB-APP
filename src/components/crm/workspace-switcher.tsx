import Link from "next/link";
import { crmHref } from "@/lib/crm/url";

// Lists the workspaces the caller belongs to. Only renders when there is more than one, and the
// links keep the current module path, so switching does not leave the screen.
export function WorkspaceSwitcher({
  basePath,
  workspaces,
  currentId,
}: {
  basePath: string;
  workspaces: { workspaceId: string; workspaceName: string }[];
  currentId: string;
}) {
  if (workspaces.length < 2) return null;
  return (
    <nav aria-label="Workspaces" className="mb-6 flex flex-wrap gap-2 text-sm">
      {workspaces.map((w) => (
        <Link
          key={w.workspaceId}
          href={crmHref(basePath, { workspace: w.workspaceId })}
          aria-current={w.workspaceId === currentId ? "page" : undefined}
          className={`rounded-full px-3 py-1 ${w.workspaceId === currentId ? "bg-brand-100 text-brand-900" : "bg-slate-100 text-ink-muted hover:text-ink"}`}
        >
          {w.workspaceName}
        </Link>
      ))}
    </nav>
  );
}
