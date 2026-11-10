import { createClient } from "@/lib/supabase/server";
import { signOut } from "@/app/login/actions";

// Server component. Shows the signed-in email and a sign-out button.
// Rendered inside <Suspense> by the topbar because it reads request cookies.
export async function AccountMenu() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  const email = typeof data?.claims?.email === "string" ? data.claims.email : null;

  if (!email) return null;

  return (
    <div className="flex items-center gap-2">
      <span className="hidden max-w-[12rem] truncate text-sm text-ink-muted lg:block" title={email}>
        {email}
      </span>
      <form action={signOut}>
        <button
          type="submit"
          className="rounded-md border border-line px-3 py-1.5 text-xs font-medium text-ink hover:bg-canvas"
        >
          Sign out
        </button>
      </form>
    </div>
  );
}
