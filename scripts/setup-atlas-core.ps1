# Setup standalone synthetic test repository 'atlas-core'
$ErrorActionPreference = "Stop"

$currentDir = (Get-Item -Path ".").FullName
$parentDir = (Get-Item -Path ".").Parent.FullName
$repoPath = Join-Path $parentDir "atlas-core"

Write-Host "Setting up atlas-core repository at: $repoPath" -ForegroundColor Cyan

if (Test-Path $repoPath) {
    Remove-Item -Recurse -Force $repoPath
}

New-Item -ItemType Directory -Path $repoPath | Out-Null
Set-Location $repoPath

git init -b main

function Invoke-GitCommit {
    param (
        [string]$AuthorName,
        [string]$AuthorEmail,
        [string]$Date,
        [string]$Message
    )
    git add -A
    $env:GIT_AUTHOR_NAME = $AuthorName
    $env:GIT_AUTHOR_EMAIL = $AuthorEmail
    $env:GIT_AUTHOR_DATE = $Date
    $env:GIT_COMMITTER_NAME = $AuthorName
    $env:GIT_COMMITTER_EMAIL = $AuthorEmail
    $env:GIT_COMMITTER_DATE = $Date
    git commit -m $Message
    Remove-Item Env:\GIT_AUTHOR_NAME
    Remove-Item Env:\GIT_AUTHOR_EMAIL
    Remove-Item Env:\GIT_AUTHOR_DATE
    Remove-Item Env:\GIT_COMMITTER_NAME
    Remove-Item Env:\GIT_COMMITTER_EMAIL
    Remove-Item Env:\GIT_COMMITTER_DATE
}

# --- Commit 1: Setup & Baseline ---
$readme = @'
# Project Atlas Core (`atlas-core`)

> Distributed workspace synchronization, tenant authorization broker, and real-time backend engine.

## Overview
Atlas Core is the backbone platform service for Project Atlas. It manages multi-tenant enterprise authorization, session persistence across distributed browser clients, database schemas, and background job ingestion.

## Tech Stack
- **Framework:** Next.js 15 (App Router & Edge Handlers)
- **Database & ORM:** PostgreSQL 16 with Prisma ORM
- **Cache & Pub/Sub:** Redis (ioredis cluster client)
- **Asynchronous Task Queue:** BullMQ
- **Language:** TypeScript 5.6+ / Node.js 22 LTS

## Project Layout
```
atlas-core/
├── docs/
│   ├── architecture/        # RFCs and architectural decision records (ADRs)
│   └── onboarding-notes.md  # Developer handover & service documentation
├── prisma/
│   ├── schema.prisma        # Prisma database schema definition
│   └── migrations/          # Version-controlled SQL migration scripts
├── src/
│   ├── auth/                # OAuth2 and session synchronization engines
│   └── workers/             # Asynchronous BullMQ background worker daemons
├── package.json
└── README.md
```

## Getting Started

### Prerequisites
- Node.js >= 22.0.0
- Docker & Docker Compose (for local PostgreSQL & Redis)
- pnpm >= 9.0.0

### Local Environment Setup
1. Clone the repository and install dependencies:
   ```bash
   pnpm install
   ```
2. Start the backing infrastructure:
   ```bash
   docker compose up -d postgres redis
   ```
3. Run database migrations:
   ```bash
   pnpm run db:migrate
   ```
4. Start the development server:
   ```bash
   pnpm dev
   ```

## Security & Compliance
All authorization routines and cryptographic tokens follow OAuth2 / OIDC spec compliance. Direct table schema alterations must be reviewed through the Architecture Council to avoid table lock contention on large production volumes.
'@
Set-Content -Path "README.md" -Value $readme -Encoding utf8

$pkg = @'
{
  "name": "atlas-core",
  "version": "2.4.0",
  "private": true,
  "description": "Project Atlas core platform engine and backend synchronization services",
  "main": "src/index.ts",
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "db:migrate": "prisma migrate deploy",
    "db:generate": "prisma generate",
    "worker:dlq": "ts-node src/workers/dlq-consumer.ts",
    "test": "jest"
  },
  "dependencies": {
    "@prisma/client": "^6.0.1",
    "bullmq": "^5.25.0",
    "ioredis": "^5.4.1",
    "next": "15.0.3",
    "react": "19.0.0-rc-66855b96-20241106",
    "react-dom": "19.0.0-rc-66855b96-20241106",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/node": "^22.9.0",
    "@types/react": "^18.3.12",
    "prisma": "^6.0.1",
    "typescript": "^5.6.3"
  }
}
'@
Set-Content -Path "package.json" -Value $pkg -Encoding utf8

Invoke-GitCommit -AuthorName "Elena Rostova" -AuthorEmail "elena.rostova@atlas-internal.io" -Date "2026-10-01T10:00:00+00:00" -Message "chore(init): project setup with Next.js 15, Prisma, and Redis cache"

