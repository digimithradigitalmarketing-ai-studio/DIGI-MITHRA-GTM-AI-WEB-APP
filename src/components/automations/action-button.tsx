"use client";

import { useActionState } from "react";
import type { ActionState } from "@/app/(app)/automations/actions";

type Props = {
  action: (prev: ActionState, formData: FormData) => Promise<ActionState>;
  label: string;
  pendingLabel: string;
  variant?: "primary" | "secondary";
};

const VARIANT_CLASS: Record<NonNullable<Props["variant"]>, string> = {
  primary: "bg-brand-600 text-white hover:bg-brand-700",
  secondary: "border border-line bg-panel text-ink hover:bg-slate-50",
};

// Runs one server action from a button and shows its result inline. The action checks the caller
// and the database enforces the change, so this component only displays what came back.
export function ActionButton({ action, label, pendingLabel, variant = "secondary" }: Props) {
  const [state, formAction, pending] = useActionState<ActionState, FormData>(action, null);
  // Once the database reports the function is not installed, the button stays disabled and the
  // explanation stays visible, so the user is not invited to click again.
  const unavailable = state?.unavailable === true;
  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <button
        type="submit"
        disabled={pending || unavailable}
        className={`rounded-lg px-3.5 py-2 text-sm font-medium disabled:opacity-60 ${VARIANT_CLASS[variant]}`}
      >
        {pending ? pendingLabel : unavailable ? "Retry unavailable" : label}
      </button>
      {state?.error ? <p role="alert" className="text-sm text-rose-700">{state.error}</p> : null}
      {state?.ok && state.message ? <p role="status" className="text-sm text-emerald-800">{state.message}</p> : null}
    </form>
  );
}
