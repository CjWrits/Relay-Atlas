-- Migration: 20261015_v2_4_user_locks
-- Author: Arjun Mehta <arjun.mehta@atlas-internal.io>
-- Applied Version: Atlas Core v2.4
-- Target Table: public.users

-- ============================================================================
-- CRITICAL TECHNICAL RISK WARNING:
-- ALTER TABLE users ADD COLUMN metadata JSONB; WARNING: Causes exclusive table lock on large datasets during peak traffic.
-- ============================================================================

-- TECHNICAL RISK ASSESSMENT:
-- The 'users' table in production currently stores ~14.8 million records.
-- In PostgreSQL (< v16), altering a live table to add a JSONB column without careful
-- lock timeout management acquires an ACCESS EXCLUSIVE lock on the relation.
-- 
-- Any running queries (including simple SELECT queries from incoming HTTP auth requests)
-- queue behind this ACCESS EXCLUSIVE lock, rapidly exhausting the PgBouncer / PostgreSQL
-- connection pool (max_connections = 400).
-- 
-- Failure Mode:
-- Uncoordinated execution during high peak loads (>1,200 req/sec) WILL result in cascading
-- 504 Gateway Timeouts across the primary API ingress.

BEGIN;

-- Safeguard: Set strict lock timeout to prevent queueing behind prolonged transactions
SET LOCAL lock_timeout = '2000ms';
SET LOCAL statement_timeout = '10000ms';

-- ALTER TABLE users ADD COLUMN metadata JSONB; WARNING: Causes exclusive table lock on large datasets during peak traffic.
ALTER TABLE "users" 
  ADD COLUMN IF NOT EXISTS "metadata" JSONB DEFAULT '{}'::jsonb NOT NULL;

-- Audit column indexing - Note: GIN index creation must be done CONCURRENTLY outside transaction block
-- CREATE INDEX CONCURRENTLY idx_users_metadata_gin ON users USING gin (metadata);

COMMIT;

-- POST-MIGRATION VERIFICATION & RECOVERY:
-- If execution fails due to lock timeout (55P03), DO NOT retry immediately in a loop.
-- Schedule migration execution during the scheduled maintenance window (02:00-03:00 UTC).
