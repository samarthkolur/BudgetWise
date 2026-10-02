import type { Goal, PrismaClient } from '@prisma/client';
import { ValidationError } from '../http/errors';
import { assertOwnsGoal } from './ownership';
import { isPositive } from '../domain/money';

export interface CreateGoalInput {
  title: string;
  targetMinor: number;
  targetDate?: Date | null;
  monthlyContributionMinor?: number | null;
  icon?: string | null;
}

export interface ContributeInput {
  goalId: string;
  amountMinor: number;
  budgetId?: string | null;
}

/** Ported from server/lib/src/repositories/goal_repository.dart. */
export async function all(prisma: PrismaClient, userId: string): Promise<Goal[]> {
  return prisma.goal.findMany({ where: { userId }, orderBy: { createdAt: 'asc' } });
}

export async function create(
  prisma: PrismaClient,
  userId: string,
  input: CreateGoalInput,
): Promise<Goal> {
  if (!isPositive(input.targetMinor)) {
    throw new ValidationError('A goal needs a target above zero');
  }
  return prisma.goal.create({
    data: {
      userId,
      title: input.title.trim(),
      targetMinor: input.targetMinor,
      savedMinor: 0,
      targetDate: input.targetDate ? dateOnlyUtc(input.targetDate) : null,
      monthlyContributionMinor: input.monthlyContributionMinor ?? null,
      icon: input.icon ?? null,
      status: 'active',
    },
  });
}

/**
 * Adds money to a goal and recomputes its total from scratch — summing the
 * contributions rather than incrementing is what keeps a later-deleted
 * contribution from leaving the total permanently wrong.
 */
export async function contribute(
  prisma: PrismaClient,
  userId: string,
  input: ContributeInput,
): Promise<void> {
  if (!isPositive(input.amountMinor)) {
    throw new ValidationError('Enter an amount greater than zero');
  }
  await assertOwnsGoal(prisma, userId, input.goalId);

  await prisma.goalContribution.create({
    data: {
      userId,
      goalId: input.goalId,
      budgetId: input.budgetId ?? null,
      amountMinor: input.amountMinor,
      contributedOn: new Date(),
    },
  });

  await recomputeSaved(prisma, input.goalId);
}

async function recomputeSaved(prisma: PrismaClient, goalId: string): Promise<void> {
  const agg = await prisma.goalContribution.aggregate({
    where: { goalId },
    _sum: { amountMinor: true },
  });
  const total = agg._sum.amountMinor ?? 0;

  const goal = await prisma.goal.findUnique({ where: { id: goalId } });
  if (!goal) return;

  const status = goal.status === 'abandoned' ? 'abandoned' : total >= goal.targetMinor ? 'achieved' : 'active';

  await prisma.goal.update({
    where: { id: goalId },
    data: { savedMinor: total, status },
  });
}

export async function remove(prisma: PrismaClient, userId: string, goalId: string): Promise<boolean> {
  // Contributions cascade via FK (onDelete: Cascade).
  const result = await prisma.goal.deleteMany({ where: { id: goalId, userId } });
  return result.count > 0;
}

function dateOnlyUtc(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}
