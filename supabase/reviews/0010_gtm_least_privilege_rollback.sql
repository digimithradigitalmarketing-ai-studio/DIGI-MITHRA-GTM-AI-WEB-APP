-- 0010_gtm_least_privilege_rollback.sql
-- Rolls back 0010_gtm_least_privilege_proposed.sql. Restores TRUNCATE only where app_private.gtm_0010_truncate_baseline
-- recorded it before the hardening ran. It never grants anything the baseline does not name.
--
-- WARNING: restoring TRUNCATE re-opens the exposure this migration closes. A TRUNCATE grant is not filtered by RLS.
-- Run it on the replica, or on production only during an incident, with a verified backup and separate approval.
--
-- Required input, set in the same transaction before this script runs:
--   select set_config('gtm.confirm_reopen_truncate', 'yes', true);
-- Without it the script refuses. There is no default.
--
-- Apply inside one transaction (psql -1). It holds no begin or commit itself.

do $$
declare
  v_rec record;
  v_n integer := 0;
begin
  if coalesce(current_setting('gtm.confirm_reopen_truncate', true), '') <> 'yes' then
    raise exception 'refusing: set gtm.confirm_reopen_truncate to yes to restore TRUNCATE (this re-opens the exposure)';
  end if;

  if to_regclass('app_private.gtm_0010_truncate_baseline') is null then
    raise exception 'no baseline recorded: 0010_gtm_least_privilege_proposed.sql has not run';
  end if;

  -- Restore table grants exactly as recorded. Each row is a TRUNCATE grant that existed before 0010.
  for v_rec in
    select b.* from app_private.gtm_0010_truncate_baseline b where b.kind = 'table'
  loop
    if v_rec.grantee = 'PUBLIC' then
      execute format('grant truncate on table %s to public', v_rec.object);
    else
      execute format('grant truncate on table %s to %I', v_rec.object, v_rec.grantee);
    end if;
    v_n := v_n + 1;
  end loop;

  -- Restore the postgres default ACL entries for TRUNCATE exactly as recorded.
  for v_rec in
    select b.* from app_private.gtm_0010_truncate_baseline b where b.kind = 'default_table'
  loop
    if v_rec.grantee = 'PUBLIC' then
      execute 'alter default privileges for role postgres in schema public grant truncate on tables to public';
    else
      execute format('alter default privileges for role postgres in schema public grant truncate on tables to %I', v_rec.grantee);
    end if;
    v_n := v_n + 1;
  end loop;

  raise notice 'restored % TRUNCATE grant(s) from the 0010 baseline', v_n;
end $$;

-- The baseline table is kept. Dropping it is a separate, explicit decision.
-- drop table app_private.gtm_0010_truncate_baseline;
