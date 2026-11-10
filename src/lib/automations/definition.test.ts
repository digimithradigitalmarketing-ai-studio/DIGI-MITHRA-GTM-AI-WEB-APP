import { describe, expect, it } from "vitest";
import {
  buildFollowUpDefinition,
  followUpInputFromDefinition,
  isKnownNodeType,
  parseDefinition,
  parseDueInHours,
  validateDefinition,
  validateFollowUpInput,
} from "./definition";

const valid = {
  name: "New lead follow-up",
  title: "Follow up with {{name}}",
  description: "Call within the hour",
  dueInHours: "24",
  priority: "high",
};

describe("validateFollowUpInput", () => {
  it("accepts a complete form and returns typed values", () => {
    const result = validateFollowUpInput(valid);
    expect(result).toEqual({
      ok: true,
      value: {
        name: "New lead follow-up",
        title: "Follow up with {{name}}",
        description: "Call within the hour",
        dueInHours: 24,
        priority: "high",
      },
    });
  });

  it("trims whitespace and allows an empty description", () => {
    const result = validateFollowUpInput({ ...valid, name: "  Lead  ", description: "   " });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.name).toBe("Lead");
      expect(result.value.description).toBe("");
    }
  });

  it("reports every missing field at once", () => {
    const result = validateFollowUpInput({ name: "", title: "", dueInHours: "", priority: "" });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(Object.keys(result.errors).sort()).toEqual(["dueInHours", "name", "priority", "title"]);
    }
  });

  it("rejects an unknown priority", () => {
    const result = validateFollowUpInput({ ...valid, priority: "critical" });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.errors.priority).toBeDefined();
  });

  it("rejects over-long text", () => {
    const result = validateFollowUpInput({ ...valid, name: "x".repeat(81), title: "y".repeat(121) });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.name).toBeDefined();
      expect(result.errors.title).toBeDefined();
    }
  });

  it("ignores non-string input rather than coercing it", () => {
    const result = validateFollowUpInput({ ...valid, name: 42, priority: ["high"] });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.errors.name).toBeDefined();
      expect(result.errors.priority).toBeDefined();
    }
  });
});

describe("parseDueInHours", () => {
  it.each([
    ["1", 1],
    ["24", 24],
    ["720", 720],
  ])("accepts %s", (raw, expected) => {
    expect(parseDueInHours(raw)).toBe(expected);
  });

  it.each(["0", "721", "1.5", "24h", "-3", "", "abc"])("rejects %j", (raw) => {
    expect(parseDueInHours(raw)).toBeNull();
  });
});

describe("buildFollowUpDefinition", () => {
  it("builds one create_task node followed by end", () => {
    const definition = buildFollowUpDefinition({
      name: "x",
      title: "Call {{name}}",
      description: "",
      dueInHours: 4,
      priority: "urgent",
    });
    expect(definition).toEqual({
      nodes: [
        { type: "create_task", config: { title: "Call {{name}}", due_in_hours: 4, priority: "urgent" } },
        { type: "end" },
      ],
    });
  });

  it("includes notes only when they are present", () => {
    const definition = buildFollowUpDefinition({
      name: "x",
      title: "Call",
      description: "Within the hour",
      dueInHours: 1,
      priority: "normal",
    });
    expect(definition.nodes[0].config).toMatchObject({ description: "Within the hour" });
  });

  it("round-trips through followUpInputFromDefinition", () => {
    const definition = buildFollowUpDefinition({
      name: "x",
      title: "Call {{name}}",
      description: "Notes",
      dueInHours: 48,
      priority: "low",
    });
    expect(followUpInputFromDefinition(definition)).toEqual({
      title: "Call {{name}}",
      description: "Notes",
      dueInHours: 48,
      priority: "low",
    });
  });
});

describe("followUpInputFromDefinition", () => {
  it("returns null for definitions with extra or missing steps", () => {
    expect(followUpInputFromDefinition({ nodes: [{ type: "end" }] })).toBeNull();
    expect(
      followUpInputFromDefinition({
        nodes: [
          { type: "create_task", config: { title: "a", due_in_hours: 1, priority: "normal" } },
          { type: "notify" },
          { type: "end" },
        ],
      }),
    ).toBeNull();
  });

  it("returns null when the stored config is invalid", () => {
    expect(
      followUpInputFromDefinition({
        nodes: [
          { type: "create_task", config: { title: "a", due_in_hours: "soon", priority: "normal" } },
          { type: "end" },
        ],
      }),
    ).toBeNull();
  });
});

