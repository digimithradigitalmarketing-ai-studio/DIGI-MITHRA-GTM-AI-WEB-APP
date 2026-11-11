-- gtm_scope_rls.sql
-- Synthetic-only test for migrations 0002-0006. Two tenants (A, B), four workspaces
-- (A1, A2, B1, B2), six users.
--
-- Runner order, all inside ONE transaction that ends in ROLLBACK:
--   1. baseline snapshot of existing policies (set_config, see dry-run prelude)
--   2. migrations 0002 .. 0006
--   3. this file
--   4. ROLLBACK
-- Each check passes silently or raises. The final row appears only if every check passed.

-- ---------------------------------------------------------------- 1. fixtures
-- Table owner only, rolled back. Quota and seed triggers are paused so fixtures are
-- deterministic. Stage rows are inserted with fixed ids.
-- Pause only the triggers that exist in this database. The local replica omits the
-- quota and seed triggers (see tests/local/01_base_schema.sql), so they are skipped there.
do $$
declare t record;
begin
  for t in select tgname, tgrelid::regclass::text as tbl from pg_trigger
            where tgname in ('trg_seed', 'trg_quota') and not tgisinternal loop
    execute format('alter table %s disable trigger %I', t.tbl, t.tgname);
  end loop;
end $$;

insert into auth.users (id, aud, role) values
  ('a0000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated'),  -- owner A
  ('a0000000-0000-4000-8000-0000000000a2', 'authenticated', 'authenticated'),  -- editor in A1
  ('a0000000-0000-4000-8000-0000000000a3', 'authenticated', 'authenticated'),  -- manager in A2
  ('a0000000-0000-4000-8000-0000000000a4', 'authenticated', 'authenticated'),  -- viewer in A1
  ('b0000000-0000-4000-8000-0000000000b1', 'authenticated', 'authenticated'),  -- owner B
  ('b0000000-0000-4000-8000-0000000000b2', 'authenticated', 'authenticated');  -- editor in B1

insert into public.tenants (id, name, slug, kind, created_by) values
  ('a1000000-0000-4000-8000-00000000000a', 'GTM Test Tenant A', 'gtm-test-tenant-a', 'agency',
   'a0000000-0000-4000-8000-0000000000a1'),
  ('b1000000-0000-4000-8000-00000000000b', 'GTM Test Tenant B', 'gtm-test-tenant-b', 'agency',
   'b0000000-0000-4000-8000-0000000000b1');

insert into public.workspaces (id, tenant_id, name, slug) values
  ('a2000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a', 'A1', 'a1'),
  ('a2000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a', 'A2', 'a2'),
  ('b2000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-00000000000b', 'B1', 'b1'),
  ('b2000000-0000-4000-8000-0000000000b2', 'b1000000-0000-4000-8000-00000000000b', 'B2', 'b2');

insert into public.tenant_members (tenant_id, user_id, role) values
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-0000000000a1', 'owner'),
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-0000000000a2', 'analyst'),
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-0000000000a3', 'analyst'),
  ('a1000000-0000-4000-8000-00000000000a', 'a0000000-0000-4000-8000-0000000000a4', 'viewer'),
  ('b1000000-0000-4000-8000-00000000000b', 'b0000000-0000-4000-8000-0000000000b1', 'owner'),
  ('b1000000-0000-4000-8000-00000000000b', 'b0000000-0000-4000-8000-0000000000b2', 'analyst');

insert into public.workspace_members (tenant_id, workspace_id, user_id, role) values
  ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'a0000000-0000-4000-8000-0000000000a2', 'editor'),
  ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a2',
   'a0000000-0000-4000-8000-0000000000a3', 'manager'),
  ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
   'a0000000-0000-4000-8000-0000000000a4', 'viewer'),
  ('b1000000-0000-4000-8000-00000000000b', 'b2000000-0000-4000-8000-0000000000b1',
   'b0000000-0000-4000-8000-0000000000b2', 'editor');

do $$
declare t record;
begin
  for t in select tgname, tgrelid::regclass::text as tbl from pg_trigger
            where tgname in ('trg_seed', 'trg_quota') and not tgisinternal loop
    execute format('alter table %s enable trigger %I', t.tbl, t.tgname);
  end loop;