# --- Commit 2: Architectural Decision - SSE Transport ---
New-Item -ItemType Directory -Path "src/auth" -Force | Out-Null
$sessSync = @'
/**
 * Server-Sent Events (SSE) Cross-Tab Session Synchronization
 *
 * ARCHITECTURAL DECISION NOTE:
 * Author: Arjun Mehta <arjun.mehta@atlas-internal.io>
 * Date: 2026-10-08
 *
 * Design Decision:
 * Implemented Server-Sent Events (SSE) over WebSockets for cross-tab token
 * synchronization. SSE provides native HTTP/2 multiplexing, automatic reconnection
 * protocol support in browsers via EventSource, and zero bidirectional handshake
 * overhead. Cross-tab session sync is inherently unidirectional (server pushes
 * auth state changes, token rotation, and remote invalidations to clients).
 */

import { Redis } from 'ioredis';
import { IncomingMessage, ServerResponse } from 'http';

export interface SessionSyncPayload {
  userId: string;
  sessionId: string;
  eventType: 'TOKEN_REFRESHED' | 'SESSION_TERMINATED' | 'MFA_REQUIRED' | 'POLICY_UPDATE';
  accessTokenExpiresAt: number;
  issuedAt: number;
}

export class SessionSyncBroker {
  private redisSubscriber: Redis;
  private activeStreams: Map<string, Set<ServerResponse>> = new Map();
  private heartbeatIntervalMs: number = 15000;

  constructor(redisConnectionUri: string) {
    this.redisSubscriber = new Redis(redisConnectionUri, {
      maxRetriesPerRequest: 3,
      enableReadyCheck: true,
    });
    this.initPubSubSubscription();
  }

  private initPubSubSubscription(): void {
    this.redisSubscriber.psubscribe('session:events:*', (err, count) => {
      if (err) {
        console.error('[SessionSync] Redis pattern subscription failed', err);
        return;
      }
      console.info(`[SessionSync] Subscribed to ${count} Redis event channel(s)`);
    });

    this.redisSubscriber.on('pmessage', (_pattern, channel, message) => {
      try {
        const userId = channel.split(':')[2];
        const payload: SessionSyncPayload = JSON.parse(message);
        this.broadcastToUserContexts(userId, payload);
      } catch (parseError) {
        console.error('[SessionSync] Error parsing incoming pubsub payload', parseError);
      }
    });
  }

  /**
   * Registers a client connection to the SSE stream.
   */
  public registerStream(userId: string, req: IncomingMessage, res: ServerResponse): void {
    // Set headers for standard Server-Sent Events (SSE) streaming
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
      'X-Accel-Buffering': 'no', // Disable Nginx proxy buffering
    });

    res.write(`: connected at ${new Date().toISOString()}\n\n`);

    if (!this.activeStreams.has(userId)) {
      this.activeStreams.set(userId, new Set());
    }
    this.activeStreams.get(userId)!.add(res);

    // Heartbeat to keep TCP socket open through firewalls & proxies
    const heartbeatTimer = setInterval(() => {
      res.write(': heartbeat ping\n\n');
    }, this.heartbeatIntervalMs);

    const cleanup = () => {
      clearInterval(heartbeatTimer);
      const userSockets = this.activeStreams.get(userId);
      if (userSockets) {
        userSockets.delete(res);
        if (userSockets.size === 0) {
          this.activeStreams.delete(userId);
        }
      }
      res.end();
    };

    req.on('close', cleanup);
    req.on('error', cleanup);
  }

  /**
   * Dispatches session updates down to all connected tabs for a user.
   */
  private broadcastToUserContexts(userId: string, payload: SessionSyncPayload): void {
    const clients = this.activeStreams.get(userId);
    if (!clients || clients.size === 0) {
      return;
    }

    const sseFormattedData = `event: session_sync\ndata: ${JSON.stringify(payload)}\n\n`;

    clients.forEach((client) => {
      try {
        client.write(sseFormattedData);
      } catch (err) {
        console.warn(`[SessionSync] Failed sending payload to client tab for user ${userId}`, err);
      }
    });
  }
}
'@
Set-Content -Path "src/auth/session-sync.ts" -Value $sessSync -Encoding utf8

Invoke-GitCommit -AuthorName "Arjun Mehta" -AuthorEmail "arjun.mehta@atlas-internal.io" -Date "2026-10-08T14:30:00+00:00" -Message "feat(auth): initial OAuth2 implementation using Server-Sent Events (SSE) for token sync"

# --- Commit 3: Conflicting Architectural Direction ---
New-Item -ItemType Directory -Path "docs/architecture" -Force | Out-Null
$rfc = @'
# RFC-0042: Preferring WebSockets over SSE for Atlas Event Streaming

