import type { Budget, PrismaClient } from '@prisma/client';
import { ConflictError, ValidationError } from '../http/errors';
import { assertOwnsBudget } from './ownership';
import { Period } from '../domain/period';

export interface CreateMonthInput {
  period: Period;
  incomeMinor: number;
  savingsMode: string;
  savingsTargetMinor: number;
  savingsPercent?: number | null;
  investmentTargetMinor?: number | null;
  carriedFromPeriod?: Period | null;
}

export interface BudgetSummary {
  budgetId: string;
  period: Date;
  status: string;
  incomeMinor: number;
  savingsMode: string;
  savingsPercent: number | null;
  savingsTargetMinor: number;
  investmentTargetMinor: number | null;
  savingsConfirmedAt: Date | null;
  spentMinor: number;
  expenseCount: number;
  savedMinor: number;
  investedMinor: number;
  daysWithExpenses: number;
  spendableMinor: number;
  remainingMinor: number;
}

/**
 * Budgets and the derived views the dashboard reads. Ported from
 * server/lib/src/repositories/budget_repository.dart.
 *
 * `summaryFor` recomputes everything from the raw rows every time, the same
 * way the old Mongo version did — there is one place this arithmetic lives,
 * imported by nothing else, so "how much is left" cannot drift between two
 * implementations.
 */
export async function allBudgets(prisma: PrismaClient, userId: string): Promise<Budget[]> {
  return prisma.budget.findMany({ where: { userId }, orderBy: { period: 'desc' } });
}

export async function budgetForPeriod(
  prisma: PrismaClient,
  userId: string,
  period: Period,
): Promise<Budget | null> {
  return prisma.budget.findFirst({ where: { userId, period: period.toDate() } });
}

export async function createMonth(
  prisma: PrismaClient,
  userId: string,
  input: CreateMonthInput,
): Promise<Budget> {
  if (input.savingsTargetMinor > input.incomeMinor) {
    throw new ValidationError('Savings cannot be more than income');
  }

  const existing = await budgetForPeriod(prisma, userId, input.period);
  if (existing) {
    throw new ConflictError(`A plan already exists for ${input.period.isoDate}`);
  }

  return prisma.budget.create({
    data: {
      userId,
      period: input.period.toDate(),
      incomeMinor: input.incomeMinor,
      savingsMode: input.savingsMode,
      savingsPercent: input.savingsPercent ?? null,
      savingsTargetMinor: input.savingsTargetMinor,
      investmentTargetMinor: input.investmentTargetMinor ?? null,
      savingsConfirmedAt: null,
      status: 'active',
      carriedFromPeriod: input.carriedFromPeriod ? input.carriedFromPeriod.toDate() : null,
    },
  });
}

export async function summaryFor(prisma: PrismaClient, budget: Budget): Promise<BudgetSummary> {
  const [spentAgg, savedAgg, investedAgg, expenseCount, daysWithExpenses] = await Promise.all([
    prisma.expense.aggregate({
      where: { budgetId: budget.id },
      _sum: { amountMinor: true },
    }),
    prisma.savingsEntry.aggregate({
      where: { budgetId: budget.id },
      _sum: { amountMinor: true },
    }),
    prisma.investment.aggregate({
      where: { budgetId: budget.id },
      _sum: { amountMinor: true },
    }),
    prisma.expense.count({ where: { budgetId: budget.id } }),
    distinctExpenseDays(prisma, budget.id),
  ]);

  const spent = spentAgg._sum.amountMinor ?? 0;
  const saved = savedAgg._sum.amountMinor ?? 0;
  const invested = investedAgg._sum.amountMinor ?? 0;

  const spendableRaw =
    budget.incomeMinor - budget.savingsTargetMinor - (budget.investmentTargetMinor ?? 0);
  const spendable = Math.max(0, spendableRaw);
  const remaining = Math.max(0, spendable - spent);

  return {
    budgetId: budget.id,
    period: budget.period,
    status: budget.status,
    incomeMinor: budget.incomeMinor,
    savingsMode: budget.savingsMode,
    savingsPercent: budget.savingsPercent,
    savingsTargetMinor: budget.savingsTargetMinor,
    investmentTargetMinor: budget.investmentTargetMinor,
    savingsConfirmedAt: budget.savingsConfirmedAt,
    spentMinor: spent,
    expenseCount,
    savedMinor: saved,
    investedMinor: invested,
    daysWithExpenses,
    spendableMinor: spendable,
    remainingMinor: remaining,
  };
}

export async function summaryForPeriod(
  prisma: PrismaClient,
  userId: string,
  period: Period,
): Promise<BudgetSummary | null> {
  const budget = await budgetForPeriod(prisma, userId, period);
  if (!budget) return null;
  return summaryFor(prisma, budget);
}

export async function allSummaries(prisma: PrismaClient, userId: string): Promise<BudgetSummary[]> {
  const budgets = await allBudgets(prisma, userId);
  return Promise.all(budgets.map((b) => summaryFor(prisma, b)));
}

/**
 * Records that the user moved their savings. Writes the entry AND stamps
 * `savingsConfirmedAt` — both matter: the stamp drives a UI reminder, the
 * entry is what the savings-streak calculation reads.
 */
export async function confirmSavings(
  prisma: PrismaClient,
  userId: string,
  budgetId: string,
  amountMinor: number,
  destination = 'bank',
): Promise<void> {
  await assertOwnsBudget(prisma, userId, budgetId);
  await prisma.$transaction([
    prisma.savingsEntry.create({
      data: {
        userId,
        budgetId,
        amountMinor,
        savedOn: new Date(),
        destination,
      },
    }),
    prisma.budget.update({
      where: { id: budgetId },
      data: { savingsConfirmedAt: new Date() },
    }),
  ]);
}

async function distinctExpenseDays(prisma: PrismaClient, budgetId: string): Promise<number> {
  const rows = await prisma.expense.findMany({
    where: { budgetId },
    select: { spentOn: true },
    distinct: ['spentOn'],
  });
  return rows.length;
}
