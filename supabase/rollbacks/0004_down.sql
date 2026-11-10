-- Rollback for 0004. Drops three tables and everything in them.
-- Run only after the 0005 and 0006 rollbacks, and only with separate approval.
-- Before running, export any rows that exist, because this destroys them.
drop table if exists public.deals;
drop table if exists public.clients;
drop table if exists public.companies;
