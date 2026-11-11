with items as (
  select 'policy' as cat, tablename||'|'||policyname||'|'||cmd||'|'||permissive||'|'||roles::text||'|'||coalesce(qual,'')||'|'||coalesce(with_check,'') as item
    from pg_policies where schemaname='public' and tablename in ('consent_records','contacts','conversations','email_sends','form_submissions','landing_pages','leads','messages','pipeline_stages','workspaces')
  union all
  select 'grant', c.relname||'|'||case when a.grantee=0 then 'PUBLIC' else a.grantee::regrole::text end||'|'||a.privilege_type
    from pg_class c join lateral aclexplode(c.relacl) a on true
   where c.relnamespace='public'::regnamespace and c.relname in ('consent_records','contacts','conversations','email_sends','form_submissions','landing_pages','leads','messages','pipeline_stages','workspaces')
  union all
  select 'fn', p.pronamespace::regnamespace::text||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')|res='||pg_get_function_result(p.oid)||'|definer='||p.prosecdef::text||'|vol='||p.provolatile::text||'|cfg='||coalesce(array_to_string(p.proconfig,','),'')||'|src='||md5(regexp_replace(p.prosrc,'\s+',' ','g'))
    from pg_proc p where p.proname in ('get_landing_page','record_landing_view','submit_landing_form','start_web_chat','send_web_chat','web_chat_config','web_chat_messages','unsubscribe_email','rls_auto_enable','notify_workspace')
  union all
  select 'fnacl', p.proname||'|'||coalesce((select string_agg(case when a.grantee=0 then 'PUBLIC' else a.grantee::regrole::text end||':'||a.privilege_type, ',' order by (case when a.grantee=0 then 'PUBLIC' else a.grantee::regrole::text end) collate "C", a.privilege_type) from aclexplode(p.proacl) a),'')
    from pg_proc p where p.proname in ('get_landing_page','record_landing_view','submit_landing_form','start_web_chat','send_web_chat','web_chat_config','web_chat_messages','unsubscribe_email','rls_auto_enable','notify_workspace')
)
select 'fingerprint|'||cat||'|'||count(*)||'|'||md5(string_agg(item, E'\n' order by item collate "C")) from items group by cat order by cat;
