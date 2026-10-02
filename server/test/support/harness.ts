import { PrismaClient } from '@prisma/client';
import type { Express } from 'express';
import request, { type Response } from 'supertest';
import { createApp } from '../../src/app';
import type { Env } from '../../src/config/env';

/**
 * Builds a running API backed by a real (throwaway) Postgres, exercised
 * in-process via supertest — mirroring the Dart harness, which called
 * `BudgetWiseApi.handler` directly with no port bind.
 */
export class Harness {
  readonly prisma: PrismaClient;
  readonly app: Express;

  private constructor(prisma: PrismaClient, app: Express) {
    this.prisma = prisma;
    this.app = app;
  }

  static async start(): Promise<Harness> {
    const databaseUrl =
      process.env.DATABASE_TEST_URL ??
      'postgresql://postgres:postgres@localhost:5433/budgetwise_test';

    const env: Env = {
      databaseUrl,
      jwtSecret: 'test-secret-that-is-definitely-long-enough-000000',
      port: 0,
      accessTokenMinutes: 60,
      refreshTokenDays: 30,
    };

    const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl } } });
    const app = createApp({ prisma, env });

    return new Harness(prisma, app);
  }

  async stop(): Promise<void> {
    await this.prisma.$disconnect();
  }

  /** Empties every table, in FK-safe order. Leaves the schema in place. */
  async reset(): Promise<void> {
    await this.prisma.goalContribution.deleteMany();
    await this.prisma.investment.deleteMany();
    await this.prisma.savingsEntry.deleteMany();
    await this.prisma.expense.deleteMany();
    await this.prisma.goal.deleteMany();
    await this.prisma.budget.deleteMany();
    await this.prisma.refreshToken.deleteMany();
    await this.prisma.user.deleteMany();
  }

  get(path: string, token?: string) {
    return this.send('get', path, undefined, token);
  }

  post(path: string, body?: unknown, token?: string) {
    return this.send('post', path, body, token);
  }

  patch(path: string, body?: unknown, token?: string) {
    return this.send('patch', path, body, token);
  }

  delete(path: string, token?: string) {
    return this.send('delete', path, undefined, token);
  }

  private send(
    method: 'get' | 'post' | 'patch' | 'delete',
    path: string,
    body: unknown,
    token?: string,
  ): Promise<Response> {
    let req = request(this.app)[method](path);
    if (token) req = req.set('Authorization', `Bearer ${token}`);
    if (body !== undefined) req = req.send(body as object);
    return req;
  }

  /** Signs a new user up and returns their session. */
  async signUp(opts: { email: string; password: string; displayName?: string }): Promise<Session> {
    const response = await this.post('/v1/auth/signup', opts);
    if (response.status !== 201) {
      throw new Error(`sign-up failed: ${response.status} ${JSON.stringify(response.body)}`);
    }
    return new Session(
      response.body.accessToken,
      response.body.refreshToken,
      response.body.user.id,
      this,
    );
  }
}

/** A signed-up user, with helpers that carry the bearer token automatically. */
export class Session {
  constructor(
    readonly accessToken: string,
    readonly refreshToken: string,
    readonly userId: string,
    private readonly harness: Harness,
  ) {}

  get(path: string) {
    return this.harness.get(path, this.accessToken);
  }

  post(path: string, body?: unknown) {
    return this.harness.post(path, body, this.accessToken);
  }

  patch(path: string, body?: unknown) {
    return this.harness.patch(path, body, this.accessToken);
  }

  delete(path: string) {
    return this.harness.delete(path, this.accessToken);
  }
}
