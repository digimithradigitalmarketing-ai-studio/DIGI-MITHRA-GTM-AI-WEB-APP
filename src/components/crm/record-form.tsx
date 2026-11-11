"use client";

import Link from "next/link";
import { useActionState, useState, type ChangeEvent } from "react";
import type { CrmFormState } from "@/lib/crm/state";

export type FieldSpec =
  | {
      kind: "text" | "email" | "tel" | "date" | "number";
      name: string;
      label: string;
      help?: string;
      required?: boolean;
      maxLength?: number;
      min?: number;
      max?: number;
      step?: number;
    }
  | { kind: "textarea"; name: string; label: string; help?: string; maxLength?: number }
  | {
      kind: "select";
      name: string;
      label: string;
      help?: string;
      options: { value: string; label: string }[];
      placeholder?: string;
    }
  | { kind: "checkbox"; name: string; label: string; help?: string };

type Props = {
  action: (state: CrmFormState, formData: FormData) => Promise<CrmFormState>;
  fields: FieldSpec[];
  defaults: Record<string, string>;
  submitLabel: string;
  pendingLabel: string;
  cancelHref: string;
};

const CONTROL =
  "mt-1 block w-full min-h-11 rounded-lg border border-line bg-panel px-3 py-2 text-sm text-ink shadow-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20 aria-[invalid=true]:border-rose-400";

// Controlled inputs keep what the user typed when validation fails. Uncontrolled inputs would be
// cleared by React after the action returns.
export function RecordForm({ action, fields, defaults, submitLabel, pendingLabel, cancelHref }: Props) {
  const [state, formAction, pending] = useActionState<CrmFormState, FormData>(action, {});
  const [values, setValues] = useState<Record<string, string>>(defaults);
  const errors = state.errors ?? {};

  function update(name: string) {
    return (event: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) =>
      setValues((prev) => ({ ...prev, [name]: event.target.value }));
  }

  return (
    <form action={formAction} noValidate className="space-y-5">
      {state.error ? (
        <div role="alert" className="rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
          {state.error}
        </div>
      ) : null}

      <div className="grid gap-5 sm:grid-cols-2">
        {fields.map((field) => {
          const error = errors[field.name];
          const errorId = `${field.name}-error`;
          const helpId = `${field.name}-help`;
          const describedBy = [error ? errorId : null, field.help ? helpId : null].filter(Boolean).join(" ") || undefined;
          const wide = field.kind === "textarea" || field.kind === "checkbox" ? "sm:col-span-2" : "";

          return (
            <div key={field.name} className={`min-w-0 ${wide}`}>
              {field.kind === "checkbox" ? (
                <label className="flex min-h-11 items-start gap-3 text-sm text-ink">
                  <input
                    type="checkbox"
                    name={field.name}
                    checked={values[field.name] === "on"}
                    onChange={(e) => setValues((prev) => ({ ...prev, [field.name]: e.target.checked ? "on" : "" }))}
                    aria-describedby={describedBy}
                    className="mt-1 h-4 w-4 rounded border-line text-brand-600 focus:ring-brand-600"
                  />
                  <span>
                    {field.label}
                    {field.help ? <span id={helpId} className="mt-0.5 block text-xs text-ink-muted">{field.help}</span> : null}
                  </span>
                </label>
              ) : (
                <>
                  <label htmlFor={field.name} className="block text-sm font-medium text-ink">
                    {field.label}
                    {"required" in field && field.required ? <span className="text-rose-700"> *</span> : null}
                  </label>
                  {field.kind === "textarea" ? (
                    <textarea
                      id={field.name}
                      name={field.name}
                      rows={4}
                      maxLength={field.maxLength}
                      value={values[field.name] ?? ""}
                      onChange={update(field.name)}
                      aria-invalid={!!error}
                      aria-describedby={describedBy}
                      className={CONTROL}
                    />
                  ) : field.kind === "select" ? (
                    <select
                      id={field.name}
                      name={field.name}
                      value={values[field.name] ?? ""}
                      onChange={update(field.name)}
                      aria-invalid={!!error}
                      aria-describedby={describedBy}
                      className={CONTROL}
                    >
                      <option value="">{field.placeholder ?? "Choose…"}</option>
                      {field.options.map((o) => (
                        <option key={o.value} value={o.value}>{o.label}</option>
                      ))}
                    </select>
                  ) : (
                    <input
                      id={field.name}
                      name={field.name}
                      type={field.kind}
                      required={"required" in field ? field.required : false}
                      maxLength={"maxLength" in field ? field.maxLength : undefined}
                      min={field.kind === "number" ? field.min : undefined}
                      max={field.kind === "number" ? field.max : undefined}
                      step={field.kind === "number" ? field.step : undefined}
                      value={values[field.name] ?? ""}
                      onChange={update(field.name)}
                      aria-invalid={!!error}
                      aria-describedby={describedBy}
                      className={CONTROL}
                    />
                  )}
                  {field.help ? <p id={helpId} className="mt-1 text-xs text-ink-muted">{field.help}</p> : null}
                </>
              )}
              {error ? <p id={errorId} role="alert" className="mt-1 text-sm text-rose-700">{error}</p> : null}
            </div>
          );
        })}
      </div>

      <div className="flex flex-col-reverse gap-3 border-t border-line pt-5 sm:flex-row sm:justify-end">
        <Link href={cancelHref} className="inline-flex min-h-11 items-center justify-center rounded-lg border border-line px-4 text-sm font-medium text-ink hover:bg-slate-50">
          Cancel
        </Link>
        <button
          type="submit"
          disabled={pending}
          className="inline-flex min-h-11 items-center justify-center rounded-lg bg-brand-600 px-5 text-sm font-semibold text-white hover:bg-brand-700 disabled:opacity-60"
        >
          {pending ? pendingLabel : submitLabel}
        </button>
      </div>
    </form>
  );
}
