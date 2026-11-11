-- 37_0006b_rollback_asserts.sql
-- Run AFTER supabase/rollbacks/0006b_down.sql, against the state it leaves. Each check raises on failure.
-- R2 (revised): the rollback removes only the clients_* and deals_* policies. It keeps archive protection, the audit
-- triggers and the restore path. This suite asserts exactly that, and asserts that the grants stay revoked.
-- The category-by-category comparison against the applied snapshot is done in run_local.sh (path F).

do $$
declare
  t text;
  v_fail text[] := '{}';
  v_priv text;
  v_trg text;
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
    -- Kept: authenticated keeps the four DML privileges that 0006b grants.
    foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if not has_table_privilege('authenticated', 'public.' || t, v_priv) then
        v_fail := array_append(v_fail, format('authenticated lost %s on %s', v_priv, t));
      end if;
    end loop;
    -- RLS stays enabled (the rollback deliberately keeps it on, so the missing policies fail closed).
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      v_fail := array_append(v_fail, format('RLS was disabled on %s', t));
    end if;
  end loop;

  -- Policies: the 0006b clients and deals policies are removed. The four companies_* policies from 0006 stay.
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename in ('clients', 'deals')) then
    v_fail := array_append(v_fail, 'clients or deals policies remain after the rollback');
  end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'companies') <> 4 then
    v_fail := array_append(v_fail, 'companies policies are not the four from 0006');
  end if;

  -- Kept (R2): archive protection and the audit trail. Each must be present after the rollback.
  foreach v_trg in array array['trg_archive_immutable', 'trg_guard_archive', 'trg_audit', 'trg_created_by', 'trg_updated'] loop
    foreach t in array array['companies', 'clients', 'deals'] loop
      if not exists (select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
                      where c.relname = t and tr.tgname = v_trg and not tr.tgisinternal) then
        v_fail := array_append(v_fail, format('trigger %s missing on %s after the rollback', v_trg, t));
      end if;
    end loop;
  end loop;
  if not exists (select 1 from pg_trigger tr join pg_class c on c.oid = tr.tgrelid
                  where c.relname = 'deals' and tr.tgname = 'trg_deal_status' and not tr.tgisinternal) then
    v_fail := array_append(v_fail, 'trg_deal_status missing on deals after the rollback');
  end if;
  foreach t in array array['guard_archive()', 'guard_archived_immutable()', 'sync_deal_status()'] loop
    if to_regprocedure('app_private.' || t) is null then
      v_fail := array_append(v_fail, format('app_private.%s missing after the rollback', t));
    end if;
  end loop;
  if to_regprocedure('public.restore_archived_record(text,uuid)') is null then
    v_fail := array_append(v_fail, 'public.restore_archived_record missing after the rollback');
  end if;
  if to_regclass('app_private.archive_restore_grant') is null then
    v_fail := array_append(v_fail, 'app_private.archive_restore_grant missing after the rollback');
  end if;
  -- The grant table stays unreachable for app roles.
  if has_table_privilege('authenticated', 'app_private.archive_restore_grant', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('anon', 'app_private.archive_restore_grant', 'SELECT,INSERT,UPDATE,DELETE') then
    v_fail := array_append(v_fail, 'an app role can reach app_private.archive_restore_grant');
  end if;

  if array_length(v_fail, 1) is not null then
    raise exception '0006b rollback asserts failed (%): %', array_length(v_fail, 1), array_to_string(v_fail, '; ');
  end if;
  raise notice '0006b rollback asserts passed (grants stay revoked; RLS policies for clients and deals removed; archive protection, audit and restore kept)';
end $$;
