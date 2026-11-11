-- 0005_verify_only.sql
-- VERIFY ONLY. Read-only: every statement is a catalog read inside a DO block, so nothing is created, altered,
-- granted or recorded. It raises an exception naming every mismatch. It never writes to supabase_migrations.
--
-- Purpose: confirm that production already has what repo migration 0005_gtm_company_links.sql would create, so the
-- migration must NOT be replayed (its ADD COLUMN would fail, and the history must not be fabricated).
-- Expected result on production (checked 2026-11-11): every check passes.
--
-- Run with: psql -X -v ON_ERROR_STOP=1 -f 0005_verify_only.sql   (read-only role is sufficient)

do $$
declare
  v_fail text[] := '{}';
  v_col record;
  v_con record;
  v_idx record;
begin
  -- 1. Columns: nullable uuid on contacts and leads (no default, no NOT NULL).
  for v_col in
    select t.tbl, c.is_nullable, c.data_type, c.column_default
      from (values ('contacts'), ('leads')) as t(tbl)
      left join information_schema.columns c
        on c.table_schema = 'public' and c.table_name = t.tbl and c.column_name = 'company_id'
  loop
    if v_col.is_nullable is null then
      v_fail := array_append(v_fail, format('%s.company_id is missing', v_col.tbl));
    else
      if v_col.is_nullable <> 'YES' then v_fail := array_append(v_fail, format('%s.company_id is NOT NULL', v_col.tbl)); end if;
      if v_col.data_type <> 'uuid' then v_fail := array_append(v_fail, format('%s.company_id type is %s', v_col.tbl, v_col.data_type)); end if;
      if v_col.column_default is not null then v_fail := array_append(v_fail, format('%s.company_id has a default', v_col.tbl)); end if;
    end if;
  end loop;

  -- 2. Scoped foreign keys: (tenant_id, workspace_id, company_id) -> companies (tenant_id, workspace_id, id),
  --    ON DELETE SET NULL (company_id) only, validated.
  for v_con in
    select cn.conname, cn.conrelid, cn.convalidated, cn.confdeltype, cn.confdelsetcols, cn.conkey, cn.confkey,
           cl.relname as child, rl.relname as parent
      from pg_constraint cn
      join pg_class cl on cl.oid = cn.conrelid
      join pg_namespace n on n.oid = cl.relnamespace
      join pg_class rl on rl.oid = cn.confrelid
     where n.nspname = 'public' and cn.contype = 'f'
       and cn.conname in ('contacts_scope_company_fkey', 'leads_scope_company_fkey')
  loop
    if not v_con.convalidated then v_fail := array_append(v_fail, format('%s is not validated', v_con.conname)); end if;
    if v_con.parent <> 'companies' then v_fail := array_append(v_fail, format('%s references %s, not companies', v_con.conname, v_con.parent)); end if;
    if v_con.confdeltype <> 'n' then v_fail := array_append(v_fail, format('%s ON DELETE is not SET NULL', v_con.conname)); end if;
    if v_con.confdelsetcols is null or array_length(v_con.confdelsetcols, 1) <> 1 then
      v_fail := array_append(v_fail, format('%s ON DELETE SET NULL is not limited to company_id', v_con.conname));
    else
      if (select attname from pg_attribute where attrelid = (select oid from pg_class where relname = v_con.child and relnamespace = 'public'::regnamespace) and attnum = v_con.confdelsetcols[1]) <> 'company_id' then
        v_fail := array_append(v_fail, format('%s ON DELETE SET NULL names a column other than company_id', v_con.conname));
      end if;
    end if;
    if (select string_agg(attname, ',' order by attnum) from pg_attribute
         where attrelid = v_con.conrelid and attnum = any(v_con.conkey)) <> 'tenant_id,workspace_id,company_id' then
      v_fail := array_append(v_fail, format('%s child columns are not (tenant_id, workspace_id, company_id)', v_con.conname));
    end if;
  end loop;
  if (select count(*) from pg_constraint where conname in ('contacts_scope_company_fkey', 'leads_scope_company_fkey')) <> 2 then
    v_fail := array_append(v_fail, 'one or both scoped company foreign keys are missing');
  end if;

  -- 3. Partial indexes, with their exact definitions.
  for v_idx in
    select indexname, indexdef from pg_indexes
     where schemaname = 'public' and indexname in ('contacts_scope_company_idx', 'leads_scope_company_idx')
  loop
    if v_idx.indexdef not like '%(tenant_id, workspace_id, company_id)%' or v_idx.indexdef not like '%WHERE (company_id IS NOT NULL)%' then
      v_fail := array_append(v_fail, format('index %s definition differs from 0005', v_idx.indexname));
    end if;
  end loop;
  if (select count(*) from pg_indexes where schemaname = 'public'
        and indexname in ('contacts_scope_company_idx', 'leads_scope_company_idx')) <> 2 then
    v_fail := array_append(v_fail, 'one or both company indexes are missing');
  end if;

  -- 4. The parent unique key that the scoped foreign keys depend on (from 0002).
  if not exists (select 1 from pg_constraint
                  where conrelid = 'public.companies'::regclass and contype = 'u'
                    and pg_get_constraintdef(oid) = 'UNIQUE (tenant_id, workspace_id, id)') then
    v_fail := array_append(v_fail, 'companies (tenant_id, workspace_id, id) unique key is missing');
  end if;

  if array_length(v_fail, 1) is not null then
    raise exception '0005 verify-only failed (%): %', array_length(v_fail, 1), array_to_string(v_fail, '; ');
  end if;
  raise notice '0005 verify-only passed: company_id columns, scoped FKs, indexes and parent key match migration 0005';
end $$;
