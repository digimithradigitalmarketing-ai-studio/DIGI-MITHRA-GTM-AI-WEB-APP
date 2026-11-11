-- 0009_anon_hardening_proposed.sql
-- PROPOSED. NOT APPLIED. Do not run against production until the backup and approval gates in
-- 0009_anon_hardening_notes.md are closed. Apply it inside one transaction (psql -1, or the migration runner's
-- own transaction), so a failure leaves nothing half-applied. It holds no begin or commit itself.
--
-- What it does:
--   1. Revokes every table privilege from anon in schema public (TRUNCATE included).
--   2. Stops future tables created by postgres from granting anon anything.
--   3. Keeps one intentional read: public.plans for anon (the plans_read policy).
--   4. Removes EXECUTE on rls_auto_enable from PUBLIC and anon. It is an event-trigger helper that
--      nothing should call over RPC.
--
-- What it does NOT do (kept on purpose):
--   * It does not revoke EXECUTE on the public landing-page and web-chat SECURITY DEFINER functions.
--     Anonymous visitors need them. Each has its own review item in the notes.
--   * It does not touch authenticated grants or any RLS policy.
--   * It does not disable RLS or change any trigger.

do $$
declare
  t record;
begin
  -- 1. Every table in public: no privileges for anon.
  for t in
    select c.oid::regclass as rel
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    execute format('revoke all on table %s from anon', t.rel);
  end loop;

  -- 2. Future tables from the postgres role get no anon rights by default.
  execute 'alter default privileges for role postgres in schema public revoke all on tables from anon';

  -- 3. plans is public pricing. Read-only, and only through its existing policy.
  if to_regclass('public.plans') is not null then
    execute 'grant select on public.plans to anon';
  end if;

  -- 4. Event-trigger helper: remove PUBLIC and anon execute.
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon';
  end if;
end $$;

