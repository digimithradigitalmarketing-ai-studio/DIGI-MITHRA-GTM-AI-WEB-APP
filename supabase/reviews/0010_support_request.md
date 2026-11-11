# Supabase Support request: supabase_admin default privileges in schema public

Project: `siyxkombexmowlggxlrb`
Status: ready for the project owner to send. Nothing in this repository changes the supabase_admin defaults.
Read-only evidence gathered 2026-11-11.

## What we observed

Default privileges are the rules that decide what a newly created object gets. Production has these defaults in schema `public`:

| Defining role | Object type | anon | authenticated | service_role |
| --- | --- | --- | --- | --- |
| `postgres` | tables (`r`) | all 8 table privileges (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN) | all 8 | all 8 |
| `supabase_admin` | tables (`r`) | all 8 table privileges | all 8 | all 8 |
| `postgres` | functions (`f`) | EXECUTE | EXECUTE | EXECUTE |
| `supabase_admin` | functions (`f`) | EXECUTE | EXECUTE | EXECUTE |
| `postgres` | sequences (`S`) | SELECT, UPDATE, USAGE | SELECT, UPDATE, USAGE | SELECT, UPDATE, USAGE |
| `supabase_admin` | sequences (`S`) | SELECT, UPDATE, USAGE | SELECT, UPDATE, USAGE | SELECT, UPDATE, USAGE |

Effect on the 56 existing public tables: anon and authenticated each hold all 8 table privileges on every one of them.
PUBLIC holds no table privilege.

## Why it matters

`TRUNCATE` is not filtered by row-level security. A signed-in or anonymous role with `TRUNCATE` on a table can empty it
over a direct database connection, even when every row policy denies access. `anon` can also execute every new public function
by default, and it holds write privileges on new tables by default.

## What this project already fixes itself

The `postgres` defaults are changed by migrations this project owns:

- `reviews/0009_anon_hardening_proposed.sql` revokes ALL on tables from anon for the `postgres` default, and sets anon's
  `plans` read.
- `reviews/0010_gtm_least_privilege_proposed.sql` revokes TRUNCATE on tables from anon and authenticated for the
  `postgres` default.

Neither can change the `supabase_admin` defaults. The project owner's role does not have that right.

## Requested change (for Supabase to run as `supabase_admin`, or to advise the correct way for the owner to run it)

```sql
-- Required: stop new tables from giving anon or authenticated TRUNCATE
alter default privileges for role supabase_admin in schema public revoke truncate on tables from anon, authenticated;

-- Required: stop new tables from giving anon any table privilege
alter default privileges for role supabase_admin in schema public revoke all on tables from anon;

-- Recommended: stop new functions from giving anon EXECUTE by default
alter default privileges for role supabase_admin in schema public revoke execute on functions from anon;

-- Recommended, to be decided by the owner: REFERENCES, TRIGGER and MAINTAIN for anon and authenticated
alter default privileges for role supabase_admin in schema public revoke references, trigger, maintain on tables from anon, authenticated;
```

Sequences are not part of this request. The `anon` sequence privileges are listed for information only.

## Questions for Support

1. Confirm the current contents of `pg_default_acl` for `supabase_admin` in schema `public`, all object types, and
   confirm the table above.
2. Confirm that changing these defaults does not change the ACL of any existing table, function or sequence. It should
   affect only objects created afterwards.
3. Confirm whether any Supabase-managed feature depends on `anon` or `authenticated` holding `TRUNCATE`, `REFERENCES`,
   `TRIGGER` or `MAINTAIN` on new `public` tables, or EXECUTE on new public functions. The expected answer is no, but the
   project should not rely on that.
4. Confirm whether the platform reapplies these defaults during maintenance or upgrades, which would undo the change.
5. Confirm the supported way to make the change: Supabase applies it, or the owner may run it with a specific role.

## What this repository has verified

- No SQL function in production `public` or `app_private` uses `TRUNCATE` (read-only check, 2026-11-10).
- The only TRUNCATE trigger is `cron.job`'s `cron_job_cache_invalidate`, in the `cron` schema.
- `postgres` is not a superuser and is not a member of `supabase_admin`.
- The local replica test `supabase/tests/local/36_least_privilege_tests.sql` checks the `postgres` default with a probe table,
  and path G of `run_local.sh` runs it on a 56-table copy.
