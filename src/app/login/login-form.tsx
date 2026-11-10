"use client";

import { useActionState } from "react";
import { signIn, type SignInState } from "./actions";

const initialState: SignInState = {};

export function LoginForm({ next }: { next: string }) {
  const [state, action, pending] = useActionState(signIn, initialState);

  return (
    <form action={action} className="space-y-4">
      <input type="hidden" name="next" value={next} />

      <label className="block">
        <span className="text-sm font-medium text-ink">Email</span>
        <input
          name="email"
          type="email"
          autoComplete="email"
          required
          className="mt-1 w-full rounded-md border border-line bg-panel px-3 py-2 text-sm text-ink"
        />
      </label>

      <label className="block">
        <span className="text-sm font-medium text-ink">Password</span>
        <input
          name="password"
          type="password"
          autoComplete="current-password"
          required
          className="mt-1 w-full rounded-md border border-line bg-panel px-3 py-2 text-sm text-ink"
        />
      </label>

      {state.error ? (
        <p role="alert" className="text-sm text-red-700">
          {state.error}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-md bg-brand-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-60"
      >
        {pending ? "Signing in..." : "Sign in"}
      </button>
    </form>
  );
}
