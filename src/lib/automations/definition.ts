// Workflow definitions: the node vocabulary, the follow-up form model, and validation.
// Pure module with no I/O, so it runs in unit tests and in server actions alike.
// The database validator (0007, validate_workflow_definition) enforces the same node list.

export const PRIORITIES = ["low", "normal", "high", "urgent"] as const;
export type Priority = (typeof PRIORITIES)[number];

export const NODE_TYPES = [
  "condition",
  "create_lead",
  "add_tag",
  "set_priority",
  "notify",
  "ai_draft",
  "wait",
  "approval",
  "end",
  "create_task",
] as const;
export type NodeType = (typeof NODE_TYPES)[number];

export const TRIGGER_TYPES = ["lead_created", "message_received", "manual"] as const;
export type TriggerType = (typeof TRIGGER_TYPES)[number];

export type WorkflowNode = { type: NodeType; config?: Record<string, unknown> };
export type WorkflowDefinition = { nodes: WorkflowNode[] };

export const LIMITS = {
  nameMax: 80,
  titleMax: 120,
  descriptionMax: 500,
  dueInHoursMin: 1,
  dueInHoursMax: 720,
} as const;

// The form edits the one shape it can express: a single create_task node followed by end.
export type FollowUpInput = {
  name: string;
  title: string;
  description: string;
  dueInHours: number;
  priority: Priority;
};

export type FieldName = "name" | "title" | "description" | "dueInHours" | "priority";
export type FieldErrors = Partial<Record<FieldName, string>>;

export type ValidationResult =
  | { ok: true; value: FollowUpInput }
  | { ok: false; errors: FieldErrors };

export const TRIGGER_LABELS: Record<TriggerType, string> = {
  lead_created: "When a lead is created",
  message_received: "When a message is received",
  manual: "Manual only",
};

function text(raw: unknown): string {
  return typeof raw === "string" ? raw.trim() : "";
}

// Accepts only whole numbers, so "24h", "1.5" and "" are all rejected.
export function parseDueInHours(raw: unknown): number | null {
  const value = text(raw);
  if (!/^\d+$/.test(value)) return null;
  const hours = Number(value);
  if (hours < LIMITS.dueInHoursMin || hours > LIMITS.dueInHoursMax) return null;
  return hours;
}

export function validateFollowUpInput(raw: Record<string, unknown>): ValidationResult {
  const errors: FieldErrors = {};

  const name = text(raw.name);
  if (!name) errors.name = "Give the automation a name.";
  else if (name.length > LIMITS.nameMax) errors.name = `Keep the name under ${LIMITS.nameMax} characters.`;

  const title = text(raw.title);
  if (!title) errors.title = "Write the task title.";
  else if (title.length > LIMITS.titleMax) errors.title = `Keep the title under ${LIMITS.titleMax} characters.`;

  const description = text(raw.description);
  if (description.length > LIMITS.descriptionMax) {
    errors.description = `Keep the description under ${LIMITS.descriptionMax} characters.`;
  }

  const dueInHours = parseDueInHours(raw.dueInHours);
  if (dueInHours === null) {
    errors.dueInHours = `Enter a whole number of hours from ${LIMITS.dueInHoursMin} to ${LIMITS.dueInHoursMax}.`;
  }

  const priority = text(raw.priority) as Priority;
  if (!(PRIORITIES as readonly string[]).includes(priority)) errors.priority = "Choose a priority.";

  if (Object.keys(errors).length > 0 || dueInHours === null) return { ok: false, errors };
  return { ok: true, value: { name, title, description, dueInHours, priority } };
}

export function buildFollowUpDefinition(input: FollowUpInput): WorkflowDefinition {
  const config: Record<string, unknown> = {
    title: input.title,
    due_in_hours: input.dueInHours,
    priority: input.priority,
  };
  if (input.description) config.description = input.description;
  return {
    nodes: [
      { type: "create_task", config },
      { type: "end" },
    ],
  };
}

// Structural check for definitions read back from the database. Unknown node types are
// reported here too, so the UI can show them instead of crashing.
export function parseDefinition(value: unknown): WorkflowDefinition | null {
  if (!value || typeof value !== "object") return null;
  const nodes = (value as { nodes?: unknown }).nodes;
  if (!Array.isArray(nodes)) return null;
  const parsed: WorkflowNode[] = [];
  for (const node of nodes) {
    if (!node || typeof node !== "object") return null;
    const type = (node as { type?: unknown }).type;
    if (typeof type !== "string") return null;
    const config = (node as { config?: unknown }).config;
    parsed.push({
      type: type as NodeType,
      config: config && typeof config === "object" ? (config as Record<string, unknown>) : undefined,
    });
  }
  return { nodes: parsed };
}

export function isKnownNodeType(type: string): type is NodeType {
  return (NODE_TYPES as readonly string[]).includes(type);
}

// Returns the form values when the definition is exactly the follow-up shape, otherwise null.
// The edit page uses this to decide whether the simple form can edit the workflow safely.
export function followUpInputFromDefinition(definition: WorkflowDefinition): Omit<FollowUpInput, "name"> | null {
  const [first, second, ...rest] = definition.nodes;
  if (!first || first.type !== "create_task" || second?.type !== "end" || rest.length > 0) return null;
  const config = first.config ?? {};
  const title = typeof config.title === "string" ? config.title : "";
  const description = typeof config.description === "string" ? config.description : "";
  const dueInHours = parseDueInHours(String(config.due_in_hours ?? ""));
  const priority = typeof config.priority === "string" ? config.priority : "";
  if (!title || dueInHours === null || !(PRIORITIES as readonly string[]).includes(priority)) return null;
  return { title, description, dueInHours, priority: priority as Priority };
}

export function describeNode(node: WorkflowNode): string {
  if (node.type === "create_task") {
    const title = typeof node.config?.title === "string" ? node.config.title : "untitled";
    return `Create a follow-up task "${title}"`;
  }
  if (node.type === "end") return "End";
  return node.type.replace(/_/g, " ");
}
