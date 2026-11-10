# DigiMithra AI Gym

Web app for running a gym's leads, members, deals, campaigns and automations. Built with Next.js (App Router), Tailwind CSS and TypeScript.

This build is **Phase 1 of the AI GTM Command Center build guide**: the responsive app shell with synthetic demo data. It has no database and no sign-in yet. Those arrive in Phase 2 (Supabase Auth and Postgres with row-level security).

## Run it

```bash
npm install
npm run dev        # http://localhost:3000 (redirects to /dashboard)
```

## Check it

```bash
npm run lint       # ESLint, must exit 0
npm run build      # production build, must exit 0
npm start          # serve the production build
```

## Screens

| Route | What it shows |
| --- | --- |
| `/dashboard` | KPI cards, pipeline by stage, tasks, recent leads, automation health |
| `/clients` | Members, families and corporate accounts |
| `/leads` | Searchable, filterable lead list |
| `/deals` | Deals grouped by stage with totals; overdue and upcoming tasks |
| `/campaigns` | Campaign drafts and approval status (sending disabled) |
| `/automations` | Rules and run log with idempotency keys and readable failures |
| `/ai` | Lead summary and draft message in mock mode (no API key, nothing sent) |
| `/reports` | Metrics with written definitions and a leads CSV download |
| `/settings` | Organization form with validation, roles, security checklist |

## Project layout

```
src/
  app/
    (app)/            authenticated-shell screens (route group keeps URLs clean)
    globals.css       design tokens (brand colors, fonts)
    layout.tsx        root layout and metadata
    not-found.tsx
  components/         UI primitives and client components
  lib/                synthetic data, pure metric functions, formatting, mock AI
  types/              shared domain types
supabase/migrations/  versioned SQL (empty until Phase 2)
tests/                automated tests (added from Phase 3 onward)
```

## Data and safety

- All records are synthetic. No real members, leads or payments are stored.
- `AS_OF` in `src/lib/data.ts` fixes the report date so pages prerender. Phase 4 replaces it with a request-time date.
- The AI assistant runs in mock mode. Its drafts are for a person to review; nothing is sent automatically.
- Campaigns are drafted and approved here, and sending is disabled.

## Next phases

1. Phase 2: Supabase project, migrations, RLS, sign-in, two-user isolation test.
2. Phase 3: persisted clients, leads and notes with validated server writes.
3. Phase 4 onward: deals and tasks, automation engine, AI with a real provider, campaigns, reports, deployment.

See the build guide for each phase's acceptance tests. Do not start Phase 2 until Phase 1's checks pass.
