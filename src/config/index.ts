import { z } from 'zod';
import dotenv from 'dotenv';

dotenv.config();

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.string().transform(Number).default('3000'),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  REDIS_URL: z.string().default('redis://localhost:6379'),
  JWT_SECRET: z.string().min(16, 'JWT_SECRET must be at least 16 chars'),
  JWT_EXPIRES_IN: z.string().default('1h'),
  WS_PORT: z.string().transform(Number).default('8080'),
  SSE_HEARTBEAT_MS: z.string().transform(Number).default('15000'),
});

export const config = envSchema.parse({
  NODE_ENV: process.env.NODE_ENV,
  PORT: process.env.PORT,
  DATABASE_URL: process.env.DATABASE_URL || 'postgresql://atlas:atlas_password@localhost:5432/atlas_db?schema=public',
  REDIS_URL: process.env.REDIS_URL || 'redis://localhost:6379',
  JWT_SECRET: process.env.JWT_SECRET || 'relay-atlas-super-secret-development-key-32-chars-min',
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN,
  WS_PORT: process.env.WS_PORT,
  SSE_HEARTBEAT_MS: process.env.SSE_HEARTBEAT_MS,
});
