// Reads the public Supabase settings. Only the publishable key is allowed here;
// service-role or secret keys must never be referenced from app code.
// process.env.NEXT_PUBLIC_* must be referenced literally so Next can inline it.
export function getSupabaseEnv() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

  if (!url || !key) {
    throw new Error(
      "Supabase is not configured. Set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY in .env.local.",
    );
  }

  return { url, key };
}
