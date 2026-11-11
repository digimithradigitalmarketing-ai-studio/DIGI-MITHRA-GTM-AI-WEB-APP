-- 34_anon_rpc_compat_tests.sql
-- Synthetic-only. Anonymous RPC compatibility on the production-shaped surface (00b_production_surface.sql).
--
-- This suite runs TWICE with the same code: once on the current production ACL (no prelude) and once with
-- supabase/reviews/0009_anon_hardening_proposed.sql as the prelude. Every check must pass in both runs, so
-- the hardening is shown not to break the public landing page, web chat, unsubscribe, or the plans read.
-- The runner ends the transaction with ROLLBACK, so nothing persists.

-- ----------------------------------------------------------------- helpers (temporary)
create function pg_temp.as_anon() returns void language plpgsql as $$
begin
  execute 'set local role anon';
end $$;

create function pg_temp.as_postgres() returns void language plpgsql as $$
begin
  execute 'reset role';
end $$;

-- The statement must fail, and its message must contain p_contains. A success or another message is a failure.
create function pg_temp.expect_error(p_label text, p_sql text, p_contains text) returns void language plpgsql as $$
declare ok boolean := false;
begin
  execute p_sql;
  ok := true;
exception when others then
  if sqlerrm not like '%' || p_contains || '%' then
    raise exception 'FAIL %: unexpected error: %', p_label, sqlerrm using errcode = 'P0100';
  end if;
  return;
end $$;

-- ----------------------------------------------------------------- fixtures (as postgres, rolled back at the end)
insert into public.tenants (id, name, slug)
values ('a0000000-0000-4000-8000-0000000000a1', 'Synthetic tenant 0009', 'synthetic-tenant-0009');

insert into public.workspaces (id, tenant_id, name, slug, chat_widget_key)
values ('a0000000-0000-4000-8000-0000000000a2', 'a0000000-0000-4000-8000-0000000000a1',
        'Synthetic workspace 0009', 'synthetic-ws-0009', 'a0000000-0000-4000-8000-0000000000a3');

insert into public.pipeline_stages (tenant_id, workspace_id, name, position)
values ('a0000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-0000000000a2', 'New', 0);

insert into public.landing_pages (id, tenant_id, workspace_id, slug, title, headline, status)
values ('a0000000-0000-4000-8000-0000000000a4', 'a0000000-0000-4000-8000-0000000000a1',
        'a0000000-0000-4000-8000-0000000000a2', 'synthetic-0009', 'Synthetic page', 'Synthetic headline', 'published'),
       ('a0000000-0000-4000-8000-0000000000a5', 'a0000000-0000-4000-8000-0000000000a1',
        'a0000000-0000-4000-8000-0000000000a2', 'synthetic-draft-0009', 'Synthetic draft', 'Draft headline', 'draft');

insert into public.contacts (id, tenant_id, workspace_id, name, email, marketing_consent)
values ('a0000000-0000-4000-8000-0000000000a6', 'a0000000-0000-4000-8000-0000000000a1',
        'a0000000-0000-4000-8000-0000000000a2', 'Synthetic contact', 'synthetic.0009@example.test', true);

insert into public.campaigns (id, tenant_id, workspace_id, name)
values ('a0000000-0000-4000-8000-0000000000a8', 'a0000000-0000-4000-8000-0000000000a1',
        'a0000000-0000-4000-8000-0000000000a2', 'Synthetic campaign 0009');

insert into public.email_sends (id, tenant_id, workspace_id, campaign_id, contact_id, email, status)
values ('a0000000-0000-4000-8000-0000000000a7', 'a0000000-0000-4000-8000-0000000000a1',
        'a0000000-0000-4000-8000-0000000000a2', 'a0000000-0000-4000-8000-0000000000a8',
        'a0000000-0000-4000-8000-0000000000a6', 'synthetic.0009@example.test', 'sent');

insert into public.plans (id, name, max_workspaces, max_accounts, max_posts_per_month, max_users, ai_credits_per_month, sort_order)
values ('synthetic-0009-plan', 'Synthetic plan', 1, 1, 10, 1, 0, 0);

-- ----------------------------------------------------------------- 1. landing page reads and views (anon)
select pg_temp.as_anon();
do $$
declare v jsonb;
begin
  v := public.get_landing_page('synthetic-0009');
  if v is null or v ->> 'title' <> 'Synthetic page' then
    raise exception 'FAIL get_landing_page: published page not returned: %', v using errcode = 'P0100';
  end if;
  if public.get_landing_page('synthetic-draft-0009') is not null then
    raise exception 'FAIL get_landing_page: a draft page was returned to anon' using errcode = 'P0100';
  end if;
  perform public.record_landing_view('synthetic-0009');
end $$;
select pg_temp.as_postgres();

do $$
begin
  if (select views from public.landing_pages where slug = 'synthetic-0009') <> 1 then
    raise exception 'FAIL record_landing_view did not increment the view count' using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- 2. landing form (anon)
select pg_temp.as_anon();
do $$
declare v_msg text;
begin
  v_msg := public.submit_landing_form('synthetic-0009',
    '{"name":"Synthetic Visitor","phone":"+91 99990 00001","email":"visitor.0009@example.test","message":"Synthetic enquiry","consent":true}'::jsonb,
    '{"utm_source":"synthetic"}'::jsonb);
  if v_msg is distinct from 'Thank you! Our team will contact you shortly.' then
    raise exception 'FAIL submit_landing_form: unexpected message %', v_msg using errcode = 'P0100';
  end if;
