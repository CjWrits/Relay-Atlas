# Operational Runbook: Dead-Letter Queue (DLQ) Triage

## Severity
- **Level:** SEV-3 (Transient failures) / SEV-2 (Sustained queue buildup > 500 items)

## Incident Symptoms
- Ingestion alert: `[UNASSIGNED_OWNERSHIP_ALERT] Poisoned message in atlas-ingestion-dlq`.
- Redis quarantine hash counts increasing.

## Recovery Steps
1. Inspect poisoned payload metadata in Redis key `dlq:quarantine:<job_id>`.
2. Check PostgreSQL connection pool capacity and lock timeouts.
3. Once upstream resolves, invoke manual retry tool: `pnpm run worker:dlq --replay`.
