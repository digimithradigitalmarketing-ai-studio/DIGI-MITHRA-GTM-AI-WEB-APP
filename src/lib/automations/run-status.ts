import type { Tone } from "@/components/ui";
import { titleCase } from "@/lib/format";

// Maps workflow run and workflow states to a badge tone and a readable label.
// Kept pure so the rules can be unit tested without a database.

export const RUN_STATUSES = [
  "running",
  "completed",
  "skipped",
  "failed",
  "waiting_approval",
  "cancelled",
] as const;
export type RunStatus = (typeof RUN_STATUSES)[number];

export const WORKFLOW_STATUSES = ["draft", "active", "paused"] as const;
export type WorkflowStatus = (typeof WORKFLOW_STATUSES)[number];

const RUN_TONES: Record<string, Tone> = {
  running: "info",
  completed: "success",
  skipped: "neutral",
  failed: "danger",
  waiting_approval: "warning",
  cancelled: "neutral",
};

export function runStatusBadge(status: string): { tone: Tone; label: string } {
  return { tone: RUN_TONES[status] ?? "neutral", label: titleCase(status) };
}

export function workflowStatusBadge(status: string): { tone: Tone; label: string } {
  const tones: Record<string, Tone> = { active: "success", paused: "warning", draft: "neutral" };
  return { tone: tones[status] ?? "neutral", label: titleCase(status) };
}

// A failed run can be retried once. The database refuses a second retry while a retry has
// succeeded or is still in progress, and this mirrors that rule so the UI hides the button.
const BLOCKING_RETRY_STATUSES = new Set(["running", "completed", "waiting_approval"]);

export function canRetryRun(run: { status: string }, retries: { status: string }[]): boolean {
  if (run.status !== "failed") return false;
  return !retries.some((r) => BLOCKING_RETRY_STATUSES.has(r.status));
}

// Pause and resume only apply to live workflows. A draft is activated instead.
export function nextStatusFor(status: string): { action: "pause" | "activate" | "resume"; target: WorkflowStatus } | null {
  if (status === "active") return { action: "pause", target: "paused" };
  if (status === "paused") return { action: "resume", target: "active" };
  if (status === "draft") return { action: "activate", target: "active" };
  return null;
}

export function attemptLabel(attempt: number): string {
  return attempt <= 1 ? "First attempt" : `Retry ${attempt - 1}`;
}

// Counts a run's steps by status for the dashboard and run detail pages.
export function stepCounts(steps: { status: string }[]): { completed: number; skipped: number; failed: number } {
  return {
    completed: steps.filter((s) => s.status === "completed").length,
    skipped: steps.filter((s) => s.status === "skipped").length,
    failed: steps.filter((s) => s.status === "failed").length,
  };
}
