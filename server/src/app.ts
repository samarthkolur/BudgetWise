import express, { type Express } from 'express';
import type { PrismaClient } from '@prisma/client';
import { bodyLimit, cors, errorHandler, requestId, requireAuth } from './http/middleware';
import { TokenService } from './auth/tokens';
import { authRoutes } from './routes/authRoutes';
import { apiRoutes } from './routes/apiRoutes';
import type { Env } from './config/env';

/**
 * Builds the Express app. Deliberately NOT bound to a port — mirrors the old
 * Dart server's `BudgetWiseApi.handler`, which the test harness called
 * in-process with no port bind. `index.ts` is the only place that calls
 * `.listen()`.
 */
export function createApp(opts: { prisma: PrismaClient; env: Env }): Express {
  const { prisma, env } = opts;
  const tokens = new TokenService({
    prisma,
    secret: env.jwtSecret,
    accessTokenMinutes: env.accessTokenMinutes,
    refreshTokenDays: env.refreshTokenDays,
  });

  const app = express();

  app.use(requestId());
  app.use(cors());
  app.use(bodyLimit());
  app.use(express.json({ limit: '256kb' }));

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  app.use('/v1/auth', authRoutes(prisma, tokens));
  app.use('/v1', requireAuth(tokens), apiRoutes(prisma, tokens));

  // Must be registered last: Express only treats a 4-arg function as error
  // middleware.
  app.use(
    errorHandler((error) => {
      // eslint-disable-next-line no-console
      console.error(error);
    }),
  );

  return app;
}
