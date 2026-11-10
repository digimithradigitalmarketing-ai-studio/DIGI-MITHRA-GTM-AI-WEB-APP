import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { getSupabaseEnv } from "./env";

// Used by the proxy only. Refreshes the Supabase session cookies on each
// request and returns the verified JWT claims (or null when signed out).
// This is an optimistic check for routing. Data access is still enforced by
// RLS in the database, so a proxy bypass cannot expose rows.
export async function updateSession(request: NextRequest) {
  const { url, key } = getSupabaseEnv();
  let response = NextResponse.next({ request });

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  // getClaims verifies the token signature; call it before any other logic.
  const { data } = await supabase.auth.getClaims();
  const claims = data?.claims ?? null;

  return { response, claims };
}
