import type {
  AutomationRule,
  AutomationRun,
  Campaign,
  Client,
  Deal,
  Lead,
  Task,
} from "@/types";

/**
 * SYNTHETIC DEMO DATA ONLY. No real members, leads or payments.
 *
 * AS_OF is fixed on purpose: Cache Components prerenders these pages, and
 * calls such as new Date() during prerender fail the build. Phase 4 replaces
 * this with a request-time date.
 */
export const AS_OF = "2026-11-09";

export const ORGANIZATION = {
  name: "DigiMithra AI Gym",
  timezone: "Asia/Kolkata",
  currency: "INR",
};

export const clients: Client[] = [
  { id: "cl-001", name: "Arjun Mehta", type: "Individual", plan: "Annual strength", status: "active", owner: "Kavya Rao", since: "2026-03-14", monthlyFee: 2500 },
  { id: "cl-002", name: "Brightline Software", type: "Corporate", plan: "Corporate wellness (24 seats)", status: "active", owner: "Kavya Rao", since: "2026-01-05", monthlyFee: 60000 },
  { id: "cl-003", name: "Priya Nair", type: "Individual", plan: "Personal training (12 sessions)", status: "active", owner: "Dev Kumar", since: "2026-08-21", monthlyFee: 9000 },
  { id: "cl-004", name: "Joshi family", type: "Family", plan: "Family monthly", status: "trial", owner: "Dev Kumar", since: "2026-11-02", monthlyFee: 0 },
  { id: "cl-005", name: "Rohan Iyer", type: "Individual", plan: "Monthly open gym", status: "paused", owner: "Kavya Rao", since: "2025-12-10", monthlyFee: 1800 },
  { id: "cl-006", name: "Northwind Dental", type: "Corporate", plan: "Corporate wellness (10 seats)", status: "active", owner: "Dev Kumar", since: "2026-06-18", monthlyFee: 25000 },
  { id: "cl-007", name: "Anika Shah", type: "Individual", plan: "Yoga and strength", status: "active", owner: "Kavya Rao", since: "2026-09-30", monthlyFee: 3200 },
  { id: "cl-008", name: "Vikram Das", type: "Individual", plan: "Monthly open gym", status: "archived", owner: "Dev Kumar", since: "2024-05-02", monthlyFee: 0 },
];

export const leads: Lead[] = [
  { id: "ld-001", name: "Divya Menon", source: "Instagram", status: "new", owner: "Kavya Rao", interest: "Strength", createdOn: "2026-11-08" },
  { id: "ld-002", name: "Karthik S", source: "Walk-in", status: "contacted", owner: "Dev Kumar", interest: "Personal training", createdOn: "2026-11-06" },
  { id: "ld-003", name: "Ishita Sen", source: "Website", status: "qualified", owner: "Kavya Rao", interest: "Yoga", createdOn: "2026-11-04" },
  { id: "ld-004", name: "Manoj Pillai", source: "Referral", status: "qualified", owner: "Dev Kumar", interest: "Cardio", createdOn: "2026-11-03" },
  { id: "ld-005", name: "Fatima Khan", source: "WhatsApp", status: "new", owner: "Kavya Rao", interest: "Corporate wellness", createdOn: "2026-11-07" },
  { id: "ld-006", name: "Rahul Verma", source: "Instagram", status: "lost", owner: "Dev Kumar", interest: "Strength", createdOn: "2026-10-22" },
  { id: "ld-007", name: "Sneha Pillai", source: "Website", status: "contacted", owner: "Kavya Rao", interest: "Personal training", createdOn: "2026-10-30" },
  { id: "ld-008", name: "Aditya Rao", source: "Walk-in", status: "new", owner: "Dev Kumar", interest: "Cardio", createdOn: "2026-11-09" },
  { id: "ld-009", name: "Nisha George", source: "Referral", status: "contacted", owner: "Kavya Rao", interest: "Yoga", createdOn: "2026-10-28" },
  { id: "ld-010", name: "Harish Bose", source: "WhatsApp", status: "qualified", owner: "Dev Kumar", interest: "Strength", createdOn: "2026-10-19" },
];

export const deals: Deal[] = [
  { id: "dl-001", title: "Annual membership", leadName: "Ishita Sen", stage: "Proposal", amount: 24000, owner: "Kavya Rao", expectedClose: "2026-11-20" },
  { id: "dl-002", title: "Personal training pack", leadName: "Manoj Pillai", stage: "Trial", amount: 9000, owner: "Dev Kumar", expectedClose: "2026-11-15" },
  { id: "dl-003", title: "Corporate wellness (15 seats)", leadName: "Fatima Khan", stage: "Enquiry", amount: 45000, owner: "Kavya Rao", expectedClose: "2026-12-05" },
  { id: "dl-004", title: "Annual strength", leadName: "Harish Bose", stage: "Proposal", amount: 30000, owner: "Dev Kumar", expectedClose: "2026-11-12" },
  { id: "dl-005", title: "Yoga quarterly", leadName: "Nisha George", stage: "Won", amount: 12000, owner: "Kavya Rao", expectedClose: "2026-10-30" },
  { id: "dl-006", title: "Cardio monthly", leadName: "Rahul Verma", stage: "Lost", amount: 3600, owner: "Dev Kumar", expectedClose: "2026-10-22" },
  { id: "dl-007", title: "Personal training pack", leadName: "Sneha Pillai", stage: "Won", amount: 18000, owner: "Kavya Rao", expectedClose: "2026-11-03" },
];

