-- 0010_gtm_least_privilege_proposed.sql
-- PROPOSED. NOT APPLIED. Do not run against production until the backup gate in supabase/reviews/DEPLOYMENT_PLAN.md
-- is closed and this file is approved. Apply it inside one transaction (psql -1). It holds no begin or commit itself.
--
-- Scope: TRUNCATE only. PostgREST does not expose TRUNCATE, and RLS does not filter it, so a grant of TRUNCATE
-- is the one table privilege that policies cannot constrain. This file removes it from anon and authenticated
-- (and PUBLIC, which holds no table grant today) on every table in schema public, including public.plans.
--
-- What it does:
--   0. Records every TRUNCATE grant it is about to remove, plus the postgres default ACL for tables, into
--      app_private.gtm_0010_truncate_baseline. The rollback reads only this record.
--   1. Revokes TRUNCATE on every public table from PUBLIC, anon and authenticated.
--   2. Stops future tables created by the postgres role from granting TRUNCATE to anon or authenticated.
--
-- What it does NOT do (kept on purpose):
--   * It does not touch SELECT, INSERT, UPDATE or DELETE. RLS still decides which rows each role reaches.
--   * It does not touch service_role, postgres or supabase_admin. Those are not the exposure in scope.
--   * It does not change the supabase_admin default ACL. Only the owner of that default can change it, so the
--     statement is in the comment at the end, for Supabase Support (see supabase/reviews/0010_support_request.md).
--   * It does not remove REFERENCES, TRIGGER or MAINTAIN. Those are listed as findings in the notes, not in this file.
--   * It does not disable RLS, change any policy, or change any trigger or function.

-- ----------------------------------------------------------------- 0. baseline record (read by the rollback)
create table if not exists app_private.gtm_0010_truncate_baseline (
  kind text not null,            -- 'table' | 'default_table'
  object text not null,          -- schema-qualified table name, or 'postgres.public' for the default ACL
  grantee text not null,         -- 'anon', 'authenticated' or 'PUBLIC'
  privilege text not null,       -- always 'TRUNCATE' in this file
  is_grantable boolean not null,
  recorded_at timestamptz not null default now(),
  primary key (kind, object, grantee, privilege)
);

-- Re-running the proposal must not change the record: insert only rows that are not yet recorded.
insert into app_private.gtm_0010_truncate_baseline (kind, object, grantee, privilege, is_grantable)
select 'table', format('%I.%I', n.nspname, c.relname),
       case when a.grantee = 0 then 'PUBLIC' else r.rolname end, a.privilege_type, a.is_grantable
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(c.relacl) a
  left join pg_roles r on r.oid = a.grantee
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and a.privilege_type = 'TRUNCATE'
   and (a.grantee = 0 or r.rolname in ('anon', 'authenticated'))
on conflict do nothing;

insert into app_private.gtm_0010_truncate_baseline (kind, object, grantee, privilege, is_grantable)
select 'default_table', pg_get_userbyid(d.defaclrole)::text || '.public',
       case when a.grantee = 0 then 'PUBLIC' else r.rolname end, a.privilege_type, a.is_grantable
  from pg_default_acl d
  join pg_namespace n on n.oid = d.defaclnamespace
  cross join lateral aclexplode(d.defaclacl) a
  left join pg_roles r on r.oid = a.grantee
 where n.nspname = 'public' and d.defaclobjtype = 'r'
   and d.defaclrole = (select oid from pg_roles where rolname = 'postgres')
   and a.privilege_type = 'TRUNCATE'
   and (a.grantee = 0 or r.rolname in ('anon', 'authenticated'))
on conflict do nothing;

-- ----------------------------------------------------------------- 1-2. the hardening
do $$
declare
  t record;
begin
  -- 1. Every table in public: no TRUNCATE for PUBLIC, anon or authenticated. Other privileges are not touched.
  for t in
    select c.oid::regclass as rel
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    execute format('revoke truncate on table %s from public, anon, authenticated', t.rel);
  end loop;

  -- 2. Future tables created by the postgres role do not inherit TRUNCATE for anon or authenticated.
  execute 'alter default privileges for role postgres in schema public revoke truncate on tables from anon, authenticated';
end $$;

-- ----------------------------------------------------------------- not run here: supabase_admin defaults
-- Production's supabase_admin default ACL may also grant TRUNCATE to anon and authenticated on new public tables.
-- Only supabase_admin, or a role that can SET ROLE to it, can change that default. The exact statement is:
--
--   alter default privileges for role supabase_admin in schema public revoke truncate on tables from anon, authenticated;
--
-- Do not run it from this migration. It goes to Supabase Support (supabase/reviews/0010_support_request.md).
