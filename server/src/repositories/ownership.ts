import type { PrismaClient } from '@prisma/client';
import { NotOwnedError } from '../http/errors';

/**
 * The ownership-scoping layer — the replacement for
 * server/lib/src/db/owned_collection.dart's `owns()` check.
 *
 * Postgres foreign keys make an orphaned budgetId impossible, but they do
 * **not** stop "this budgetId is real but belongs to someone else" — so
 * every repository calls one of these before a cross-parent write. This is
 * exactly the attack server/test/isolation.test.ts exists to catch.
 */
export async function assertOwnsBudget(
  prisma: PrismaClient,
  userId: string,
  budgetId: string,
): Promise<void> {
  const budget = await prisma.budget.findFirst({ where: { id: budgetId, userId } });
  if (!budget) throw new NotOwnedError('budget');
}

export async function assertOwnsGoal(
  prisma: PrismaClient,
  userId: string,
  goalId: string,
): Promise<void> {
  const goal = await prisma.goal.findFirst({ where: { id: goalId, userId } });
  if (!goal) throw new NotOwnedError('goal');
}
