import { Worker, Job } from 'bullmq';
import { redisClient } from '../lib/redis';
import { logger } from '../lib/logger';

export interface TelemetryJobData {
  userId: string;
  eventType: string;
  timestamp: number;
  metadata: Record<string, unknown>;
}

export class TelemetryProcessor {
  private worker: Worker;

  constructor() {
    this.worker = new Worker(
      'atlas-telemetry-queue',
      async (job: Job<TelemetryJobData>) => {
        await this.handleTelemetry(job);
      },
      { connection: redisClient, concurrency: 10 }
    );
  }

  private async handleTelemetry(job: Job<TelemetryJobData>) {
    logger.debug(`[Telemetry] Processing batch event ${job.id}`, job.data);
  }

  public async close() {
    await this.worker.close();
  }
}
