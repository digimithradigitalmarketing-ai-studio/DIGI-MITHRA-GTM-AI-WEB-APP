import type { Tone } from "@/components/ui";
import { titleCase } from "@/lib/format";

// Badge tones for CRM statuses. These use the database values, not the mock types in lib/status.ts.

export function lifecycleBadge(value: string): { tone: Tone; label: string } {
  const tones: Record<string, Tone> = { prospect: "brand", customer: "success", former: "neutral" };
  return { tone: tones[value] ?? "neutral", label: titleCase(value) };
}

export function clientStatusBadge(value: string): { tone: Tone; label: string } {
  const tones: Record<string, Tone> = { onboarding: "info", active: "success", paused: "warning", churned: "neutral" };
  return { tone: tones[value] ?? "neutral", label: titleCase(value) };
}

export function archivedBadge(archivedAt: string | null): { tone: Tone; label: string } | null {
  return archivedAt ? { tone: "warning", label: "Archived" } : null;
}
