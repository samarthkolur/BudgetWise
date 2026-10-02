/**
 * The investing gate. Ported exactly from
 * packages/budgetwise_domain/lib/src/investing_unlock.dart.
 *
 * Either route unlocks: six consecutive months of meeting the savings
 * target, or an emergency fund covering three months of essentials.
 * Unlocking is permanent — `wasPreviouslyUnlocked` short-circuits the
 * calculation so a later broken streak never re-locks it.
 */

export const REQUIRED_STREAK_MONTHS = 6;
export const EMERGENCY_FUND_MONTHS = 3;

export interface YearMonth {
  year: number;
  month: number; // 1-12
}

export interface SavingsMonth {
  period: YearMonth;
  targetMinor: number;
  actualMinor: number;
}

export type UnlockRoute = 'savingsStreak' | 'emergencyFund' | null;

export interface InvestingStatus {
  isUnlocked: boolean;
  streakMonths: number;
  emergencyFundRatio: number;
  unlockedBy: UnlockRoute;
}

function isSuccessful(month: SavingsMonth): boolean {
  return month.targetMinor > 0 && month.actualMinor >= month.targetMinor;
}

function previousMonth(ym: YearMonth): YearMonth {
  const zeroBased = ym.month - 1 - 1; // to 0-based, then step back one
  const y = ym.year + Math.floor(zeroBased / 12);
  const m = ((zeroBased % 12) + 12) % 12;
  return { year: y, month: m + 1 };
}

function keyOf(ym: YearMonth): string {
  return `${ym.year}-${ym.month}`;
}

/**
 * Counts consecutive successful months walking backward from the month
 * immediately before `asOf` (default: current calendar month). The current
 * month is always excluded — it's still in progress.
 */
export function savingsStreak(history: SavingsMonth[], asOf?: YearMonth): number {
  if (history.length === 0) return 0;

  const current = asOf ?? toYearMonth(new Date());
  const byPeriod = new Map<string, SavingsMonth>();
  for (const m of history) byPeriod.set(keyOf(m.period), m);

  let cursor = previousMonth(current);
  let streak = 0;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const month = byPeriod.get(keyOf(cursor));
    if (!month || !isSuccessful(month)) break;
    streak++;
    cursor = previousMonth(cursor);
  }
  return streak;
}

/**
 * Total saved, against three months of average essential spend. 0 when
 * averageMonthlyEssentialsMinor is 0 — an unknown denominator must not read
 * as a satisfied cushion.
 */
export function emergencyFundRatio(
  totalSavedMinor: number,
  averageMonthlyEssentialsMinor: number,
): number {
  if (averageMonthlyEssentialsMinor === 0) return 0;
  const required = averageMonthlyEssentialsMinor * EMERGENCY_FUND_MONTHS;
  return required === 0 ? 0 : totalSavedMinor / required;
}

export interface EvaluateInvestingUnlockOptions {
  history: SavingsMonth[];
  totalSavedMinor: number;
  averageMonthlyEssentialsMinor: number;
  wasPreviouslyUnlocked: boolean;
  asOf?: YearMonth;
}

export function evaluateInvestingUnlock(
  opts: EvaluateInvestingUnlockOptions,
): InvestingStatus {
  const streak = savingsStreak(opts.history, opts.asOf);
  const ratio = emergencyFundRatio(opts.totalSavedMinor, opts.averageMonthlyEssentialsMinor);

  if (opts.wasPreviouslyUnlocked) {
    return {
      isUnlocked: true,
      streakMonths: streak,
      emergencyFundRatio: ratio,
      unlockedBy: null,
    };
  }

  const byStreak = streak >= REQUIRED_STREAK_MONTHS;
  const byFund = ratio >= 1.0;

  return {
    isUnlocked: byStreak || byFund,
    streakMonths: streak,
    emergencyFundRatio: ratio,
    unlockedBy: byStreak ? 'savingsStreak' : byFund ? 'emergencyFund' : null,
  };
}

function toYearMonth(date: Date): YearMonth {
  return { year: date.getFullYear(), month: date.getMonth() + 1 };
}
