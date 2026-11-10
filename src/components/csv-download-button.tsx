"use client";

import { useState } from "react";

/** Builds a CSV in the browser from rows that were already authorized and shown on the page. */
export function CsvDownloadButton({
  filename,
  rows,
  label = "Download CSV",
}: {
  filename: string;
  rows: string[][];
  label?: string;
}) {
  const [status, setStatus] = useState<"idle" | "done" | "failed">("idle");

  function download() {
    try {
      const csv = rows
        .map((row) =>
          row
            .map((cell) => {
              const safe = /^[=+\-@]/.test(cell) ? `'${cell}` : cell; // blunt formula-injection guard
              return `"${safe.replace(/"/g, '""')}"`;
            })
            .join(","),
        )
        .join("\r\n");

      const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
      setStatus("done");
    } catch {
      setStatus("failed");
    }
  }

  return (
    <div className="flex flex-wrap items-center gap-3">
      <button
        type="button"
        onClick={download}
        className="min-h-11 rounded-lg bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700"
      >
        {label}
      </button>
      <p role="status" aria-live="polite" className="text-sm text-ink-muted">
        {status === "done" ? "Download started." : status === "failed" ? "The download could not be created." : ""}
      </p>
    </div>
  );
}
