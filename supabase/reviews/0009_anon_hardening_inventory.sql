-- 0009_anon_hardening_inventory.sql
-- READ-ONLY. Lists what the anon role can reach in schema public. It changes nothing and is safe to
-- run on production. Run each block separately and keep the output with the review notes.
--
-- Blocks:
--   1. anon table privileges, per table, with RLS state and anon-applicable policy count
--   2. default privileges that grant anon rights on newly created objects
--   3. public policies that apply to anon or PUBLIC
--   4. functions anon can execute, with SECURITY DEFINER flag, owner and PUBLIC EXECUTE state

-- 1. Table privileges held by anon (TRUNCATE is included: RLS does not restrict it).
select c.relname as table_name,
       c.relrowsecurity as rls_enabled,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policy_count,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname
          and ('anon' = any(p.roles) or 'public' = any(p.roles))) as anon_policy_count,
       has_table_privilege('anon', c.oid, 'SELECT') as anon_select,
       has_table_privilege('anon', c.oid, 'INSERT') as anon_insert,
       has_table_privilege('anon', c.oid, 'UPDATE') as anon_update,
       has_table_privilege('anon', c.oid, 'DELETE') as anon_delete,
       has_table_privilege('anon', c.oid, 'TRUNCATE') as anon_truncate
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p')
  and has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
order by c.relrowsecurity, c.relname;

-- 2. Default ACLs for public. Any table created by these roles arrives with anon rights.
select defaclrole::regrole::text as creating_role,
       defaclnamespace::regnamespace::text as schema,
       defaclobjtype as object_type,
       defaclacl::text as acl
from pg_default_acl
where defaclnamespace = 'public'::regnamespace
order by 1, 3;

-- 3. Policies that apply to anon or PUBLIC.
select tablename, policyname, cmd, roles::text, qual, with_check
from pg_policies
where schemaname = 'public' and ('anon' = any(roles) or 'public' = any(roles))
order by tablename, policyname;

-- 4. Functions anon can execute. SECURITY DEFINER runs with the owner's rights, so it bypasses RLS.
select p.proname,
       p.prosecdef as security_definer,
       pg_get_userbyid(p.proowner) as owner,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.prorettype::regtype::text as returns,
       exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'EXECUTE')
order by p.prosecdef desc, p.proname;
