import { PrismaClient } from '@prisma/client';

declare global {
  // eslint-disable-next-line no-var
  var prisma: PrismaClient | undefined;
}

export const prisma =
  global.prisma ||
  new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error', 'warn'] : ['error'],
  });

if (process.env.NODE_ENV !== 'production') {
  global.prisma = prisma;
}

export async function executeSafeTransaction<T>(fn: (tx: any) => Promise<T>): Promise<T> {
  return prisma.$transaction(fn, {
    maxWait: 2000,
    timeout: 5000,
  });
}
