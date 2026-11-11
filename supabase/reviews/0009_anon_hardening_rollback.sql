-- 0009_anon_hardening_rollback.sql
-- Rolls back 0009_anon_hardening_proposed.sql. Restores the production state recorded on the
-- inventory date: anon held ALL (arwdDxtm) on every public table, the postgres default ACL granted
-- anon ALL on new tables, and EXECUTE on rls_auto_enable came from PUBLIC and anon.
--
-- Apply inside one transaction (psql -1). It holds no begin or commit itself.
-- Use only if the hardening breaks a real caller and that caller cannot be fixed quickly.

do $$
declare
  t record;
begin
  for t in
    select c.oid::regclass as rel
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    execute format('grant all on table %s to anon', t.rel);
  end loop;

  execute 'alter default privileges for role postgres in schema public grant all on tables to anon';

  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'grant execute on function public.rls_auto_enable() to public, anon';
  end if;
end $$;
