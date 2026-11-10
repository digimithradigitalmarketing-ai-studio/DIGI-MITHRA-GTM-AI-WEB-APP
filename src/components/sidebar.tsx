import { ORGANIZATION } from "@/lib/data";
import { SidebarNav } from "./sidebar-nav";
import { Brand } from "./brand";

/** Desktop sidebar. Hidden below the md breakpoint, where MobileNav takes over. */
export function Sidebar() {
  return (
    <aside className="sticky top-0 hidden h-screen w-64 shrink-0 flex-col bg-ink px-4 py-6 md:flex">
      <div className="px-3 pb-6">
        <Brand />
      </div>
      <SidebarNav />
      <p className="mt-auto px-3 text-xs text-slate-400">
        {ORGANIZATION.name}
        <br />
        Demo data only
      </p>
    </aside>
  );
}
