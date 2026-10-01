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
