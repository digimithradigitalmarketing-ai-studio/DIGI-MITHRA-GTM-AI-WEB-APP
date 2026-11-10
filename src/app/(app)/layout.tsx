import { Sidebar } from "@/components/sidebar";
import { Topbar } from "@/components/topbar";

// Shell shared by every module screen. Route group (app) keeps URLs clean
// (/dashboard, not /app/dashboard). Phase 2 adds the auth check here.
export default function AppShellLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen w-full">
      <a
        href="#main"
        className="sr-only z-50 rounded-md bg-panel px-4 py-2 text-sm font-medium text-ink focus:not-sr-only focus:absolute focus:left-4 focus:top-4"
      >
        Skip to content
      </a>
      <Sidebar />
      <div className="flex min-w-0 flex-1 flex-col">
        <Topbar />
        <main id="main" className="flex-1 px-4 py-6 sm:px-6 lg:px-8">
          <div className="mx-auto w-full max-w-6xl">{children}</div>
        </main>
      </div>
    </div>
  );
}
