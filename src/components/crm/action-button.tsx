"use client";

import { useRouter } from "next/navigation";
import { useActionState, useEffect, type FormEvent } from "react";
import type { CrmActionState } from "@/lib/crm/state";

type Props = {
  action: (prev: CrmActionState, formData: FormData) => Promise<CrmActionState>;
  label: string;
  pendingLabel: string;
  tone?: "primary" | "secondary" | "danger";
  confirm?: string;
};

const TONE: Record<NonNullable<Props["tone"]>, string> = {
  primary: "bg-brand-600 text-white hover:bg-brand-700",
  secondary: "border border-line bg-panel text-ink hover:bg-slate-50",
  danger: "border border-rose-300 bg-panel text-rose-800 hover:bg-rose-50",
};

// Runs one server action from a button. Asks for confirmation first when a message is given,
// shows the result, and follows redirectTo when the action returns one (used after a delete).
export function CrmActionButton({ action, label, pendingLabel, tone = "secondary", confirm }: Props) {
  const router = useRouter();
  const [state, formAction, pending] = useActionState<CrmActionState, FormData>(action, null);

  useEffect(() => {
    if (state?.ok && state.redirectTo) router.push(state.redirectTo);
  }, [state, router]);

  function onSubmit(event: FormEvent<HTMLFormElement>) {
    if (confirm && !window.confirm(confirm)) event.preventDefault();
  }

  return (
    <form action={formAction} onSubmit={onSubmit} className="flex flex-col items-start gap-2">
      <button
        type="submit"
        disabled={pending}
        className={`min-h-11 rounded-lg px-4 text-sm font-medium disabled:opacity-60 ${TONE[tone]}`}
      >
        {pending ? pendingLabel : label}
      </button>
      {state?.error ? <p role="alert" className="text-sm text-rose-700">{state.error}</p> : null}
      {state?.ok && state.message && !state.redirectTo ? (
        <p role="status" className="text-sm text-emerald-800">{state.message}</p>
      ) : null}
    </form>
  );
}
