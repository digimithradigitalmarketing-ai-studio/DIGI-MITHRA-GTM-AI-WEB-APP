-- 0009_anon_hardening_rollback.sql
-- Rolls back 0009_anon_hardening_proposed.sql, selectively. It does NOT restore the blanket grant that the
-- earlier draft used (grant all on every table to anon). It restores only what the caller asks for, and only
-- what app_private.gtm_0009_anon_baseline recorded before the hardening ran.
--
-- Inputs, set in the same transaction before this script runs:
--   select set_config('gtm.restore_anon_tables', 'public.leads,public.landing_pages', true);
--   select set_config('gtm.restore_anon_privileges', 'SELECT', true);
-- Both default to empty, and empty restores NOTHING.
--
-- Hard limits, enforced below:
--   * Only SELECT, INSERT, UPDATE and DELETE can be restored. TRUNCATE, REFERENCES, TRIGGER and MAINTAIN are
--     refused: they are the privileges that bypass or sidestep RLS, and no caller of the public Data API needs them.
--   * Only tables recorded as anon-held in the baseline can be restored. Anything else is refused.
--   * The default privileges (postgres, supabase_admin) are NOT restored. Restoring them re-opens every future table.
--   * EXECUTE on rls_auto_enable is NOT restored to PUBLIC or anon. The ensure_rls trigger does not need it.
--
-- Apply inside one transaction (psql -1). It holds no begin or commit itself.

do $$
declare
  v_tables text := coalesce(nullif(current_setting('gtm.restore_anon_tables', true), ''), '');
  v_privs  text := coalesce(nullif(current_setting('gtm.restore_anon_privileges', true), ''), '');
  v_table  text;
  v_priv   text;
  v_rec    record;
  v_n      integer := 0;
begin
  if to_regclass('app_private.gtm_0009_anon_baseline') is null then
    raise exception 'no baseline recorded: run 0009_anon_hardening_proposed.sql first';
  end if;

  if v_tables = '' then
    raise notice 'gtm.restore_anon_tables is empty: nothing restored';
    return;
  end if;
  if v_privs = '' then
    raise exception 'gtm.restore_anon_privileges is empty: name the privileges to restore (SELECT, INSERT, UPDATE, DELETE)';
  end if;

  -- Validate the privilege list first. Anything outside the allow-list fails the whole rollback.
  foreach v_priv in array string_to_array(upper(replace(v_privs, ' ', '')), ',') loop
    if v_priv not in ('SELECT', 'INSERT', 'UPDATE', 'DELETE') then
      raise exception 'privilege % may not be restored by this script', v_priv;
    end if;
  end loop;

  foreach v_table in array string_to_array(replace(v_tables, ' ', ''), ',') loop
    if not exists (
      select 1 from app_private.gtm_0009_anon_baseline b
       where b.kind = 'table' and b.grantee = 'anon' and b.object = v_table
    ) then
      raise exception '% was not recorded as anon-held in the baseline: refusing', v_table;
    end if;

    foreach v_priv in array string_to_array(upper(replace(v_privs, ' ', '')), ',') loop
      select * into v_rec
        from app_private.gtm_0009_anon_baseline b
       where b.kind = 'table' and b.grantee = 'anon' and b.object = v_table and b.privilege = v_priv;
      if found then
        if v_rec.is_grantable then
          raise exception 'baseline shows % on % is grantable; refusing to restore with grant option', v_priv, v_table;
        end if;
        execute format('grant %s on table %s to anon', v_priv, v_table);
        v_n := v_n + 1;
      else
        raise notice 'baseline did not record % on %: not restored', v_priv, v_table;
      end if;
    end loop;
  end loop;

  raise notice 'restored % anon table grant(s) on: %', v_n, v_tables;
end $$;

-- Optional, after every restore decision is final and recorded elsewhere. Not run by default.
-- drop table app_private.gtm_0009_anon_baseline;
