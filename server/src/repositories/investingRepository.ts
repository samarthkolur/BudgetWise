import type { Investment, PrismaClient } from '@prisma/client';
import { NotPermittedError, ValidationError } from '../http/errors';
import { assertOwnsBudget } from './ownership';
import { isPositive } from '../domain/money';
import { evaluateInvestingUnlock, SavingsMonth } from '../domain/investingUnlock';
import { averageMonthlySpend } from './expenseRepository';
import { Period } from '../domain/period';

export interface ClaimUnlockResult {
  isUnlocked: boolean;
  newlyUnlocked: boolean;
  streakMonths: number;
  fundRatio: number;
}

export interface RecordInvestmentInput {
  budgetId: string;
  amountMinor: number;
  instrument?: string | null;
  note?: string | null;
}

/**
 * The investing gate. Ported from
 * server/lib/src/repositories/investing_repository.dart. `recordInvestment`
 * is the only path that writes an investment, and it re-checks the gate
 * itself rather than trusting a client-reported "unlocked" flag.
 */
async function history(prisma: PrismaClient, userId: string): Promise<SavingsMonth[]> {
  const budgets = await prisma.budget.findMany({
    where: { userId },
    orderBy: { period: 'desc' },
  });

  const months: SavingsMonth[] = [];
  for (const budget of budgets) {
    const agg = await prisma.savingsEntry.aggregate({
      where: { budgetId: budget.id },
      _sum: { amountMinor: true },
    });
    const period = Period.fromDate(budget.period);
    months.push({
      period: { year: period.year, month: period.month },
      targetMinor: budget.savingsTargetMinor,
      actualMinor: agg._sum.amountMinor ?? 0,
    });
  }
  return months;
}

/**
 * Evaluates the gate and stamps the unlock the first time it is earned.
 * `newlyUnlocked` is true only on the call that earned it. Unlocking is
 * permanent: once `investingUnlockedAt` is set, later calls short-circuit.
 */
export async function claimUnlock(prisma: PrismaClient, userId: string): Promise<ClaimUnlockResult> {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  const already = user?.investingUnlockedAt ?? null;

  const monthHistory = await history(prisma, userId);
  const totalSavedAgg = await prisma.savingsEntry.aggregate({
    where: { userId },
    _sum: { amountMinor: true },
  });
  const totalSavedMinor = totalSavedAgg._sum.amountMinor ?? 0;

  // Total spend stands in for "essentials" now that there are no categories
  // to isolate essentials from the rest.
  const essentials = await averageMonthlySpend(prisma, userId);

  const status = evaluateInvestingUnlock({
    history: monthHistory,
    totalSavedMinor,
    averageMonthlyEssentialsMinor: essentials,
    wasPreviouslyUnlocked: already != null,
  });

  const newlyUnlocked = already == null && status.isUnlocked;
  if (newlyUnlocked) {
    await prisma.user.update({
      where: { id: userId },
      data: { investingUnlockedAt: new Date() },
    });
  }

  return {
    isUnlocked: status.isUnlocked,
    newlyUnlocked,
    streakMonths: status.streakMonths,
    fundRatio: status.emergencyFundRatio,
  };
}

export async function isUnlocked(prisma: PrismaClient, userId: string): Promise<boolean> {
  const result = await claimUnlock(prisma, userId);
  return result.isUnlocked;
}

export async function recordInvestment(
  prisma: PrismaClient,
  userId: string,
  input: RecordInvestmentInput,
): Promise<Investment> {
  if (!isPositive(input.amountMinor)) {
    throw new ValidationError('Enter an amount greater than zero');
  }
  await assertOwnsBudget(prisma, userId, input.budgetId);

  if (!(await isUnlocked(prisma, userId))) {
    throw new NotPermittedError(
      'Investing unlocks after six months of consistent saving, or once you have ' +
        'three months of essentials set aside.',
    );
  }

  return prisma.investment.create({
    data: {
      userId,
      budgetId: input.budgetId,
      amountMinor: input.amountMinor,
      instrument: input.instrument ?? 'other',
      investedOn: new Date(),
      note: input.note ?? null,
    },
  });
}
