import { createBrowserClient } from "@supabase/ssr";
import { getSupabaseEnv } from "./env";

// Browser client for Client Components. Uses only the publishable key; access
// is enforced by RLS on the database, not by hiding anything in the UI.
export function createClient() {
  const { url, key } = getSupabaseEnv();
  return createBrowserClient(url, key);
}
