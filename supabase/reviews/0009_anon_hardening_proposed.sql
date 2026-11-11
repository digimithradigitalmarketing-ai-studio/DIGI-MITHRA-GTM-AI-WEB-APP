-- 0009_anon_hardening_proposed.sql
-- PROPOSED. NOT APPLIED. Do not run against production until the backup and approval gates in
-- 0009_anon_hardening_notes.md are closed. Apply it inside one transaction (psql -1, or the migration runner's
-- own transaction), so a failure leaves nothing half-applied. It holds no begin or commit itself.
--
-- What it does:
--   0. Records anon's current privileges (tables, rls_auto_enable, and the default ACLs of postgres and
--      supabase_admin) into app_private.gtm_0009_anon_baseline. The rollback reads only this record.
--   1. Revokes every table privilege from anon in schema public (TRUNCATE included).
--   2. Stops future tables created by postgres from granting anon anything.
--   3. Keeps one intentional read: public.plans for anon (the plans_read policy). Its grant is reset to SELECT only.
--   4. Removes EXECUTE on rls_auto_enable from PUBLIC and anon. The ensure_rls event trigger still runs it,
--      because event triggers are not gated by EXECUTE for the table owner (tested in suite 34).
--
-- What it does NOT do (kept on purpose):
--   * It does not revoke EXECUTE on the public landing-page and web-chat SECURITY DEFINER functions.
--     Anonymous visitors need them. Each has its own review item in the notes.
--   * It does not revoke the supabase_admin default privileges. Only the owner of those defaults can change them,
--     so the exact statement is in the comment at the end, for Supabase support to run.
--   * It does not revoke authenticated privileges (see the notes: authenticated also holds TRUNCATE).
--   * It does not touch any RLS policy, and it does not disable RLS or any trigger.

-- ----------------------------------------------------------------- 0. baseline record (read by the rollback)
create table if not exists app_private.gtm_0009_anon_baseline (
  kind text not null,            -- 'table' | 'function' | 'default_table'
  object text not null,          -- schema-qualified name, or the function identity, or 'role.schema'
  grantee text not null,         -- 'anon' or 'PUBLIC'
  privilege text not null,
  is_grantable boolean not null,
  recorded_at timestamptz not null default now(),
  primary key (kind, object, grantee, privilege)
);

-- Re-running the proposal must not change the record: insert only rows that are not yet recorded.
insert into app_private.gtm_0009_anon_baseline (kind, object, grantee, privilege, is_grantable)
select 'table', format('%I.%I', n.nspname, c.relname),
       case when a.grantee = 0 then 'PUBLIC' else 'anon' end, a.privilege_type, a.is_grantable
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral aclexplode(c.relacl) a
 where n.nspname = 'public' and c.relkind in ('r', 'p')
   and a.grantee in (0, (select oid from pg_roles where rolname = 'anon'))
on conflict do nothing;

insert into app_private.gtm_0009_anon_baseline (kind, object, grantee, privilege, is_grantable)
select 'function', 'public.rls_auto_enable()',
       case when a.grantee = 0 then 'PUBLIC' else 'anon' end, a.privilege_type, a.is_grantable
  from pg_proc p
  cross join lateral aclexplode(p.proacl) a
 where p.oid = to_regprocedure('public.rls_auto_enable()')
   and a.grantee in (0, (select oid from pg_roles where rolname = 'anon'))
on conflict do nothing;

insert into app_private.gtm_0009_anon_baseline (kind, object, grantee, privilege, is_grantable)
select 'default_table', pg_get_userbyid(d.defaclrole)::text || '.public',
       case when a.grantee = 0 then 'PUBLIC' else 'anon' end, a.privilege_type, a.is_grantable
  from pg_default_acl d
  join pg_namespace n on n.oid = d.defaclnamespace
  cross join lateral aclexplode(d.defaclacl) a
 where n.nspname = 'public' and d.defaclobjtype = 'r'
   and a.grantee in (0, (select oid from pg_roles where rolname = 'anon'))
on conflict do nothing;

-- ----------------------------------------------------------------- 1-4. the hardening
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

  -- 2. Future tables created by the postgres role give anon nothing by default.
  execute 'alter default privileges for role postgres in schema public revoke all on tables from anon';

  -- 3. plans is public pricing. anon reads it through the plans_read policy, and nothing else.
  if to_regclass('public.plans') is not null then
    execute 'grant select on public.plans to anon';
  end if;

  -- 4. Event-trigger helper: remove PUBLIC and anon execute. ensure_rls keeps firing (suite 34).
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon';
  end if;
end $$;

-- ----------------------------------------------------------------- not run here: supabase_admin defaults
-- Production also has default table privileges for supabase_admin in schema public that grant anon everything
-- (recorded in the baseline as default_table / supabase_admin.public). Only supabase_admin, or a role that
-- can SET ROLE to it, can change them. The exact statement for Supabase support is:
--
--   alter default privileges for role supabase_admin in schema public revoke all on tables from anon;
--
-- Do not run it from this migration. It is recorded in notes section "supabase_admin requirement".
