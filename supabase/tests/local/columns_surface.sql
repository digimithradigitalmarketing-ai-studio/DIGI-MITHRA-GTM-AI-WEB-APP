select 'columns|'||table_name||'|'||count(*)||'|'||md5(string_agg(column_name||' '||data_type||' '||is_nullable||' '||coalesce(column_default,''), E'\n' order by column_name collate "C")) 
  from information_schema.columns
 where table_schema='public' and table_name in ('consent_records','contacts','conversations','email_sends','form_submissions','landing_pages','leads','messages','pipeline_stages','workspaces','notifications','plans')
 group by table_name order by table_name collate "C";