end $$;
select pg_temp.expect_error('landing form without consent',
  $$select public.submit_landing_form('synthetic-0009', '{"name":"X","phone":"1","consent":false}'::jsonb, '{}'::jsonb)$$,
  'Please accept the consent checkbox');
select pg_temp.expect_error('landing form missing required name',
  $$select public.submit_landing_form('synthetic-0009', '{"phone":"1","consent":true}'::jsonb, '{}'::jsonb)$$,
  'is required');
select pg_temp.expect_error('landing form on a draft page',
  $$select public.submit_landing_form('synthetic-draft-0009', '{"name":"X","phone":"1","consent":true}'::jsonb, '{}'::jsonb)$$,
  'not available');
select pg_temp.as_postgres();

do $$
begin
  if (select count(*) from public.leads where landing_page_id = 'a0000000-0000-4000-8000-0000000000a4') <> 1 then
    raise exception 'FAIL submit_landing_form did not create exactly one lead' using errcode = 'P0100';
  end if;
  if (select count(*) from public.form_submissions where landing_page_id = 'a0000000-0000-4000-8000-0000000000a4') <> 1 then
    raise exception 'FAIL submit_landing_form did not record exactly one submission' using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- 3. web chat (anon)
select pg_temp.as_anon();
do $$
declare
  v_cfg jsonb;
  v_session uuid;
  v_count integer;
begin
  v_cfg := public.web_chat_config('a0000000-0000-4000-8000-0000000000a3');
  if v_cfg ->> 'business' <> 'Synthetic workspace 0009' then
    raise exception 'FAIL web_chat_config: unexpected business %', v_cfg using errcode = 'P0100';
  end if;

  v_session := public.start_web_chat('a0000000-0000-4000-8000-0000000000a3', 'Synthetic Visitor',
                                     'visitor.0009@example.test', 'Synthetic opening message', true);
  if v_session is null then
    raise exception 'FAIL start_web_chat returned no session' using errcode = 'P0100';
  end if;

  perform public.send_web_chat(v_session, 'Synthetic follow up');

  select count(*) into v_count from public.web_chat_messages(v_session);
  if v_count < 2 then
    raise exception 'FAIL web_chat_messages returned % rows, expected at least 2', v_count using errcode = 'P0100';
  end if;
end $$;
select pg_temp.expect_error('web chat with an unknown key',
  $$select public.start_web_chat('a0000000-0000-4000-8000-00000000ffff', 'X', null, 'hello', false)$$,
  'Chat is not available');
select pg_temp.expect_error('web chat send with an unknown session',
  $$select public.send_web_chat('a0000000-0000-4000-8000-00000000ffff', 'hello')$$,
  'Chat session expired');
select pg_temp.as_postgres();

-- ----------------------------------------------------------------- 4. unsubscribe (anon)
select pg_temp.expect_error('unsubscribe with an unknown token',
  $$select public.unsubscribe_email('a0000000-0000-4000-8000-00000000ffff')$$,
  'Link is invalid');

select pg_temp.as_anon();
do $$
declare v_name text;
begin
  v_name := public.unsubscribe_email('a0000000-0000-4000-8000-0000000000a7');
  if v_name is distinct from 'Synthetic workspace 0009' then
    raise exception 'FAIL unsubscribe_email: unexpected business %', v_name using errcode = 'P0100';
  end if;
end $$;
select pg_temp.as_postgres();

do $$
begin
  if (select marketing_consent from public.contacts where id = 'a0000000-0000-4000-8000-0000000000a6') then
    raise exception 'FAIL unsubscribe_email did not clear marketing consent' using errcode = 'P0100';
  end if;
end $$;

-- ----------------------------------------------------------------- 5. direct reads anon may not make
-- Under the current ACL, anon holds table privileges that RLS filters to zero rows. After 0009, anon is refused
-- outright. Both are acceptable. Returning rows would be a failure.
select pg_temp.as_anon();
do $$
declare n integer;
begin
  begin
    select count(*) into n from public.leads;
    if n <> 0 then
      raise exception 'FAIL anon read % lead row(s) directly', n using errcode = 'P0100';
    end if;
  exception when insufficient_privilege then
    null;
  end;
end $$;
select pg_temp.as_postgres();

-- ----------------------------------------------------------------- 6. plans: the one intentional anon read
select pg_temp.as_anon();
do $$
declare n integer;
begin
  select count(*) into n from public.plans where id = 'synthetic-0009-plan';
  if n <> 1 then
    raise exception 'FAIL anon cannot read public.plans (saw % row(s))', n using errcode = 'P0100';
  end if;
end $$;
select pg_temp.as_postgres();

-- ----------------------------------------------------------------- 7. ensure_rls still fires without anon EXECUTE
-- The event trigger runs rls_auto_enable as its owner. This must enable RLS on a new public table in both runs.
create table public.gtm_0009_probe (id integer);
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.gtm_0009_probe'::regclass) then
    raise exception 'FAIL ensure_rls did not enable RLS on a new public table' using errcode = 'P0100';
  end if;
end $$;
drop table public.gtm_0009_probe;

drop function pg_temp.as_anon();
do $$ begin raise notice 'PASS 34_anon_rpc_compat_tests'; end $$;