export const tasks: Task[] = [
  { id: "tk-001", title: "Call Divya Menon back", owner: "Kavya Rao", due: "2026-11-09", done: false },
  { id: "tk-002", title: "Send Ishita Sen the membership proposal", owner: "Kavya Rao", due: "2026-11-07", done: false },
  { id: "tk-003", title: "Trial session with Manoj Pillai", owner: "Dev Kumar", due: "2026-11-12", done: false },
  { id: "tk-004", title: "Follow up with Karthik S", owner: "Dev Kumar", due: "2026-11-06", done: false },
  { id: "tk-005", title: "Corporate quote for Fatima Khan", owner: "Kavya Rao", due: "2026-11-14", done: false },
  { id: "tk-006", title: "Renewal check for Brightline Software", owner: "Kavya Rao", due: "2026-11-02", done: true },
];

export const campaigns: Campaign[] = [
  { id: "cp-001", name: "Winter strength kickoff", channel: "WhatsApp", status: "awaiting_approval", segment: "New leads, last 14 days", audience: 42, approvedBy: null },
  { id: "cp-002", name: "Yoga weekend open house", channel: "Instagram", status: "approved", segment: "Leads interested in yoga", audience: 118, approvedBy: "Kavya Rao" },
  { id: "cp-003", name: "Corporate wellness pilot", channel: "Email", status: "draft", segment: "Companies with 20 to 100 staff", audience: 64, approvedBy: null },
  { id: "cp-004", name: "Referral bonus reminder", channel: "WhatsApp", status: "paused", segment: "Active members", audience: 230, approvedBy: "Dev Kumar" },
  { id: "cp-005", name: "Festive re-engagement", channel: "Instagram", status: "completed", segment: "Lapsed members", audience: 75, approvedBy: "Kavya Rao" },
];

export const automationRules: AutomationRule[] = [
  { id: "ar-001", name: "New lead creates follow-up task", trigger: "lead.created", action: "Create follow-up task and activity", enabled: true },
  { id: "ar-002", name: "Deal stage change writes audit activity", trigger: "deal.stage_changed", action: "Write activity record", enabled: true },
  { id: "ar-003", name: "Inactive lead reminder (7 days)", trigger: "lead.inactive_7d", action: "Create reminder task", enabled: false },
];

// Newest first. eventKey is the idempotency key: a repeated event must not
// create a second task, and the skipped run shows that guard working.
export const automationRuns: AutomationRun[] = [
  { id: "run-006", ruleId: "ar-002", eventKey: "deal.stage_changed:dl-005:Won", status: "success", message: "Activity written for Yoga quarterly", at: "2026-10-30" },
  { id: "run-005", ruleId: "ar-001", eventKey: "lead.created:ld-008", status: "success", message: "1 task created", at: "2026-11-09" },
  { id: "run-004", ruleId: "ar-001", eventKey: "lead.created:ld-001", status: "skipped", message: "Duplicate event key. No second task created.", at: "2026-11-08" },
  { id: "run-003", ruleId: "ar-001", eventKey: "lead.created:ld-005", status: "failed", message: "Owner has no active membership, so the task was not created. Assign an owner and retry.", at: "2026-11-07" },
  { id: "run-002", ruleId: "ar-002", eventKey: "deal.stage_changed:dl-001:Proposal", status: "success", message: "Activity written for Annual membership", at: "2026-11-05" },
  { id: "run-001", ruleId: "ar-001", eventKey: "lead.created:ld-002", status: "success", message: "1 task created", at: "2026-11-06" },
];

export const teamRoles = [
  { role: "Platform owner", scope: "Agency-wide configuration and billing, with audited elevated actions" },
  { role: "Organization admin", scope: "Manages members, clients and workflows inside their organization" },
  { role: "Sales operator", scope: "Works on assigned leads, deals and tasks" },
  { role: "Viewer", scope: "Read-only access to permitted organization data" },
  { role: "Client portal user", scope: "Later phase: only records explicitly shared with them" },
];

export const securityChecklist = [
  { item: "Sign-in and protected routes", status: "Phase 2" },
  { item: "Row-level security on every tenant table", status: "Phase 2" },
  { item: "Server-only secrets (no NEXT_PUBLIC service keys)", status: "Phase 2" },
  { item: "Validated server writes with audit records", status: "Phase 3" },
  { item: "AI runs without an API key (mock mode)", status: "Done" },
  { item: "No outbound sending; human approval for campaigns", status: "Done" },
];
