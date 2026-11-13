import { Redis, RedisOptions } from 'ioredis';
import { config } from '../config';

const redisOptions: RedisOptions = {
  maxRetriesPerRequest: 3,
  enableReadyCheck: true,
  lazyConnect: true,
  retryStrategy(times) {
    const delay = Math.min(times * 200, 2000);
    return delay;
  },
};

export const redisClient = new Redis(config.REDIS_URL, redisOptions);
export const redisSubscriber = new Redis(config.REDIS_URL, redisOptions);

redisClient.on('error', (err) => {
  console.error('[Redis:Client] Connection error:', err.message);
});

redisSubscriber.on('error', (err) => {
  console.error('[Redis:Subscriber] Connection error:', err.message);
});

export function getChannelKey(tenantId: string, channel: string): string {
  return tlas:tenant::;
}
