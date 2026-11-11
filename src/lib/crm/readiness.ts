import { createClient } from "@/lib/supabase/server";
import { evaluateClientsReadiness, type ClientsReadiness } from "./readiness-state";

// Server-side loader. It runs public.clients_readiness() with the caller's own session, so no
// service key is involved. Error codes that mean the function is absent are "not configured"; any
// other failure is "unavailable", never "ready".
const FUNCTION_MISSING_CODES = new Set(["42883", "PGRST202"]);

export async function loadClientsReadiness(): Promise<ClientsReadiness> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("clients_readiness");
  if (error) {
    return FUNCTION_MISSING_CODES.has(error.code ?? "") ? { state: "not_configured" } : { state: "unavailable" };
  }
  return evaluateClientsReadiness(data);
}
