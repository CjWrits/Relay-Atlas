import { Queue, QueueOptions } from 'bullmq';
import { redisClient } from '../lib/redis';

const queueOptions: QueueOptions = {
  connection: redisClient,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 1000,
    },
    removeOnComplete: true,
    removeOnFail: false,
  },
};

export const telemetryQueue = new Queue('atlas-telemetry-queue', queueOptions);
export const auditQueue = new Queue('atlas-audit-queue', queueOptions);
