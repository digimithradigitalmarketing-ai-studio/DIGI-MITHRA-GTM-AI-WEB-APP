import { describe, expect, it } from "vitest";
import { attemptLabel, canRetryRun, nextStatusFor, runStatusBadge, stepCounts, workflowStatusBadge } from "./run-status";

describe("canRetryRun", () => {
  it("allows a retry of a failed run with no retries yet", () => {
    expect(canRetryRun({ status: "failed" }, [])).toBe(true);
  });

  it.each(["failed", "completed", "running", "waiting_approval"])(
    "hides the button on the original once it has a retry that is %s (retry the retry instead)",
    (status) => {
      expect(canRetryRun({ status: "failed" }, [{ status }])).toBe(false);
    },
  );

  it.each(["completed", "running", "skipped", "cancelled", "waiting_approval"])("never retries a %s run", (status) => {
    expect(canRetryRun({ status }, [])).toBe(false);
  });
});

describe("nextStatusFor", () => {
  it("pauses an active workflow", () => {
    expect(nextStatusFor("active")).toEqual({ action: "pause", target: "paused" });
  });

  it("resumes a paused workflow", () => {
    expect(nextStatusFor("paused")).toEqual({ action: "resume", target: "active" });
  });

  it("activates a draft", () => {
    expect(nextStatusFor("draft")).toEqual({ action: "activate", target: "active" });
  });

  it("has no transition for an unknown status", () => {
    expect(nextStatusFor("archived")).toBeNull();
  });
});

describe("badges", () => {
  it("maps run statuses to tones and readable labels", () => {
    expect(runStatusBadge("failed")).toEqual({ tone: "danger", label: expect.any(String) });
    expect(runStatusBadge("completed").tone).toBe("success");
    expect(runStatusBadge("waiting_approval").tone).toBe("warning");
    expect(runStatusBadge("something_new")).toEqual({ tone: "neutral", label: expect.any(String) });
  });

  it("maps workflow statuses", () => {
    expect(workflowStatusBadge("active").tone).toBe("success");
    expect(workflowStatusBadge("paused").tone).toBe("warning");
    expect(workflowStatusBadge("draft").tone).toBe("neutral");
  });
});

describe("attemptLabel", () => {
  it("labels the first attempt and each retry", () => {
    expect(attemptLabel(1)).toBe("First attempt");
    expect(attemptLabel(2)).toBe("Retry 1");
    expect(attemptLabel(3)).toBe("Retry 2");
  });
});

describe("stepCounts", () => {
  it("counts steps by status", () => {
    expect(
      stepCounts([{ status: "completed" }, { status: "completed" }, { status: "skipped" }, { status: "failed" }]),
    ).toEqual({ completed: 2, skipped: 1, failed: 1 });
  });
});
