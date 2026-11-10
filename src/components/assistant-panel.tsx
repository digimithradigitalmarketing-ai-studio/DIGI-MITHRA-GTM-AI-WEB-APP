"use client";

import { useId, useMemo, useState } from "react";
import type { Deal, Lead } from "@/types";
import { buildMockOutput } from "@/lib/ai-mock";
import { Badge, Notice, Panel } from "./ui";

/**
 * Lead summary and draft message. Mock mode only: nothing is sent, and the
 * draft is editable text that a person copies after reviewing it.
 */
export function AssistantPanel({
  leads,
  deals,
  gymName,
}: {
  leads: Lead[];
  deals: Deal[];
  gymName: string;
}) {
  const [leadId, setLeadId] = useState(leads[0]?.id ?? "");
  const [generated, setGenerated] = useState<{ leadId: string } | null>(null);
  const [draft, setDraft] = useState("");
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle");
  const selectId = useId();

  const lead = leads.find((l) => l.id === leadId);
  const deal = lead ? deals.find((d) => d.leadName === lead.name) : undefined;

  const output = useMemo(() => {
    if (!lead || !generated || generated.leadId !== lead.id) return null;
    return buildMockOutput(lead, deal, gymName);
  }, [lead, deal, generated, gymName]);

  function generate() {
    if (!lead) return;
    const next = buildMockOutput(lead, deal, gymName);
    setDraft(next.draft);
    setGenerated({ leadId: lead.id });
    setCopyState("idle");
  }

  async function copyDraft() {
    try {
      await navigator.clipboard.writeText(draft);
      setCopyState("copied");
    } catch {
      setCopyState("failed");
    }
  }

  if (leads.length === 0) {
    return (
      <Panel title="Generate a summary">
        <p className="text-sm text-ink-muted">Add a lead first. The assistant needs a lead to summarize.</p>
      </Panel>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-5">
      <Panel title="Choose a lead" className="lg:col-span-2">
        <div className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <label htmlFor={selectId} className="text-sm font-medium text-ink">
              Lead
            </label>
            <select
              id={selectId}
              value={leadId}
              onChange={(e) => {
                setLeadId(e.target.value);
                setGenerated(null);
              }}
              className="min-h-11 w-full rounded-lg border border-line bg-panel px-3 text-sm"
            >
              {leads.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.name} ({l.source})
                </option>
              ))}
            </select>
          </div>
          <button
            type="button"
            onClick={generate}
            className="min-h-11 rounded-lg bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700"
          >
            Generate summary and draft
          </button>
          <Badge tone="warning">Mock mode: no AI provider connected</Badge>
        </div>
      </Panel>

      <div className="flex flex-col gap-4 lg:col-span-3">
        {output ? (
          <>
            <Panel title="Summary" description="Generated from the lead and deal records">
              <p className="text-sm leading-relaxed text-ink">{output.summary}</p>
              <p className="mt-3 text-sm text-ink-muted">
                <span className="font-semibold text-ink">Suggested next step: </span>
                {output.nextStep}
              </p>
            </Panel>

            <Panel title="Draft message" description="Review and edit before you copy it. Nothing is sent automatically.">
              <label htmlFor="assistant-draft" className="sr-only">
                Draft message
              </label>
              <textarea
                id="assistant-draft"
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                rows={8}
                className="w-full rounded-lg border border-line bg-panel p-3 text-sm leading-relaxed focus:border-brand-500"
              />
              <div className="mt-3 flex flex-wrap items-center gap-3">
                <button
                  type="button"
                  onClick={copyDraft}
                  className="min-h-11 rounded-lg border border-line bg-panel px-4 text-sm font-medium text-ink hover:bg-slate-50"
                >
                  Copy draft
                </button>
                <p role="status" aria-live="polite" className="text-sm text-ink-muted">
                  {copyState === "copied"
                    ? "Copied. Paste it into your own messaging app."
                    : copyState === "failed"
                      ? "Copy was blocked by the browser. Select the text and copy it manually."
                      : ""}
                </p>
              </div>
            </Panel>
          </>
        ) : (
          <Notice>Choose a lead and select Generate to see a summary and a draft reply.</Notice>
        )}
      </div>
    </div>
  );
}
