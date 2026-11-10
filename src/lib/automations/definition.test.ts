import { describe, expect, it } from "vitest";
import {
  buildFollowUpDefinition,
  followUpInputFromDefinition,
  isKnownNodeType,
  parseDefinition,
  parseDueInHours,
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
