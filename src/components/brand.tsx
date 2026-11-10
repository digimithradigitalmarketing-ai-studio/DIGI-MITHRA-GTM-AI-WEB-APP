import Link from "next/link";

/**
 * Wordmark. Use "dark" on the ink sidebar and "light" on white surfaces such as
 * the top bar. Pure markup, no client code.
 */
export function Brand({ variant = "dark" }: { variant?: "dark" | "light" }) {
  const isDark = variant === "dark";
  return (
    <Link href="/dashboard" className="flex items-center gap-2.5 rounded-lg" aria-label="DigiMithra AI Gym home">
      <span
        aria-hidden="true"
        className="flex h-9 w-9 items-center justify-center rounded-lg bg-brand-500 text-sm font-bold text-white"
      >
        DM
      </span>
      <span className="flex flex-col leading-tight">
        <span className={`text-sm font-semibold ${isDark ? "text-white" : "text-ink"}`}>DigiMithra</span>
        <span className={`text-xs font-medium ${isDark ? "text-brand-200" : "text-brand-700"}`}>AI Gym</span>
      </span>
    </Link>
  );
}
