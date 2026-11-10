import type { Campaign, Deal, DealStage, Lead, Task } from "@/types";

/**
 * Pure metric functions. Every number shown in the UI comes from here, so
 * the definitions stay in one place (Phase 8 documents them for reports).
 */

export const OPEN_STAGES: DealStage[] = ["Enquiry", "Trial", "Proposal"];
export const DEAL_STAGES: DealStage[] = ["Enquiry", "Trial", "Proposal", "Won", "Lost"];

export function countBy<T, K extends string>(items: T[], key: (item: T) => K): Record<K, number> {
  const result = {} as Record<K, number>;
  for (const item of items) {
    const k = key(item);
    result[k] = (result[k] ?? 0) + 1;
  }
  return result;
}

export function openPipelineValue(deals: Deal[]): number {
  return deals
    .filter((d) => OPEN_STAGES.includes(d.stage))
    .reduce((sum, d) => sum + d.amount, 0);
}

export function openLeadCount(leads: Lead[]): number {
  return leads.filter((l) => l.status !== "lost").length;
}

/** Won deals divided by closed deals (won + lost). Returns null when nothing has closed. */
export function conversionRate(deals: Deal[]): number | null {
  const won = deals.filter((d) => d.stage === "Won").length;
  const lost = deals.filter((d) => d.stage === "Lost").length;
  const closed = won + lost;
  return closed === 0 ? null : won / closed;
}

/** A task is overdue when it is open and its due date is before the as-of date. */
export function overdueTasks(tasks: Task[], asOf: string): Task[] {
  return tasks.filter((t) => !t.done && t.due < asOf);
}

export function dueTodayOrLater(tasks: Task[], asOf: string): Task[] {
  return tasks
    .filter((t) => !t.done && t.due >= asOf)
    .sort((a, b) => a.due.localeCompare(b.due));
}

export function campaignsAwaitingApproval(campaigns: Campaign[]): number {
  return campaigns.filter((c) => c.status === "awaiting_approval").length;
}
