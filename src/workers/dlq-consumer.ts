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
    await this.redisConnection.disconnect();
    console.info('[DLQ-Consumer] Redis connection closed gracefully');
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

