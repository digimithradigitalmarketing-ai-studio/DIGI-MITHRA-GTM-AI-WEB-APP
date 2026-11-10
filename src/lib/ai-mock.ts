import type { Deal, Lead, LeadStatus } from "@/types";
import { formatDate, formatINR } from "./format";

/**
 * Mock AI. Deterministic templates, no network call and no API key.
 * Phase 6 replaces this with a server-side provider behind the same shape:
 * a summary plus a draft that a human must approve before anything is sent.
 */

export type MockOutput = {
  summary: string;
  draft: string;
  nextStep: string;
};

const NEXT_STEP: Record<LeadStatus, string> = {
  new: "Contact within 24 hours and offer a free intro session.",
  contacted: "Send a short membership overview and ask about preferred trial times.",
  qualified: "Move to a proposal with a clear price and start date.",
  lost: "Archive the lead, or re-engage in a future campaign with consent.",
};

export function buildMockOutput(lead: Lead, deal: Deal | undefined, gymName: string): MockOutput {
  const firstName = lead.name.split(" ")[0];
  const dealLine = deal
    ? `An open deal ("${deal.title}") is worth ${formatINR(deal.amount)} in the ${deal.stage} stage.`
    : "No deal has been opened for this lead yet.";

  const summary = [
    `${lead.name} enquired through ${lead.source} on ${formatDate(lead.createdOn)} and is currently ${lead.status}.`,
    `Interest: ${lead.interest}. Owner: ${lead.owner}.`,
    dealLine,
  ].join(" ");

  const draft = [
    `Hi ${firstName},`,
    "",
    `Thanks for your interest in ${lead.interest.toLowerCase()} at ${gymName}. We would love to show you around.`,
    "Would you like a free intro session this week? Reply with a day and time that suits you and our team will confirm.",
    "",
    `Reply STOP to opt out of messages. ${gymName} team`,
  ].join("\n");

  return { summary, draft, nextStep: NEXT_STEP[lead.status] };
}
