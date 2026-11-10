import type { Metadata } from "next";
import { Suspense } from "react";
import { Brand } from "@/components/brand";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Sign in" };

// Sign-in page. Outside the (app) shell so it has no sidebar. searchParams is
// read inside Suspense because cacheComponents requires request-time data to
// stream rather than block the static shell.
export default function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-canvas px-4 py-10">
      <div className="w-full max-w-sm space-y-6 rounded-xl border border-line bg-panel p-6 shadow-sm">
        <Brand variant="light" />
        <div>
          <h1 className="text-lg font-semibold text-ink">Sign in</h1>
          <p className="mt-1 text-sm text-ink-muted">
            Use the email and password for your DigiMithra workspace.
          </p>
        </div>
        <Suspense fallback={null}>
          <NextField searchParams={searchParams} />
        </Suspense>
      </div>
    </main>
  );
}

async function NextField({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const safe = next && next.startsWith("/") && !next.startsWith("//") ? next : "/dashboard";
  return <LoginForm next={safe} />;
}
