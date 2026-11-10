"use client";

import { useId, useState } from "react";

type OrgDetails = { name: string; timezone: string; currency: string };

const fieldClass =
  "min-h-11 w-full rounded-lg border border-line bg-panel px-3 text-sm text-ink focus:border-brand-500";

/**
 * Organization details form. Phase 1 keeps values in memory only; Phase 2
 * saves them server-side with validation and an audit record.
 */
export function SettingsForm({ initial }: { initial: OrgDetails }) {
  const nameId = useId();
  const tzId = useId();
  const currencyId = useId();
  const [values, setValues] = useState<OrgDetails>(initial);
  const [errors, setErrors] = useState<Partial<Record<keyof OrgDetails, string>>>({});
  const [message, setMessage] = useState("");

  function update<K extends keyof OrgDetails>(key: K, value: string) {
    setValues((v) => ({ ...v, [key]: value }));
    setErrors((e) => ({ ...e, [key]: undefined }));
    setMessage("");
  }

  function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const next: Partial<Record<keyof OrgDetails, string>> = {};
    if (values.name.trim().length < 2) next.name = "Enter a gym name with at least 2 characters.";
    if (values.name.trim().length > 80) next.name = "Keep the gym name under 80 characters.";
    if (!/^[A-Za-z_]+\/[A-Za-z_]+$/.test(values.timezone)) {
      next.timezone = "Use an IANA timezone such as Asia/Kolkata.";
    }
    if (!/^[A-Z]{3}$/.test(values.currency)) next.currency = "Use a 3-letter currency code such as INR.";

    setErrors(next);
    if (Object.keys(next).length > 0) {
      setMessage("Fix the highlighted fields and try again.");
      return;
    }
    setMessage("Saved for this browser session. Persistence arrives with Supabase in Phase 2.");
  }

  return (
    <form onSubmit={save} noValidate aria-describedby="settings-status" className="grid grid-cols-1 gap-4 sm:max-w-xl">
      <div className="flex flex-col gap-1.5">
        <label htmlFor={nameId} className="text-sm font-medium text-ink">
          Gym name
        </label>
        <input
          id={nameId}
          value={values.name}
          onChange={(e) => update("name", e.target.value)}
          aria-invalid={Boolean(errors.name)}
          aria-describedby={errors.name ? `${nameId}-error` : undefined}
          className={fieldClass}
        />
        {errors.name ? (
          <p id={`${nameId}-error`} className="text-sm text-rose-700">
            {errors.name}
          </p>
        ) : null}
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor={tzId} className="text-sm font-medium text-ink">
          Timezone
        </label>
        <input
          id={tzId}
          value={values.timezone}
          onChange={(e) => update("timezone", e.target.value)}
          aria-invalid={Boolean(errors.timezone)}
          aria-describedby={errors.timezone ? `${tzId}-error` : `${tzId}-hint`}
          className={fieldClass}
        />
        {errors.timezone ? (
          <p id={`${tzId}-error`} className="text-sm text-rose-700">
            {errors.timezone}
          </p>
        ) : (
          <p id={`${tzId}-hint`} className="text-xs text-ink-muted">
            IANA name, for example Asia/Kolkata.
          </p>
        )}
      </div>

      <div className="flex flex-col gap-1.5">
        <label htmlFor={currencyId} className="text-sm font-medium text-ink">
          Currency
        </label>
        <input
          id={currencyId}
          value={values.currency}
          onChange={(e) => update("currency", e.target.value.toUpperCase())}
          maxLength={3}
          aria-invalid={Boolean(errors.currency)}
          aria-describedby={errors.currency ? `${currencyId}-error` : undefined}
          className={fieldClass}
        />
        {errors.currency ? (
          <p id={`${currencyId}-error`} className="text-sm text-rose-700">
            {errors.currency}
          </p>
        ) : null}
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <button
          type="submit"
          className="min-h-11 rounded-lg bg-brand-600 px-4 text-sm font-semibold text-white hover:bg-brand-700"
        >
          Save details
        </button>
        <p id="settings-status" role="status" aria-live="polite" className="text-sm text-ink-muted">
          {message}
        </p>
      </div>
    </form>
  );
}
