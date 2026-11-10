// Shared domain types. Phase 2+ will generate database types from Supabase;
// until then these describe the synthetic demo data.

export type ClientType = "Individual" | "Family" | "Corporate";
export type ClientStatus = "active" | "trial" | "paused" | "archived";

export type Client = {
  id: string;
  name: string;
  type: ClientType;
  plan: string;
  status: ClientStatus;
  owner: string;
  since: string; // ISO date YYYY-MM-DD
  monthlyFee: number; // INR
};

export type LeadSource = "Instagram" | "Walk-in" | "Website" | "Referral" | "WhatsApp";
export type LeadStatus = "new" | "contacted" | "qualified" | "lost";
export type LeadInterest =
  | "Strength"
  | "Cardio"
  | "Personal training"
  | "Yoga"
  | "Corporate wellness";

export type Lead = {
  id: string;
  name: string;
  source: LeadSource;
  status: LeadStatus;
  owner: string;
  interest: LeadInterest;
  createdOn: string;
};

export type DealStage = "Enquiry" | "Trial" | "Proposal" | "Won" | "Lost";

export type Deal = {
  id: string;
  title: string;
  leadName: string;
  stage: DealStage;
  amount: number; // INR
  owner: string;
  expectedClose: string;
};

export type Task = {
  id: string;
  title: string;
  owner: string;
  due: string;
  done: boolean;
};

export type CampaignStatus =
  | "draft"
  | "awaiting_approval"
  | "approved"
  | "paused"
  | "completed";
export type CampaignChannel = "WhatsApp" | "Instagram" | "Email";

export type Campaign = {
  id: string;
  name: string;
  channel: CampaignChannel;
  status: CampaignStatus;
  segment: string;
  audience: number;
  approvedBy: string | null;
};

export type AutomationRule = {
  id: string;
  name: string;
  trigger: string;
  action: string;
  enabled: boolean;
};

export type AutomationRunStatus = "success" | "failed" | "skipped";

export type AutomationRun = {
  id: string;
  ruleId: string;
  eventKey: string; // idempotency key
  status: AutomationRunStatus;
  message: string;
  at: string; // ISO date YYYY-MM-DD
};
