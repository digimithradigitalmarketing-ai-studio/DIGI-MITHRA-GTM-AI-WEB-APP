import path from "node:path";
import { defineConfig } from "vitest/config";

// Unit tests cover the pure automation modules. SQL integration tests run separately through
// supabase/tests/local/run_local.sh against a local Postgres replica.
export default defineConfig({
  resolve: {
    alias: { "@": path.resolve(__dirname, "src") },
  },
  test: {
    include: ["src/**/*.test.ts"],
    environment: "node",
  },
});
