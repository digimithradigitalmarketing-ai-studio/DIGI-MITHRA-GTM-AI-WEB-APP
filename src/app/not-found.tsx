import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-canvas px-6 text-center">
      <p className="text-sm font-semibold uppercase tracking-wide text-brand-600">Error 404</p>
      <h1 className="mt-2 text-3xl font-semibold tracking-tight text-ink">Page not found</h1>
      <p className="mt-2 max-w-md text-sm text-ink-muted">
        This page does not exist in the DigiMithra AI Gym demo.
      </p>
      <Link
        href="/dashboard"
        className="mt-6 inline-flex min-h-11 items-center rounded-lg bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700"
      >
        Back to dashboard
      </Link>
    </div>
  );
}
