# ADR-001: Zero-Downtime Database Concurrency and Migration Guidelines

- **Status:** APPROVED
- **Date:** 2026-10-10
- **Authors:** Platform Architecture Council

## Context
Atlas Core services high-concurrency enterprise workloads. Alterations to high-volume tables such as `users` and `sessions` must not acquire exclusive locks during production hours.

## Decision
1. Any DDL migration adding columns with defaults must use nullable or default expressions that avoid table rewrites.
2. Index creation must always be scheduled with `CONCURRENTLY` outside of transaction blocks.
3. Lock timeouts must be explicitly bounded to 2000ms.
