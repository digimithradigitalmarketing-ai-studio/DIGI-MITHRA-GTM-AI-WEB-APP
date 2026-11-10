"use client";

import { useEffect } from "react";
import { Panel } from "@/components/ui";

// Error boundary for module screens. Shows a calm message instead of a stack
// trace. Full error details go to the console only.
export default function AppError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <Panel title="Something went wrong on this screen">
      <p className="text-sm text-ink-muted">
        The rest of the app still works. Try again, or pick another section from the menu.
      </p>
      {error.digest ? (
        <p className="mt-2 font-mono text-xs text-ink-muted">Reference: {error.digest}</p>
      ) : null}
      <button
        type="button"
        onClick={() => reset()}
        className="mt-4 min-h-11 rounded-lg bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700"
      >
        Try again
      </button>
    </Panel>
  );
}
