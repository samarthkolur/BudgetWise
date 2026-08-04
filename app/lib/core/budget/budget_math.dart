import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/core/time/period.dart';

/// How a category is doing against its allocation.
///
/// The PRD asks for green → yellow → red *before* overspending occurs, so the
/// amber band starts at 75% rather than at the limit. A warning that arrives
/// the moment the money is gone is not a warning.
enum CategoryStatus {
  healthy,
  warning,
  exceeded;

  static CategoryStatus forRatio(double ratio) {
    if (ratio >= 1.0) return CategoryStatus.exceeded;
    if (ratio >= 0.75) return CategoryStatus.warning;
    return CategoryStatus.healthy;
  }
}

/// The dashboard's answer to "how much can I safely spend today?".
class SafeDailySpend {
  const SafeDailySpend({
    required this.perDay,
    required this.remaining,
    required this.daysRemaining,
  });

  final Money perDay;
  final Money remaining;
  final int daysRemaining;

  bool get isExhausted => remaining.isZero || remaining.isNegative;
}

/// Divides what is left across the days that are left.
///
/// Floors to the rupee: telling someone they may spend ₹283.47 today invites
/// them to spend ₹284, and the rounding error compounds across a month. Better
/// to under-promise by a few paise a day.
SafeDailySpend safeDailySpend({
  required Money remaining,
  required Period period,
  DateTime? now,
}) {
  final days = period.daysRemaining(now: now);
  final safe = remaining.orZeroIfNegative;

  if (days <= 0) {
    return SafeDailySpend(
      perDay: const Money.zero(),
      remaining: safe,
      daysRemaining: 0,
    );
  }

  final perDayMinor = (safe.minor ~/ days ~/ 100) * 100;
  return SafeDailySpend(
    perDay: Money(perDayMinor),
    remaining: safe,
    daysRemaining: days,
  );
}

/// A category's position against its budget, in the terms the UI needs.
class CategoryProgress {
  const CategoryProgress({
    required this.allocated,
    required this.spent,
  });

  final Money allocated;
  final Money spent;

  Money get remaining => (allocated - spent).orZeroIfNegative;

  /// How far past the allocation this category has gone. Kept separate from
  /// [remaining] rather than encoded as a negative remainder — the PRD wants
  /// the overspend stated as its own number, not inferred from a minus sign.
  Money get overspend =>
      spent > allocated ? spent - allocated : const Money.zero();

  bool get isExceeded => spent > allocated;

  double get ratio => spent.ratioOf(allocated);

  /// Clamped for progress bars, which cannot render 140%.
  double get displayRatio => ratio.clamp(0.0, 1.0);

  CategoryStatus get status => CategoryStatus.forRatio(ratio);
}

/// A suggestion for covering an overspent category from a surplus elsewhere.
///
/// The PRD asks the app to suggest adjustments rather than only report the
/// breach. This proposes the single largest surplus that can absorb it, which
/// is the smallest number of decisions the user has to make.
class ReallocationSuggestion {
  const ReallocationSuggestion({
    required this.fromKey,
    required this.amount,
    required this.availableAtSource,
  });

  final String fromKey;
  final Money amount;
  final Money availableAtSource;

  /// True when covering the overspend would consume the source's entire
  /// surplus, leaving that category with nothing spare of its own.
  bool get drainsSource => amount >= availableAtSource;
}

/// Finds the healthiest category with room to cover [overspend].
///
/// Returns null when no category has any surplus — in which case the honest
/// answer is that the month is over-committed, and inventing a source would be
/// worse than saying nothing.
ReallocationSuggestion? suggestReallocation({
  required Money overspend,
  required Map<String, CategoryProgress> categories,
  required String excludingKey,
}) {
  if (overspend.isZero || overspend.isNegative) return null;

  MapEntry<String, CategoryProgress>? best;
  for (final entry in categories.entries) {
    if (entry.key == excludingKey) continue;
    if (entry.value.remaining.isZero) continue;
    if (best == null || entry.value.remaining > best.value.remaining) {
      best = entry;
    }
  }
  if (best == null) return null;

  final available = best.value.remaining;
  final take = available >= overspend ? overspend : available;
  return ReallocationSuggestion(
    fromKey: best.key,
    amount: take,
    availableAtSource: available,
  );
}
