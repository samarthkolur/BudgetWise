import { PrismaClient } from '@prisma/client';
import { createApp } from './app';
import { loadEnv } from './config/env';

// Fails loudly at startup rather than lazily on first request — see
// src/config/env.ts.
const env = loadEnv();
const prisma = new PrismaClient();
const app = createApp({ prisma, env });

const server = app.listen(env.port, () => {
  // eslint-disable-next-line no-console
  console.log(`BudgetWise API listening on :${env.port}`);
});

async function shutdown(signal: string) {
  // eslint-disable-next-line no-console
  console.log(`${signal} received, shutting down`);
  server.close();
  await prisma.$disconnect();
  process.exit(0);
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