- **Author:** Elena Rostova <elena.rostova@atlas-internal.io>
- **Date:** 2026-10-12
- **Status:** PROPOSED / CONFLICTING
- **Replaces / Challenges:** `src/auth/session-sync.ts` (Arjun Mehta's SSE Implementation)

---

## 1. Context & Motivation
In commit `feat(auth): initial OAuth2 implementation using Server-Sent Events (SSE) for token sync`, Arjun Mehta introduced an HTTP Server-Sent Events (SSE) transport pipeline (`src/auth/session-sync.ts`) to propagate token refreshes and invalidations across browser tabs.

While SSE serves simple unidirectional downlinks cleanly, Project Atlas is expanding into collaborative workspaces requiring:
1. Real-time telemetry reporting from browser clients back to Atlas Core.
2. Low-latency presence and live cursor synchronization (< 40ms round-trip).
3. Bi-directional flow control and binary message serialization (e.g., MessagePack or Protobuf).

## 2. Fundamental Flaws in the Current SSE Approach

### A. Unidirectional Limitation
SSE only streams from server to client. For clients to emit heartbeats, collaborative updates, or telemetry events, they must issue separate HTTP `POST` requests. Under heavy traffic, opening new TCP handshakes and TLS sessions for every client emission introduces significant latency, connection bloat, and server overhead.

### B. Connection Exhaustion in HTTP/1.1 Fallback Environments
In corporate enterprise environments with older proxies or where HTTP/2 is downgraded, browsers enforce a strict limit of **6 concurrent open SSE connections per domain**. If a user opens 5-6 tabs, additional tabs stall completely, breaking auth and live data synchronization.

### C. Fragmentation of Real-Time Infrastructure
Maintaining SSE for authentication sync while building WebSockets for live workspace telemetry creates two disparate streaming stacks, redundant Redis Pub/Sub channels, and fragmented connection monitoring.

## 3. Proposed WebSocket Unified Architecture
We propose replacing `src/auth/session-sync.ts` with a unified WebSocket Gateway (`src/realtime/ws-gateway.ts`):
- Single persistent full-duplex socket per client tab.
- Multiplexed channel protocol (`auth`, `presence`, `telemetry`).
- Support for binary framing to reduce payload overhead by up to 60%.

```mermaid
flowchart TD
    ClientTab["Browser Tabs (1..N)"]
    subgraph Proposed Architecture
        WS["Unified WebSocket Gateway"]
        AuthCh["Channel: Auth / Session Sync"]
        TelemCh["Channel: Telemetry & Presence"]
    end
    ClientTab <-->|Bi-directional WebSocket| WS
    WS --> AuthCh
    WS --> TelemCh
```

## 4. Conflict & Action Items
- Deprecate `src/auth/session-sync.ts`.
- Address objections raised by Arjun Mehta regarding WebSocket reconnection complexity and proxy traversal.
- Target migration for Atlas Core v2.5.
'@
Set-Content -Path "docs/architecture/rfc-event-stream.md" -Value $rfc -Encoding utf8

Invoke-GitCommit -AuthorName "Elena Rostova" -AuthorEmail "elena.rostova@atlas-internal.io" -Date "2026-10-12T11:15:00+00:00" -Message "refactor(transport): RFC - prefer WebSockets over SSE for bi-directional event stream"

# --- Commit 4: Critical Technical Risk ---
New-Item -ItemType Directory -Path "prisma/migrations" -Force | Out-Null
$sql = @'
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
'@
Set-Content -Path "prisma/migrations/20261015_v2_4_user_locks.sql" -Value $sql -Encoding utf8

Invoke-GitCommit -AuthorName "Arjun Mehta" -AuthorEmail "arjun.mehta@atlas-internal.io" -Date "2026-10-15T16:45:00+00:00" -Message "fix(db): add v2.4 migration warning - high risk of exclusive lock on users table"

# --- Commit 5: Knowledge Gap & Unassigned Responsibility ---
New-Item -ItemType Directory -Path "src/workers" -Force | Out-Null
$worker = @'
/**
 * Dead-Letter Queue (DLQ) Consumer & Poison Pill Recovery
 *
 * Author: Arjun Mehta <arjun.mehta@atlas-internal.io>
 * Status: Experimental / In-Production Workaround
 *
 * OPERATIONAL WARNING & RESPONSIBILITY GAP:
 * TODO(unassigned): DLQ consumer alerting and manual retry routing need dedicated owner.
 *
 * Context:
 * This worker was spun up rapidly during the v2.3 release to catch failed webhook
 * deliveries and downstream database serialization errors that were getting silently
 * dropped by BullMQ workers. Currently, no team or engineer is assigned to monitor
 * this queue, respond to DLQ threshold alerts, or prune poisoned messages.
 */

import { Worker, Job } from 'bullmq';
import { Redis } from 'ioredis';

const REDIS_CONNECTION_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const DLQ_QUEUE_NAME = 'atlas-ingestion-dlq';

export interface DeadLetterJobPayload {
  originalQueue: string;
  originalJobId: string;
  payload: Record<string, unknown>;
  failedReason: string;
  stackTrace: string[];
  attemptsMade: number;
  quarantinedAt: string;
}

export class DeadLetterQueueConsumer {
  private redisConnection: Redis;
  private worker: Worker;

  constructor() {
    this.redisConnection = new Redis(REDIS_CONNECTION_URL, { maxRetriesPerRequest: null });

    this.worker = new Worker(
      DLQ_QUEUE_NAME,
      async (job: Job<DeadLetterJobPayload>) => {
        await this.processPoisonedMessage(job);
      },
      {
        connection: this.redisConnection,
        concurrency: 5,
        limiter: {
          max: 50,
          duration: 1000,
        },
      }
    );

    this.setupLifecycleHooks();
  }

  private async processPoisonedMessage(job: Job<DeadLetterJobPayload>): Promise<void> {
    const { originalQueue, originalJobId, failedReason, quarantinedAt } = job.data;

    console.warn(`[DLQ-Consumer] Quarantined job ${job.id} (origin: ${originalQueue}#${originalJobId})`);
    console.warn(`[DLQ-Consumer] Failure reason: ${failedReason}`);

    // Persist quarantine audit record
    await this.redisConnection.hset(
      `dlq:quarantine:${job.id}`,
      'metadata',
      JSON.stringify({
        ...job.data,
        receivedAt: quarantinedAt,
        processedByWorkerAt: new Date().toISOString(),
      })
    );

    // TODO(unassigned): DLQ consumer alerting and manual retry routing need dedicated owner.
    // ACTION REQUIRED:
    // 1. Wire this notification to PagerDuty or Slack webhook (#alerts-atlas-dlq).
    // 2. Build automated replay tool for transient database failure exceptions.
    // 3. Define SLA for poisoned message retention (currently messages remain indefinitely).
    await this.triggerEmergencyAlertPlaceholder(job.data);
  }

  private async triggerEmergencyAlertPlaceholder(data: DeadLetterJobPayload): Promise<void> {
    // Alerting implementation is unassigned.
    // Log placeholder to standard error until an owning team claims this component.
    process.stderr.write(
      `[UNASSIGNED_OWNERSHIP_ALERT] Poisoned message in ${data.originalQueue} requires manual review!\n`
    );
  }

  private setupLifecycleHooks(): void {
    this.worker.on('completed', (job) => {
      console.log(`[DLQ-Consumer] Archived job ${job.id} into quarantine store.`);
    });

    this.worker.on('failed', (job, err) => {
      console.error(`[DLQ-Consumer] CRITICAL: DLQ worker failed to process quarantine job ${job?.id}:`, err);
    });
  }

  public async close(): Promise<void> {
    await this.worker.close();
    await this.redisConnection.quit();
  }
}

if (require.main === module) {
  const consumer = new DeadLetterQueueConsumer();
  console.info('Dead-Letter Queue Worker started. Monitoring:', DLQ_QUEUE_NAME);

  process.on('SIGTERM', async () => {
    console.info('Shutting down DLQ consumer...');
    await consumer.close();
    process.exit(0);
  });
}
'@
Set-Content -Path "src/workers/dlq-consumer.ts" -Value $worker -Encoding utf8

Invoke-GitCommit -AuthorName "Arjun Mehta" -AuthorEmail "arjun.mehta@atlas-internal.io" -Date "2026-10-22T09:20:00+00:00" -Message "WIP(workers): add BullMQ dead-letter queue; unassigned retry consumer alerting"

# --- Commit 6: Incoming Developer Context ---
New-Item -ItemType Directory -Path "docs" -Force | Out-Null
$notes = @'
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
'@
Set-Content -Path "docs/onboarding-notes.md" -Value $notes -Encoding utf8

Invoke-GitCommit -AuthorName "Maya Chen" -AuthorEmail "maya.chen@atlas-internal.io" -Date "2026-11-02T13:10:00+00:00" -Message "docs(onboarding): initial review of Atlas auth modules and open blockers"

# Set remote
git remote add origin https://gitlab.com/cjwrits/atlas.git

Write-Host "`n=== Verification: Git Log ===" -ForegroundColor Green
git log --graph --pretty=format:'%h - %an <%ae> (%ad): %s' --date=short

Write-Host "`n=== Verification: Distinct Authors ===" -ForegroundColor Green
git shortlog -sne --all

Set-Location $currentDir
Write-Host "`nAtlas Core setup completed successfully in $repoPath" -ForegroundColor Green