end $$;

insert into public.pipeline_stages (id, tenant_id, workspace_id, name, position, is_won, is_lost) values
  ('e1000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'New enquiry', 0, false, false),
  ('e1000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'Won', 4, true, false),
  ('e1000000-0000-4000-8000-0000000000a3', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a2', 'New enquiry', 0, false, false),
  ('e1000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-00000000000b',
   'b2000000-0000-4000-8000-0000000000b1', 'New enquiry', 0, false, false);

insert into public.contacts (id, tenant_id, workspace_id, name) values
  ('c2000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'Test Contact A1'),
  ('c2000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-00000000000b',
   'b2000000-0000-4000-8000-0000000000b1', 'Test Contact B1');

insert into public.campaigns (id, tenant_id, workspace_id, name) values
  ('c3000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a2', 'Test Campaign A2');

insert into public.landing_pages
  (id, tenant_id, workspace_id, slug, title, headline, cta_label, accent,
   form_fields, success_message, consent_text, bullets, status) values
  ('c5000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a2', 'gtm-test-lp-a2', 'Test LP', 'Test headline',
   'Book', '#f97316', '[]'::jsonb, 'Thanks', 'Test consent', '{}'::text[], 'draft');

insert into public.companies (id, tenant_id, workspace_id, name) values
  ('c1000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'Test Co A1'),
  ('c1000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a2', 'Test Co A2'),
  ('c1000000-0000-4000-8000-0000000000b1', 'b1000000-0000-4000-8000-00000000000b',
   'b2000000-0000-4000-8000-0000000000b1', 'Test Co B1');

insert into public.leads (id, tenant_id, workspace_id, title, stage_id, contact_id) values
  ('c4000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'Test Lead A1', 'e1000000-0000-4000-8000-0000000000a1',
   'c2000000-0000-4000-8000-0000000000a1'),
  ('c4000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a2', 'Test Lead A2', 'e1000000-0000-4000-8000-0000000000a3',
   null);

insert into public.deals (id, tenant_id, workspace_id, title, stage_id, company_id, contact_id, lead_id) values
  ('d1000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'Test Deal A1', 'e1000000-0000-4000-8000-0000000000a1',
   'c1000000-0000-4000-8000-0000000000a1', 'c2000000-0000-4000-8000-0000000000a1',
   'c4000000-0000-4000-8000-0000000000a1');

insert into public.clients (id, tenant_id, workspace_id, company_id, primary_contact_id, status) values
  ('c6000000-0000-4000-8000-0000000000a1', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-0000000000a1',
   'c2000000-0000-4000-8000-0000000000a1', 'active'),
  ('c6000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
   'a2000000-0000-4000-8000-0000000000a2', 'c1000000-0000-4000-8000-0000000000a2', null, 'active');

-- ---------------------------------------------------------------- 2. cross-scope references must fail
-- Runs as table owner, so RLS cannot hide a missing foreign key check.

-- A1: deal in A1 pointing at a company in tenant B
do $$ begin
  insert into public.deals (tenant_id, workspace_id, title, stage_id, company_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-0000000000b1');
  raise exception 'FAIL A1: deal accepted a company from another tenant';
exception when foreign_key_violation then null; end $$;

-- A2: deal in A1 pointing at a stage from workspace A2 (same tenant).
-- The sync_deal_status BEFORE trigger rejects this first (message 'deal stage ...').
-- The composite foreign key is the second guard. Either rejection is a pass.
do $$ begin
  insert into public.deals (tenant_id, workspace_id, title, stage_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000a3');
  raise exception 'FAIL A2: deal accepted a stage from another workspace';
exception
  when foreign_key_violation then null;
  when raise_exception then
    if sqlerrm not like 'deal stage%' then raise; end if;
end $$;

-- A3: deal in A1 pointing at a stage from tenant B (same two-layer guard as A2)
do $$ begin
  insert into public.deals (tenant_id, workspace_id, title, stage_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000b1');
  raise exception 'FAIL A3: deal accepted a stage from another tenant';
exception
  when foreign_key_violation then null;
  when raise_exception then
    if sqlerrm not like 'deal stage%' then raise; end if;
end $$;

-- A4: task in A1 pointing at a lead in A2
do $$ begin
  insert into public.tasks (tenant_id, workspace_id, title, lead_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'c4000000-0000-4000-8000-0000000000a2');
  raise exception 'FAIL A4: task accepted a lead from another workspace';
exception when foreign_key_violation then null; end $$;

-- A5: task in A1 pointing at a contact in tenant B
do $$ begin
  insert into public.tasks (tenant_id, workspace_id, title, contact_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'c2000000-0000-4000-8000-0000000000b1');
  raise exception 'FAIL A5: task accepted a contact from another tenant';
exception when foreign_key_violation then null; end $$;

-- A6: lead in A1 pointing at a campaign in A2
do $$ begin
  insert into public.leads (tenant_id, workspace_id, title, stage_id, campaign_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000a1', 'c3000000-0000-4000-8000-0000000000a2');
  raise exception 'FAIL A6: lead accepted a campaign from another workspace';
exception when foreign_key_violation then null; end $$;

-- A7: lead in A1 pointing at a landing page in A2
do $$ begin
  insert into public.leads (tenant_id, workspace_id, title, stage_id, landing_page_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000a1', 'c5000000-0000-4000-8000-0000000000a2');
  raise exception 'FAIL A7: lead accepted a landing page from another workspace';
exception when foreign_key_violation then null; end $$;

-- A8: contact in A1 pointing at a company in A2
do $$ begin
  insert into public.contacts (tenant_id, workspace_id, name, company_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'c1000000-0000-4000-8000-0000000000a2');
  raise exception 'FAIL A8: contact accepted a company from another workspace';
exception when foreign_key_violation then null; end $$;

-- A9: client in A1 pointing at a company in tenant B
do $$ begin
  insert into public.clients (tenant_id, workspace_id, company_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'c1000000-0000-4000-8000-0000000000b1');
  raise exception 'FAIL A9: client accepted a company from another tenant';
exception when foreign_key_violation then null; end $$;

-- A10: a second client for the same company is refused
do $$ begin
  insert into public.clients (tenant_id, workspace_id, company_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'c1000000-0000-4000-8000-0000000000a1');
  raise exception 'FAIL A10: duplicate client for one company accepted';
exception when unique_violation then null; end $$;

-- ---------------------------------------------------------------- 3. sales operator in A1 (editor)
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;

-- B1: positive, can create a company in A1
insert into public.companies (tenant_id, workspace_id, name)
values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'Sales Co A1');

-- B2: cannot create a company in A2 (no membership there)
do $$ begin
  insert into public.companies (tenant_id, workspace_id, name)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a2', 'x');
  raise exception 'FAIL B2: editor in A1 created a company in A2';
exception when insufficient_privilege then null; end $$;

-- B3: cannot read A2 companies
do $$ begin
  if (select count(*) from public.companies
      where workspace_id = 'a2000000-0000-4000-8000-0000000000a2') <> 0 then
    raise exception 'FAIL B3: editor in A1 can read A2 companies';
  end if;
end $$;

-- B4: positive, can edit a company in A1
do $$ declare v int; begin
  update public.companies set name = 'Test Co A1 renamed'
  where id = 'c1000000-0000-4000-8000-0000000000a1';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL B4: editor could not edit a company in A1'; end if;
end $$;

-- B5: cannot archive a company (guard trigger, admin only)
do $$ begin
  update public.companies set archived_at = now()
  where id = 'c1000000-0000-4000-8000-0000000000a1';
  raise exception 'FAIL B5: editor archived a company';
exception when insufficient_privilege then null; end $$;

-- B6: cannot hard-delete a company (no delete policy, zero rows)
do $$ declare v int; begin
  delete from public.companies where id = 'c1000000-0000-4000-8000-0000000000a1';
  get diagnostics v = row_count;
  if v <> 0 then raise exception 'FAIL B6: editor deleted a company'; end if;
end $$;

-- B7: positive, can create a deal in A1
insert into public.deals (id, tenant_id, workspace_id, title, stage_id, company_id, contact_id)
values ('d1000000-0000-4000-8000-0000000000a2', 'a1000000-0000-4000-8000-00000000000a',
        'a2000000-0000-4000-8000-0000000000a1', 'Sales Deal A1', 'e1000000-0000-4000-8000-0000000000a1',
        'c1000000-0000-4000-8000-0000000000a1', 'c2000000-0000-4000-8000-0000000000a1');

-- B8: moving the deal to Won sets status and closed_at
update public.deals set stage_id = 'e1000000-0000-4000-8000-0000000000a2'
where id = 'd1000000-0000-4000-8000-0000000000a2';
do $$ begin
  if not exists (select 1 from public.deals where id = 'd1000000-0000-4000-8000-0000000000a2'
                  and status = 'won' and closed_at is not null) then
    raise exception 'FAIL B8: moving to Won did not set status and closed_at';
  end if;
end $$;

-- B9: moving back to an open stage clears them
update public.deals set stage_id = 'e1000000-0000-4000-8000-0000000000a1'
where id = 'd1000000-0000-4000-8000-0000000000a2';
do $$ begin
  if not exists (select 1 from public.deals where id = 'd1000000-0000-4000-8000-0000000000a2'
                  and status = 'open' and closed_at is null) then
    raise exception 'FAIL B9: moving back to open did not clear status and closed_at';
  end if;
end $$;

-- B10: cannot archive a deal
do $$ begin
  update public.deals set archived_at = now() where id = 'd1000000-0000-4000-8000-0000000000a2';
  raise exception 'FAIL B10: editor archived a deal';
exception when insufficient_privilege then null; end $$;

-- B11: cannot create a client (admin only)
do $$ begin
  insert into public.clients (tenant_id, workspace_id, company_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'c1000000-0000-4000-8000-0000000000a1');
  raise exception 'FAIL B11: editor created a client';
exception when insufficient_privilege then null; end $$;

-- B12: can read clients in A1
do $$ begin
  if (select count(*) from public.clients
      where workspace_id = 'a2000000-0000-4000-8000-0000000000a1') <> 1 then
    raise exception 'FAIL B12: editor in A1 cannot read clients in A1';
  end if;
end $$;

-- B13: cannot edit a client (zero rows, RLS filters the row)
do $$ declare v int; begin
  update public.clients set status = 'paused' where id = 'c6000000-0000-4000-8000-0000000000a1';
  get diagnostics v = row_count;
  if v <> 0 then raise exception 'FAIL B13: editor edited a client'; end if;
end $$;

-- B14: cannot delete a client (zero rows)
do $$ declare v int; begin
  delete from public.clients where id = 'c6000000-0000-4000-8000-0000000000a1';
  get diagnostics v = row_count;
  if v <> 0 then raise exception 'FAIL B14: editor deleted a client'; end if;
end $$;

reset role;

-- ---------------------------------------------------------------- 4. viewer in A1 (read only)
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-0000000000a4","role":"authenticated"}', true);
set local role authenticated;

-- C1: cannot create a company
do $$ begin
  insert into public.companies (tenant_id, workspace_id, name)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'x');
  raise exception 'FAIL C1: viewer created a company';
exception when insufficient_privilege then null; end $$;

-- C2: cannot create a deal
do $$ begin
  insert into public.deals (tenant_id, workspace_id, title, stage_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000a1');
  raise exception 'FAIL C2: viewer created a deal';
exception when insufficient_privilege then null; end $$;

-- C3: can read companies in A1
do $$ begin
  if (select count(*) from public.companies
      where id = 'c1000000-0000-4000-8000-0000000000a2') <> 0 then
    raise exception 'FAIL C3: viewer in A1 can read a company in A2';
  end if;
  if (select count(*) from public.companies
      where workspace_id = 'a2000000-0000-4000-8000-0000000000a1') < 1 then
    raise exception 'FAIL C3b: viewer in A1 cannot read companies in A1';
  end if;
end $$;

reset role;

-- ---------------------------------------------------------------- 5. manager in A2 (sales, other workspace)
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
set local role authenticated;

-- D1: positive, can edit a company in A2
do $$ declare v int; begin
  update public.companies set lifecycle = 'customer'
  where id = 'c1000000-0000-4000-8000-0000000000a2';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL D1: manager could not edit a company in A2'; end if;
end $$;

-- D2: cannot see A1 companies, even inside the same tenant
do $$ begin
  if (select count(*) from public.companies
      where id = 'c1000000-0000-4000-8000-0000000000a1') <> 0 then
    raise exception 'FAIL D2: manager in A2 can read a company in A1';
  end if;
end $$;

-- D3: cannot see A1 deals
do $$ begin
  if (select count(*) from public.deals
      where workspace_id = 'a2000000-0000-4000-8000-0000000000a1') <> 0 then
    raise exception 'FAIL D3: manager in A2 can read deals in A1';
  end if;
end $$;

-- D4: cannot archive a company
do $$ begin
  update public.companies set archived_at = now() where id = 'c1000000-0000-4000-8000-0000000000a2';
  raise exception 'FAIL D4: manager archived a company';
exception when insufficient_privilege then null; end $$;

reset role;

-- ---------------------------------------------------------------- 6. owner A (admin, tenant-wide)
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;

-- E1: positive, admin creates a company in A2
insert into public.companies (tenant_id, workspace_id, name)
values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a2', 'Owner Co A2');

-- E2: positive, admin archives a company, and archived_by is set to the admin
do $$ declare v int; begin
  update public.companies set archived_at = now() where id = 'c1000000-0000-4000-8000-0000000000a1';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL E2: admin could not archive a company'; end if;
  if not exists (select 1 from public.companies
                  where id = 'c1000000-0000-4000-8000-0000000000a1'
                    and archived_by = 'a0000000-0000-4000-8000-0000000000a1') then
    raise exception 'FAIL E2b: archived_by was not recorded';
  end if;
end $$;

-- E3: positive, admin restores the company through restore_archived_record (R1: the only restore path), and
-- archived_by is cleared. A direct update that clears archived_at is refused (see 39_f2 section 5).
do $$ begin
  perform public.restore_archived_record('companies', 'c1000000-0000-4000-8000-0000000000a1');
  if (select archived_at from public.companies where id = 'c1000000-0000-4000-8000-0000000000a1') is not null then
    raise exception 'FAIL E3: admin could not restore a company';
  end if;
  if exists (select 1 from public.companies
              where id = 'c1000000-0000-4000-8000-0000000000a1' and archived_by is not null) then
    raise exception 'FAIL E3b: archived_by not cleared on restore';
  end if;
end $$;

-- E4: positive, admin archives a client
do $$ declare v int; begin
  update public.clients set archived_at = now() where id = 'c6000000-0000-4000-8000-0000000000a1';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL E4: admin could not archive a client'; end if;
end $$;

-- E5: hard delete of a company that still has history is refused (deal and client depend on it)
do $$ begin
  delete from public.companies where id = 'c1000000-0000-4000-8000-0000000000a1';
  raise exception 'FAIL E5: admin hard-deleted a company with history';
exception when foreign_key_violation then null; end $$;

-- E6: positive, admin hard-deletes a company with no history
do $$ declare v int; begin
  insert into public.companies (id, tenant_id, workspace_id, name)
  values ('c1000000-0000-4000-8000-0000000000d1', 'a1000000-0000-4000-8000-00000000000a',
          'a2000000-0000-4000-8000-0000000000a1', 'Scratch Co');
  delete from public.companies where id = 'c1000000-0000-4000-8000-0000000000d1';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL E6: admin could not delete an unused company'; end if;
end $$;

-- E7: positive, admin edits a client
do $$ declare v int; begin
  update public.clients set status = 'active' where id = 'c6000000-0000-4000-8000-0000000000a2';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL E7: admin could not edit a client'; end if;
end $$;

-- E8: positive, admin deletes a client
do $$ declare v int; begin
  delete from public.clients where id = 'c6000000-0000-4000-8000-0000000000a2';
  get diagnostics v = row_count;
  if v <> 1 then raise exception 'FAIL E8: admin could not delete a client'; end if;
end $$;

-- E9: owner A cannot see tenant B
do $$ begin
  if (select count(*) from public.companies
      where tenant_id = 'b1000000-0000-4000-8000-00000000000b') <> 0 then
    raise exception 'FAIL E9: tenant A admin can read tenant B companies';
  end if;
end $$;

reset role;

-- ---------------------------------------------------------------- 7. owner B (tenant B)
select set_config('request.jwt.claims',
  '{"sub":"b0000000-0000-4000-8000-0000000000b1","role":"authenticated"}', true);
set local role authenticated;

-- F1: cannot create a company in tenant A
do $$ begin
  insert into public.companies (tenant_id, workspace_id, name)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1', 'x');
  raise exception 'FAIL F1: tenant B admin created a company in tenant A';
exception when insufficient_privilege then null; end $$;

-- F2: cannot read tenant A companies
do $$ begin
  if (select count(*) from public.companies where tenant_id = 'a1000000-0000-4000-8000-00000000000a') <> 0 then
    raise exception 'FAIL F2: tenant B admin can read tenant A companies';
  end if;
end $$;

-- F3: positive, can create a company in its own tenant
insert into public.companies (tenant_id, workspace_id, name)
values ('b1000000-0000-4000-8000-00000000000b', 'b2000000-0000-4000-8000-0000000000b2', 'Owner Co B2');

reset role;

-- ---------------------------------------------------------------- 8. anon (signed out)
set local role anon;

-- G1: anon cannot read the new tables
do $$ begin
  perform 1 from public.companies;
  raise exception 'FAIL G1: anon reached companies';
exception when insufficient_privilege then null; end $$;

-- G2: anon cannot write
do $$ begin
  insert into public.deals (tenant_id, workspace_id, title, stage_id)
  values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
          'x', 'e1000000-0000-4000-8000-0000000000a1');
  raise exception 'FAIL G2: anon wrote a deal';
exception when insufficient_privilege then null; end $$;

reset role;

-- ---------------------------------------------------------------- 9. existing modules and history
-- H1: smoke test. Sales in A1 can still create lead, task and activity rows.
select set_config('request.jwt.claims',
  '{"sub":"a0000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
set local role authenticated;

insert into public.leads (id, tenant_id, workspace_id, title, stage_id)
values ('c4000000-0000-4000-8000-0000000000a3', 'a1000000-0000-4000-8000-00000000000a',
        'a2000000-0000-4000-8000-0000000000a1', 'Smoke lead', 'e1000000-0000-4000-8000-0000000000a1');
insert into public.tasks (tenant_id, workspace_id, title, lead_id)
values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
        'Smoke task', 'c4000000-0000-4000-8000-0000000000a3');
insert into public.activities (tenant_id, workspace_id, lead_id, kind, body)
values ('a1000000-0000-4000-8000-00000000000a', 'a2000000-0000-4000-8000-0000000000a1',
        'c4000000-0000-4000-8000-0000000000a3', 'note', 'Smoke activity');

reset role;

-- H2: audit rows are written for the new tables
do $$ begin
  if not exists (select 1 from public.audit_logs
                  where entity = 'companies' and tenant_id = 'a1000000-0000-4000-8000-00000000000a') then
    raise exception 'FAIL H2: no audit rows for companies';
  end if;
end $$;

-- H3: existing RLS policies are byte-identical to the baseline taken before migration.
-- The workflow engine and notification tables are excluded: 0007a records their live policies
-- for the first time, so they are not part of the pre-GTM baseline. Their own suite is 40_*.
do $$ declare v text; begin
  select md5(coalesce(string_agg(
    tablename || '|' || policyname || '|' || cmd || '|' || roles::text || '|' ||
    coalesce(qual, '') || '|' || coalesce(with_check, ''), E'\n' order by tablename, policyname), ''))
    into v
    from pg_policies
   where schemaname = 'public'
     and tablename not in ('companies', 'clients', 'deals',
                           'workflows', 'workflow_versions', 'workflow_runs', 'workflow_steps', 'notifications');
  if v <> current_setting('gtm.baseline_policy_md5') then
    raise exception 'FAIL H3: existing RLS policies changed';
  end if;
end $$;

select 'all GTM scope and RLS checks passed' as result;
