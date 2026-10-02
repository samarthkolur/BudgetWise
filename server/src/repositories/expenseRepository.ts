import type { Expense, PrismaClient } from '@prisma/client';
import { ValidationError } from '../http/errors';
import { assertOwnsBudget } from './ownership';
import { Period } from '../domain/period';
import { isPositive } from '../domain/money';

export interface AddExpenseInput {
  budgetId: string;
  amountMinor: number;
  spentOn: Date;
  paymentMethod: string;
  note?: string | null;
}

export interface UpdateExpenseInput {
  amountMinor: number;
  spentOn: Date;
  paymentMethod: string;
  note?: string | null;
}

/** Ported from server/lib/src/repositories/expense_repository.dart. */
export async function forBudget(
  prisma: PrismaClient,
  userId: string,
  budgetId: string,
): Promise<Expense[]> {
  await assertOwnsBudget(prisma, userId, budgetId);
  return prisma.expense.findMany({
    where: { budgetId, userId },
    orderBy: [{ spentOn: 'desc' }, { createdAt: 'desc' }],
  });
}

/**
 * Adds an expense. The parent budget is checked before the write — Postgres
 * foreign keys stop an orphaned budgetId, but not "this budgetId is real but
 * belongs to someone else"; `assertOwnsBudget` is the entire defence for
 * that, and the cross-user test asserts it directly.
 */
export async function add(
  prisma: PrismaClient,
  userId: string,
  input: AddExpenseInput,
): Promise<Expense> {
  if (!isPositive(input.amountMinor)) {
    throw new ValidationError('Enter an amount greater than zero');
  }
  await assertOwnsBudget(prisma, userId, input.budgetId);

  return prisma.expense.create({
    data: {
      userId,
      budgetId: input.budgetId,
      amountMinor: input.amountMinor,
      spentOn: dateOnlyUtc(input.spentOn),
      paymentMethod: input.paymentMethod,
      note: normalizeNote(input.note),
    },
  });
}

export async function update(
  prisma: PrismaClient,
  userId: string,
  expenseId: string,
  input: UpdateExpenseInput,
): Promise<Expense | null> {
  if (!isPositive(input.amountMinor)) {
    throw new ValidationError('Enter an amount greater than zero');
  }
  const existing = await prisma.expense.findFirst({ where: { id: expenseId, userId } });
  if (!existing) return null;

  return prisma.expense.update({
    where: { id: expenseId },
    data: {
      amountMinor: input.amountMinor,
      spentOn: dateOnlyUtc(input.spentOn),
      paymentMethod: input.paymentMethod,
      note: normalizeNote(input.note),
    },
  });
}

export async function remove(prisma: PrismaClient, userId: string, expenseId: string): Promise<boolean> {
  const result = await prisma.expense.deleteMany({ where: { id: expenseId, userId } });
  return result.count > 0;
}

/**
 * Average total monthly spend, across completed months only. The current
 * month is excluded because it is partial and would understate the average.
 * Integer division (truncated), matching `Money(total ~/ rows.length)` in
 * the Dart version.
 */
export async function averageMonthlySpend(prisma: PrismaClient, userId: string): Promise<number> {
  const budgets = await prisma.budget.findMany({ where: { userId } });
  const current = Period.current();
  const completedIds = budgets
    .filter((b) => Period.fromDate(b.period).isBefore(current))
    .map((b) => b.id);

  if (completedIds.length === 0) return 0;

  const rows = await prisma.expense.groupBy({
    by: ['budgetId'],
    where: { userId, budgetId: { in: completedIds } },
    _sum: { amountMinor: true },
  });
  if (rows.length === 0) return 0;

  const total = rows.reduce((sum, r) => sum + (r._sum.amountMinor ?? 0), 0);
  return Math.trunc(total / rows.length);
}

function dateOnlyUtc(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function normalizeNote(note: string | null | undefined): string | null {
  if (!note) return null;
  const trimmed = note.trim();
  return trimmed.length === 0 ? null : trimmed;
}