describe("parseDefinition", () => {
  it("accepts a well-formed definition", () => {
    expect(parseDefinition({ nodes: [{ type: "end" }] })).toEqual({ nodes: [{ type: "end", config: undefined }] });
  });

  it("keeps unknown node types so the UI can show them", () => {
    const parsed = parseDefinition({ nodes: [{ type: "send_email" }] });
    expect(parsed?.nodes[0].type).toBe("send_email");
    expect(isKnownNodeType("send_email")).toBe(false);
  });

  it.each([null, "text", {}, { nodes: "x" }, { nodes: [null] }, { nodes: [{ config: {} }] }])(
    "rejects malformed input %j",
    (value) => {
      expect(parseDefinition(value)).toBeNull();
    },
  );

  it("recognises the ten engine node types", () => {
    for (const type of [
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
    ]) {
      expect(isKnownNodeType(type)).toBe(true);
    }
  });
});

describe("validateDefinition (mirrors the database check)", () => {
  const node = (type: string, config?: unknown) => ({ type, ...(config === undefined ? {} : { config }) });
  const defn = (...nodes: unknown[]) => ({ nodes });

  it("accepts a valid follow-up definition and a boundary-valued one", () => {
    expect(validateDefinition(defn(node("create_task", { title: "Call", due_in_hours: 720, priority: "urgent" }), node("end"))).ok).toBe(true);
    expect(validateDefinition(defn(node("add_tag", { tag: "vip" }), node("end"))).ok).toBe(true);
  });

  it("accepts a node with no config, since config is optional", () => {
    expect(validateDefinition(defn(node("end"), node("create_task")))).toMatchObject({ ok: true });
  });

  it("refuses a definition without a nodes array", () => {
    expect(validateDefinition({})).toMatchObject({ ok: false });
    expect(validateDefinition(null)).toMatchObject({ ok: false });
    expect(validateDefinition([])).toMatchObject({ ok: false });
  });

  it("refuses an unknown node type and names the node", () => {
    const result = validateDefinition(defn(node("send_email")));
    expect(result).toEqual({ ok: false, error: "unknown workflow node type: send_email (node 1)" });
  });

  it("refuses a node that is not an object", () => {
    expect(validateDefinition(defn("end"))).toEqual({ ok: false, error: "node 1 must be an object" });
  });

  it("refuses a config that is not an object", () => {
    expect(validateDefinition(defn(node("create_task", "24h")))).toEqual({
      ok: false,
      error: "node 1 (create_task): config must be an object",
    });
  });

  it("refuses a text due_in_hours, a fraction, zero and anything above 720", () => {
    for (const due of ["soon", "24", 0, 721, 1.5]) {
      expect(validateDefinition(defn(node("create_task", { due_in_hours: due })))).toMatchObject({ ok: false });
    }
  });

  it("refuses an add_tag node without a tag, including a blank one", () => {
    expect(validateDefinition(defn(node("add_tag", {})))).toEqual({
      ok: false,
      error: "node 1 (add_tag): config.tag is required",
    });
    expect(validateDefinition(defn(node("add_tag", { tag: "   " })))).toEqual({
      ok: false,
      error: "node 1 (add_tag): config.tag cannot be empty",
    });
  });

  it("refuses an unknown priority and an unknown condition operator", () => {
    expect(validateDefinition(defn(node("set_priority", { priority: "critical" })))).toMatchObject({ ok: false });
    expect(validateDefinition(defn(node("condition", { operator: "starts_with", value: "x" })))).toMatchObject({ ok: false });
  });

  it("refuses text longer than its limit, counting characters", () => {
    expect(validateDefinition(defn(node("create_task", { description: "x".repeat(501) })))).toMatchObject({ ok: false });
    expect(validateDefinition(defn(node("create_task", { description: "x".repeat(500) })))).toMatchObject({ ok: true });
    expect(validateDefinition(defn(node("create_task", { description: "é".repeat(500) })))).toMatchObject({ ok: true });
  });

  it("refuses more than 25 nodes", () => {
    const many = Array.from({ length: 26 }, () => node("wait"));
    expect(validateDefinition(defn(...many))).toEqual({ ok: false, error: "a workflow can have at most 25 nodes" });
  });

  it("names the node position when a later node is the bad one", () => {
    const result = validateDefinition(defn(node("create_task", { due_in_hours: 24 }), node("wait", { minutes: -5 })));
    expect(result).toEqual({
      ok: false,
      error: "node 2 (wait): config.minutes must be a whole number from 0 to 43200",
    });
  });
});
