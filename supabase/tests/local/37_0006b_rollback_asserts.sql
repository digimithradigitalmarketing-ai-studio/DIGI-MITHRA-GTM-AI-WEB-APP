-- 37_0006b_rollback_asserts.sql
-- Run AFTER supabase/rollbacks/0006b_down.sql, against the state it leaves. Each check raises on failure.
-- Covers what must return to the pre-0006b baseline, and what must stay revoked on purpose.
-- The category-by-category comparison against the baseline snapshot is done in run_local.sh (path F).

do $$
declare
  t text;
  v_fail text[] := '{}';
  v_priv text;
begin
  foreach t in array array['companies', 'clients', 'deals'] loop
    -- Intentionally left revoked: anon holds no privilege at all on these tables.
    foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] loop
      if has_table_privilege('anon', 'public.' || t, v_priv) then
        v_fail := array_append(v_fail, format('anon still holds %s on %s after the rollback', v_priv, t));
      end if;
    end loop;
    -- Intentionally left revoked: authenticated loses TRUNCATE, REFERENCES, TRIGGER and MAINTAIN.
    foreach v_priv in array array['TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN'] loop
      if has_table_privilege('authenticated', 'public.' || t, v_priv) then
        v_fail := array_append(v_fail, format('authenticated regained %s on %s', v_priv, t));
      end if;
    end loop;
    -- Kept: authenticated keeps the four DML privileges that the rollback re-grants.
    foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if not has_table_privilege('authenticated', 'public.' || t, v_priv) then
        v_fail := array_append(v_fail, format('authenticated lost %s on %s', v_priv, t));
      end if;
    end loop;
    -- RLS stays enabled (0006b_down deliberately keeps it on).
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      v_fail := array_append(v_fail, format('RLS was disabled on %s', t));
    end if;
  end loop;

  -- Baseline: the 0006b policies are gone. The four companies_* policies from 0006 stay.
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('clients', 'deals')) then
    v_fail := array_append(v_fail, 'clients or deals policies remain after the rollback');
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'companies') <> 4 then
    v_fail := array_append(v_fail, 'companies policies are not the four from 0006');
  end if;

  -- Baseline: the triggers and functions 0006b created are gone.
  if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
              where c.relname in ('companies', 'clients', 'deals') and not t.tgisinternal) then
    v_fail := array_append(v_fail, 'a trigger on companies, clients or deals remains after the rollback');
  end if;
  if to_regprocedure('app_private.guard_archive()') is not null
     or to_regprocedure('app_private.sync_deal_status()') is not null then
    v_fail := array_append(v_fail, 'guard_archive or sync_deal_status remains after the rollback');
  end if;

  if array_length(v_fail, 1) is not null then
    raise exception '0006b rollback asserts failed (%): %', array_length(v_fail, 1), array_to_string(v_fail, '; ');
  end if;
  raise notice '0006b rollback asserts passed (intentional revokes held; baseline policies, triggers and functions restored)';
end $$;
