import type {
  AutomationRunStatus,
  CampaignStatus,
  ClientStatus,
  DealStage,
  LeadStatus,
} from "@/types";
import type { Tone } from "@/components/ui";
import { titleCase } from "./format";

// Maps domain statuses to a badge tone and a readable label, in one place.

export function clientStatusBadge(status: ClientStatus): { tone: Tone; label: string } {
  const tones: Record<ClientStatus, Tone> = {
    active: "success",
    trial: "info",
    paused: "warning",
    archived: "neutral",
  };
  return { tone: tones[status], label: titleCase(status) };
}

export function leadStatusBadge(status: LeadStatus): { tone: Tone; label: string } {
  const tones: Record<LeadStatus, Tone> = {
    new: "brand",
    contacted: "info",
    qualified: "success",
    lost: "neutral",
  };
  return { tone: tones[status], label: titleCase(status) };
}

export function dealStageBadge(stage: DealStage): { tone: Tone; label: string } {
  const tones: Record<DealStage, Tone> = {
    Enquiry: "neutral",
    Trial: "info",
    Proposal: "brand",
    Won: "success",
    Lost: "danger",
  };
  return { tone: tones[stage], label: stage };
}

export function campaignStatusBadge(status: CampaignStatus): { tone: Tone; label: string } {
  const tones: Record<CampaignStatus, Tone> = {
    draft: "neutral",
    awaiting_approval: "warning",
    approved: "success",
    paused: "danger",
    completed: "info",
  };
  const labels: Record<CampaignStatus, string> = {
    draft: "Draft",
    awaiting_approval: "Awaiting approval",
    approved: "Approved",
    paused: "Paused",
    completed: "Completed",
  };
  return { tone: tones[status], label: labels[status] };
}

export function automationRunBadge(status: AutomationRunStatus): { tone: Tone; label: string } {
  const tones: Record<AutomationRunStatus, Tone> = {
    success: "success",
    failed: "danger",
    skipped: "neutral",
  };
  return { tone: tones[status], label: titleCase(status) };
}
