-- 50_review_0006c_tests.sql
-- Synthetic-only. Runs supabase/reviews/0006c_rls_review.sql inside ONE transaction that
-- the runner ends with ROLLBACK, then checks the outcome. Each check raises FAIL on
-- violation, so psql stops with a non-zero exit.
--
-- Covers: clients and deals policies match 0006b; anon has no privileges on any of
-- the three tables; webhook_events is closed to authenticated users and to anon;
-- the review file is idempotent; service_role is not revoked.

-- ----------------------------------------------------------------- helpers
create function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end $$;

create function pg_temp.act_as_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
end $$;

create function pg_temp.act_as_postgres() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end $$;

-- Passes only if the statement is denied by privilege or RLS.
create function pg_temp.expect_denied(p_label text, p_sql text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL %: statement was allowed', p_label using errcode = 'P0100';
exception
  when insufficient_privilege then
    null;
end $$;

-- The runner puts 50a_webhook_fixture.sql and reviews/0006c_rls_review.sql in front of
-- this file inside the same transaction, so the review has run before any check here.

-- ----------------------------------------------------------------- checks
do $$
declare
  n int;
begin
  -- a) RLS on all three tables.
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
   where ns.nspname = 'public' and c.relname in ('clients','deals','webhook_events') and c.relrowsecurity;
  if n <> 3 then raise exception 'FAIL RLS: expected 3 tables with RLS on, found %', n using errcode = 'P0100'; end if;

  -- b) Policy set on clients and deals is the 0006b set: 8 policies, names as approved.
  select count(*) into n from pg_policies
   where schemaname = 'public' and tablename in ('clients','deals');
  if n <> 8 then raise exception 'FAIL policies: expected 8 on clients and deals, found %', n using errcode = 'P0100'; end if;

  -- c) webhook_events has no policies and no client grants.
  select count(*) into n from pg_policies where schemaname = 'public' and tablename = 'webhook_events';
  if n <> 0 then raise exception 'FAIL webhook policies: expected 0, found %', n using errcode = 'P0100'; end if;

  -- d) Idempotent: running the review file a second time changes nothing.
  select count(*) into n from pg_policies where schemaname = 'public' and tablename in ('clients','deals');
  if n <> 8 then raise exception 'FAIL idempotency: policy count changed to %', n using errcode = 'P0100'; end if;
end $$;

-- e) anon has no table privileges on the three tables.
select pg_temp.act_as_anon();
select pg_temp.expect_denied('anon read clients',   'select 1 from public.clients');
select pg_temp.expect_denied('anon read deals',     'select 1 from public.deals');
select pg_temp.expect_denied('anon read webhook',   'select 1 from public.webhook_events');
select pg_temp.expect_denied('anon write webhook',  'insert into public.webhook_events (payload) values (''{}'')');
select pg_temp.act_as_postgres();

-- f) authenticated cannot read or write webhook_events, with or without a JWT.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1'::uuid);
select pg_temp.expect_denied('authenticated read webhook',  'select 1 from public.webhook_events');
select pg_temp.expect_denied('authenticated write webhook', 'insert into public.webhook_events (payload) values (''{}'')');
select pg_temp.act_as_postgres();

-- g) service_role keeps its privileges. The review must not revoke them.
do $$
begin
  if not has_table_privilege('service_role', 'public.webhook_events', 'SELECT') then
    raise exception 'FAIL service_role: lost SELECT on webhook_events' using errcode = 'P0100';
  end if;
  if not has_table_privilege('service_role', 'public.clients', 'SELECT') then
    raise exception 'FAIL service_role: lost SELECT on clients' using errcode = 'P0100';
  end if;
end $$;

select 'passed: 0006c review file, webhook_events closed, clients/deals policies as approved';
