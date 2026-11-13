# Atlas Core Developer Onboarding & Technical Handover Notes

- **Author:** Maya Chen <maya.chen@atlas-internal.io>
- **Date:** 2026-11-02
- **Purpose:** Initial architectural review of Atlas Core modules, identify open risks, technical conflicts, and onboarding blockers.

---

## 1. Executive Summary & First Impressions
Atlas Core provides essential services for token synchronization and event processing. However, the repository displays active technical divergences and ownership vacuums that represent immediate delivery risks:
- Conflicting real-time transport paradigms (SSE vs WebSockets).
- Dangerous un-gated database migration scripts capable of causing table locks.
- Critical background worker infrastructure operating without ownership or alerting.

---

## 2. Key Findings & Open Blockers

### A. Real-Time Transport Strategy Collision
- **Existing Implementation:** `src/auth/session-sync.ts` by Arjun Mehta uses Server-Sent Events (SSE) to push OAuth2 token refreshes to multiple browser tabs.
- **Proposed Architecture:** `docs/architecture/rfc-event-stream.md` by Elena Rostova argues that SSE cannot support bi-directional telemetry and suffers connection limits in HTTP/1.1 proxies, proposing a unified WebSocket Gateway.
- **Blocker:** Which transport is authoritative for upcoming roadmap features? We need a joint architecture sync between Elena and Arjun before building out new event consumers.

### B. High-Risk Database Migration (`20261015_v2_4_user_locks.sql`)
- Arjun documented a critical warning:
  > `ALTER TABLE users ADD COLUMN metadata JSONB; WARNING: Causes exclusive table lock on large datasets during peak traffic.`
- **Concern:** The `users` table holds ~15M rows. Running this directly through Prisma migrate in production without a verified zero-downtime execution plan risks taking down our auth ingress during peak hours.
- **Action Required:** Coordinate with Platform/DBA team to verify whether this was already run on staging or if an off-peak maintenance window is scheduled.

### C. Dead-Letter Queue (DLQ) Ownership Vacuum
- Located in `src/workers/dlq-consumer.ts`:
  > `// TODO(unassigned): DLQ consumer alerting and manual retry routing need dedicated owner.`
- Arjun created this worker as a temporary mitigation during v2.3. No team currently monitors the DLQ, and failed jobs sit unalerted in Redis.
- **Action Required:** Formally assign DLQ triage to an on-call rotation.

---

## 3. Next Steps & Questions for Arjun & Elena
1. **[For Elena / Arjun]:** Can we schedule a 30-min RFC review to finalize SSE vs WebSocket unification?
2. **[For Arjun]:** What is the rollout status of `20261015_v2_4_user_locks.sql`?
3. **[For Engineering Leadership]:** Who owns the BullMQ Dead-Letter Queue monitoring and alerting operations?
