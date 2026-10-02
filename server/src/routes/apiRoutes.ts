import { Router } from 'express';
import type { PrismaClient } from '@prisma/client';
import { ApiError } from '../http/errors';
import { asyncHandler, principalOf } from '../http/middleware';
import { serialize, serializeAll } from '../http/serialize';
import { publicUser } from './authRoutes';
import { TokenService } from '../auth/tokens';
import { Period } from '../domain/period';
import * as budgetRepo from '../repositories/budgetRepository';
import * as expenseRepo from '../repositories/expenseRepository';
import * as goalRepo from '../repositories/goalRepository';
import * as investingRepo from '../repositories/investingRepository';

/**
 * Everything behind a session. Ported from
 * server/lib/src/routes/api_routes.dart.
 *
 * Each handler starts by taking the principal from the request context and
 * passes that userId into the repository layer. There is no path by which a
 * handler can operate on an owner supplied by the caller — that is the whole
 * design, and it is what stands in for row-level security.
 */
export function apiRoutes(prisma: PrismaClient, tokens: TokenService): Router {
  const router = Router();

  // --- account -------------------------------------------------------------

  router.get(
    '/me',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const user = await prisma.user.findUnique({ where: { id: userId } });
      if (!user) throw ApiError.notFound('Account not found.');
      res.json(publicUser(user));
    }),
  );

  router.patch(
    '/me',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};

      const data: { displayName?: string; onboardingCompletedAt?: Date } = {};
      if (body.onboardingCompleted === true) {
        data.onboardingCompletedAt = new Date();
      }
      if (typeof body.displayName === 'string') {
        data.displayName = body.displayName;
      }
      if (Object.keys(data).length === 0) {
        throw ApiError.badRequest('Nothing to update.');
      }

      const user = await prisma.user.update({ where: { id: userId }, data });
      res.json(publicUser(user));
    }),
  );

  router.delete(
    '/me',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      await tokens.revokeAllFor(userId);
      // Postgres FKs (onDelete: Cascade) sweep every owned row once the User
      // row goes — unlike Mongo, which needed a hand-written sweep.
      await prisma.user.delete({ where: { id: userId } });
      res.status(204).end();
    }),
  );

  // --- budgets ---------------------------------------------------------------

  router.get(
    '/budgets',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const budgets = await budgetRepo.allBudgets(prisma, userId);
      res.json(serializeAll(budgets));
    }),
  );

  router.get(
    '/budgets/current',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const budget = await budgetRepo.budgetForPeriod(prisma, userId, Period.current());
      res.json(budget ? serialize(budget) : null);
    }),
  );

  router.post(
    '/budgets',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};

      const period = Period.parse(requireString(body, 'period'));
      const incomeMinor = requireInt(body, 'incomeMinor');
      const savingsTargetMinor = requireInt(body, 'savingsTargetMinor');

      const budget = await budgetRepo.createMonth(prisma, userId, {
        period,
        incomeMinor,
        savingsTargetMinor,
        savingsMode: typeof body.savingsMode === 'string' ? body.savingsMode : 'percent',
        savingsPercent: typeof body.savingsPercent === 'number' ? body.savingsPercent : null,
        investmentTargetMinor:
          body.investmentTargetMinor == null ? null : Number(body.investmentTargetMinor),
        carriedFromPeriod: body.carriedFromPeriod == null ? null : Period.parse(body.carriedFromPeriod),
      });

      res.status(201).json(serialize(budget));
    }),
  );

  router.get(
    '/summaries',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      res.json(await budgetRepo.allSummaries(prisma, userId));
    }),
  );

  router.get(
    '/summaries/:period',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const summary = await budgetRepo.summaryForPeriod(prisma, userId, Period.parse(req.params.period));
      res.json(summary ?? null);
    }),
  );

  router.post(
    '/budgets/:budgetId/confirm-savings',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};
      await budgetRepo.confirmSavings(
        prisma,
        userId,
        req.params.budgetId,
        requireInt(body, 'amountMinor'),
        typeof body.destination === 'string' ? body.destination : 'bank',
      );
      res.status(204).end();
    }),
  );

  // --- expenses --------------------------------------------------------------

  router.get(
    '/budgets/:budgetId/expenses',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const expenses = await expenseRepo.forBudget(prisma, userId, req.params.budgetId);
      res.json(serializeAll(expenses));
    }),
  );

  router.post(
    '/expenses',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};
      const expense = await expenseRepo.add(prisma, userId, {
        budgetId: requireString(body, 'budgetId'),
        amountMinor: requireInt(body, 'amountMinor'),
        spentOn: new Date(requireString(body, 'spentOn')),
        paymentMethod: typeof body.paymentMethod === 'string' ? body.paymentMethod : 'upi',
        note: typeof body.note === 'string' ? body.note : null,
      });
      res.status(201).json(serialize(expense));
    }),
  );

  router.patch(
    '/expenses/:expenseId',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};
      const expense = await expenseRepo.update(prisma, userId, req.params.expenseId, {
        amountMinor: requireInt(body, 'amountMinor'),
        spentOn: new Date(requireString(body, 'spentOn')),
        paymentMethod: typeof body.paymentMethod === 'string' ? body.paymentMethod : 'upi',
        note: typeof body.note === 'string' ? body.note : null,
      });
      if (!expense) throw ApiError.notFound();
      res.json(serialize(expense));
    }),
  );

  router.delete(
    '/expenses/:expenseId',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const deleted = await expenseRepo.remove(prisma, userId, req.params.expenseId);
      if (!deleted) throw ApiError.notFound();
      res.status(204).end();
    }),
  );

  // --- goals -------------------------------------------------------------------

  router.get(
    '/goals',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      res.json(serializeAll(await goalRepo.all(prisma, userId)));
    }),
  );

  router.post(
    '/goals',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};
      const goal = await goalRepo.create(prisma, userId, {
        title: requireString(body, 'title'),
        targetMinor: requireInt(body, 'targetMinor'),
        targetDate: body.targetDate == null ? null : new Date(body.targetDate),
        monthlyContributionMinor:
          body.monthlyContributionMinor == null ? null : Number(body.monthlyContributionMinor),
        icon: typeof body.icon === 'string' ? body.icon : null,
      });
      res.status(201).json(serialize(goal));
    }),
  );

  router.post(
    '/goals/:goalId/contribute',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};
      await goalRepo.contribute(prisma, userId, {
        goalId: req.params.goalId,
        amountMinor: requireInt(body, 'amountMinor'),
        budgetId: typeof body.budgetId === 'string' ? body.budgetId : null,
      });
      res.status(204).end();
    }),
  );

  router.delete(
    '/goals/:goalId',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const deleted = await goalRepo.remove(prisma, userId, req.params.goalId);
      if (!deleted) throw ApiError.notFound();
      res.status(204).end();
    }),
  );

  // --- investing -----------------------------------------------------------

  router.get(
    '/investing/status',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      res.json(await investingRepo.claimUnlock(prisma, userId));
    }),
  );

  router.post(
    '/investing',
    asyncHandler(async (req, res) => {
      const { userId } = principalOf(req);
      const body = req.body ?? {};
      const investment = await investingRepo.recordInvestment(prisma, userId, {
        budgetId: requireString(body, 'budgetId'),
        amountMinor: requireInt(body, 'amountMinor'),
        instrument: typeof body.instrument === 'string' ? body.instrument : 'other',
        note: typeof body.note === 'string' ? body.note : null,
      });
      res.status(201).json(serialize(investment));
    }),
  );

  return router;
}

// --- body helpers ------------------------------------------------------------

function requireString(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  if (typeof value !== 'string' || value.length === 0) {
    throw ApiError.badRequest(`${key} is required.`);
  }
  return value;
}

function requireInt(body: Record<string, unknown>, key: string): number {
  const value = body[key];
  if (typeof value !== 'number' || Number.isNaN(value)) {
    throw ApiError.badRequest(`${key} is required.`);
  }
  return Math.trunc(value);
}
