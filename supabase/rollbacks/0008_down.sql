-- 0008_down.sql. Manual rollback for 0008_gtm_clients_readiness.sql.
-- Drops only the readiness function. It holds no data, so nothing else needs restoring.
drop function if exists public.clients_readiness();
