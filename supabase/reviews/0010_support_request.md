# Supabase Support request: supabase_admin default privileges on public tables

Project: `siyxkombexmowlggxlrb`
Status: draft for the owner to send. Nothing in this repository changes the supabase_admin defaults.

## Problem

New tables created in schema `public` by the `supabase_admin` role inherit default table privileges that
grant the `anon` and `authenticated` roles more than the application needs. Read-only inspection of
`pg_default_acl` on the project shows the `supabase_admin` default for `public` tables includes privileges for
`anon`. Only `supabase_admin`, or a role that can `SET ROLE` to it, can change that default, so the project
owner cannot change it from the SQL editor.

The `postgres` role's default ACL for `public` was reviewed separately and is corrected by migration
`0010_gtm_least_privilege_proposed.sql` (TRUNCATE) and `0009_anon_hardening_proposed.sql` (all privileges for
`anon`). Those are not affected by this request.

The concrete exposure: `TRUNCATE` is not filtered by row-level security. A table created in `public` with a
`supabase_admin` default can therefore be truncated by `anon` or `authenticated` over a direct database
connection, even when RLS policies restrict every row.

## Requested change

Please run, as `supabase_admin` (or confirm the correct way for the project owner to run it):

```sql
alter default privileges for role supabase_admin in schema public revoke truncate on tables from anon, authenticated;
```

If the owner also wants the `anon` default removed entirely, the statement is:

```sql
alter default privileges for role supabase_admin in schema public revoke all on tables from anon;
```

## Questions for Support

1. Confirm the current contents of `pg_default_acl` for `supabase_admin` in schema `public`, `defaclobjtype = 'r'`.
2. Confirm that changing this default does not change any existing table's ACL (it should affect only tables
   created afterwards).
3. Confirm whether the Supabase platform recreates or reapplies this default during maintenance or upgrades.
4. Confirm whether any Supabase-managed feature depends on `anon` or `authenticated` holding `TRUNCATE` on new
   `public` tables. The expected answer is no, but the project should not rely on that assumption.

## What this repository has already verified

- No SQL function in production `public` or `app_private` uses `TRUNCATE` (read-only check).
- The only `TRUNCATE` trigger is `cron.job`'s `cron_job_cache_invalidate`, in the `cron` schema.
- `postgres` is not a superuser and is not a member of `supabase_admin`.
- The replica test `supabase/tests/local/36_least_privilege_tests.sql` checks the default ACL with a probe table.
