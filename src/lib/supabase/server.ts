import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabaseEnv } from "./env";

// Server client for Server Components, Server Actions and Route Handlers.
// Reads the session from request cookies. Call inside a request scope only
// (it reads cookies), and wrap any component that calls it in <Suspense>
// because cacheComponents is enabled.
export async function createClient() {
  const cookieStore = await cookies();
  const { url, key } = getSupabaseEnv();

  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Cookies cannot be written during Server Component rendering. The
          // proxy refreshes the session on every request, so this is safe to skip.
        }
      },
    },
  });
}
