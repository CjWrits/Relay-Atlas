# ADR-002: BullMQ Message Queue Architecture & Retry Topologies

- **Status:** APPROVED
- **Date:** 2026-10-17
- **Authors:** Platform Engineering

## Context
High ingestion rate of client telemetry and webhook integrations requires decoupled queue processing.

## Decision
1. Standard queues will leverage Redis streams backed by BullMQ.
2. Poison pills that fail 3 consecutive exponential backoff retries are moved to Dead-Letter Queue (DLQ).
3. DLQ consumers must quarantine messages to avoid memory leak or pipeline stall.
