-- 0009_emulated_advisor.sql
-- READ-ONLY. Emulates the Supabase security advisor in SQL, so the replica and production can be
-- compared row for row. The hosted advisor only runs on a real project, so this is the replica's
-- stand-in. Each block returns a count and the objects behind it.
--
-- Lint names follow the advisor:
--   rls_enabled_no_policy                          (0008)
--   anon_security_definer_function_executable      (0028)
--   authenticated_security_definer_function_executable (0029)
-- Block 4 is NOT an advisor lint. The advisor does not report table privileges granted to anon,
-- so this block is the only check here that covers the TRUNCATE exposure.

-- 1. rls_enabled_no_policy
select 'rls_enabled_no_policy' as lint, count(*) as n, string_agg(c.relname, ', ' order by c.relname) as objects
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p') and c.relrowsecurity
  and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname);

-- 2. anon_security_definer_function_executable
select 'anon_security_definer_function_executable' as lint, count(*) as n, string_agg(p.proname, ', ' order by p.proname) as objects
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE');

-- 3. authenticated_security_definer_function_executable
select 'authenticated_security_definer_function_executable' as lint, count(*) as n, string_agg(p.proname, ', ' order by p.proname) as objects
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef and has_function_privilege('authenticated', p.oid, 'EXECUTE');

-- 4. Not an advisor lint: tables where anon holds any write or TRUNCATE privilege.
select 'anon_table_write_or_truncate' as check_name, count(*) as n, string_agg(c.relname, ', ' order by c.relname) as objects
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p')
  and (has_table_privilege('anon', c.oid, 'INSERT') or has_table_privilege('anon', c.oid, 'UPDATE')
    or has_table_privilege('anon', c.oid, 'DELETE') or has_table_privilege('anon', c.oid, 'TRUNCATE'));
