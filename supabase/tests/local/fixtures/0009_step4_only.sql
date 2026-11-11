-- 0009_step4_only.sql
-- LOCAL FIXTURE ONLY. Never run on production as written.
-- Step 4 of supabase/reviews/0009_anon_hardening_proposed.sql on its own: remove PUBLIC and anon EXECUTE on
-- rls_auto_enable. Nothing else from 0009 is applied (no table revokes, no plans grant, no default-ACL change).
revoke execute on function public.rls_auto_enable() from public, anon;
