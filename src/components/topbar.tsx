import { Brand } from "./brand";
import { MobileNav } from "./mobile-nav";

/**
 * Top bar. On phones it carries the brand and the menu; on desktop it shows
 * the demo-mode notice. Auth status arrives with Phase 2.
 */
export function Topbar() {
  return (
    <header className="sticky top-0 z-20 border-b border-line bg-panel/95 backdrop-blur">
      <div className="relative flex items-center justify-between gap-3 px-4 py-3 sm:px-6">
        <div className="md:hidden">
          <Brand variant="light" />
        </div>
        <div className="hidden text-sm text-ink-muted md:block">
          Demo workspace. Sign-in arrives in Phase 2.
        </div>
        <div className="flex items-center gap-3">
          <span className="rounded-full bg-brand-100 px-3 py-1 text-xs font-semibold text-brand-900">
            Synthetic data
          </span>
          <MobileNav />
        </div>
      </div>
    </header>
  );
}
