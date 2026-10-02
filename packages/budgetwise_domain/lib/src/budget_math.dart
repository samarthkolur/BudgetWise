import 'package:budgetwise_domain/src/money.dart';
import 'package:budgetwise_domain/src/period.dart';

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
