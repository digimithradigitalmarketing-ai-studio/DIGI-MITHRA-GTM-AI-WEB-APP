"use client";

import { useActionState, useState, type ChangeEvent } from "react";
import type { WorkflowFormState } from "@/app/(app)/automations/actions";
import { LIMITS, PRIORITIES, type FieldErrors, type FieldName, type Priority } from "@/lib/automations/definition";

export type WorkflowFormValues = {
  name: string;
  title: string;
  description: string;
  dueInHours: string;
  priority: Priority;
};

type Props = {
  action: (state: WorkflowFormState, formData: FormData) => Promise<WorkflowFormState>;
  defaults: WorkflowFormValues;
  submitLabel: string;
  pendingLabel: string;
  cancelHref: string;
};

const FIELD_CLASS =
  "mt-1 block w-full rounded-lg border border-line bg-panel px-3 py-2 text-sm text-ink shadow-sm focus:border-brand-600 focus:outline-none focus:ring-2 focus:ring-brand-600/20 aria-[invalid=true]:border-rose-400";

// Controlled inputs, so a failed submit keeps what the user typed. React resets uncontrolled
// inputs after a form action completes, which would throw the values away.
export function WorkflowForm({ action, defaults, submitLabel, pendingLabel, cancelHref }: Props) {
  const [state, formAction, pending] = useActionState<WorkflowFormState, FormData>(action, {});
  const [values, setValues] = useState<WorkflowFormValues>(defaults);
  const errors: FieldErrors = state.errors ?? {};

  function update(field: keyof WorkflowFormValues) {
    return (event: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) =>
      setValues((prev) => ({ ...prev, [field]: event.target.value }));
  }

  return (
    <form action={formAction} noValidate className="space-y-5">
      {state.error ? (
        <div role="alert" className="rounded-lg border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800">
          {state.error}
        </div>
      ) : null}

      <Field id="name" label="Automation name" error={errors.name} help={`Up to ${LIMITS.nameMax} characters.`}>
        <input id="name" name="name" type="text" maxLength={LIMITS.nameMax} value={values.name} onChange={update("name")} className={FIELD_CLASS} aria-invalid={!!errors.name} aria-describedby={errors.name ? "name-error" : undefined} />
      </Field>

      <fieldset className="rounded-lg border border-line p-4">
        <legend className="px-1 text-sm font-medium text-ink">Trigger</legend>
        <p className="text-sm text-ink-muted">Runs when a lead is created. Replays of the same lead never create a second task.</p>
      </fieldset>

      <Field id="title" label="Task title" error={errors.title} help="Use {{name}} for the lead's first name." >
        <input id="title" name="title" type="text" maxLength={LIMITS.titleMax} value={values.title} onChange={update("title")} className={FIELD_CLASS} aria-invalid={!!errors.title} aria-describedby={errors.title ? "title-error" : undefined} />
      </Field>

      <Field id="description" label="Task notes (optional)" error={errors.description} help={`Up to ${LIMITS.descriptionMax} characters.`}>
        <textarea id="description" name="description" rows={3} maxLength={LIMITS.descriptionMax} value={values.description} onChange={update("description")} className={FIELD_CLASS} aria-invalid={!!errors.description} />
      </Field>

      <div className="grid gap-5 sm:grid-cols-2">
        <Field id="dueInHours" label="Due in (hours)" error={errors.dueInHours} help={`Whole hours, ${LIMITS.dueInHoursMin} to ${LIMITS.dueInHoursMax}.`}>
          <input id="dueInHours" name="dueInHours" type="text" inputMode="numeric" value={values.dueInHours} onChange={update("dueInHours")} className={FIELD_CLASS} aria-invalid={!!errors.dueInHours} />
        </Field>

        <Field id="priority" label="Priority" error={errors.priority}>
          <select id="priority" name="priority" value={values.priority} onChange={update("priority")} className={FIELD_CLASS} aria-invalid={!!errors.priority}>
            {PRIORITIES.map((p) => (
              <option key={p} value={p}>{p.charAt(0).toUpperCase() + p.slice(1)}</option>
            ))}
          </select>
        </Field>
      </div>

      <div className="flex flex-wrap items-center gap-3 pt-2">
        <button type="submit" disabled={pending} className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-medium text-white hover:bg-brand-700 disabled:opacity-60">
          {pending ? pendingLabel : submitLabel}
        </button>
        <a href={cancelHref} className="rounded-lg px-4 py-2 text-sm font-medium text-ink-muted hover:text-ink">
          Cancel
        </a>
      </div>
    </form>
  );
}

function Field({
  id,
  label,
  help,
  error,
  children,
}: {
  id: FieldName | string;
  label: string;
  help?: string;
  error?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label htmlFor={id} className="block text-sm font-medium text-ink">
        {label}
      </label>
      {children}
      {error ? (
        <p id={`${id}-error`} className="mt-1 text-sm text-rose-700">
          {error}
        </p>
      ) : help ? (
        <p className="mt-1 text-xs text-ink-muted">{help}</p>
      ) : null}
    </div>
  );
}
