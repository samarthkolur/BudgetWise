import 'package:budgetwise_domain/src/money.dart';
import 'package:budgetwise_domain/src/period.dart';

/// One completed month's savings record, as the streak calculation sees it.
class SavingsMonth {
  const SavingsMonth({
    required this.period,
    required this.target,
    required this.actual,
  });

  final Period period;
  final Money target;
  final Money actual;

  /// A month counts toward the streak when the user saved what they set out to
  /// save. A target of zero does not count — skipping the commitment is not the
  /// same as keeping it.
  bool get isSuccessful => !target.isZero && actual >= target;
}

/// Months of consecutive successful saving required to unlock investing.
const kRequiredStreakMonths = 6;

/// Months of essential expenses an emergency fund must cover as the alternative
/// route. Standard personal-finance advice, and the PRD's stated threshold.
const kEmergencyFundMonths = 3;

class InvestingStatus {
  const InvestingStatus({
    required this.isUnlocked,
    required this.streakMonths,
    required this.emergencyFundRatio,
    required this.unlockedBy,
  });

  final bool isUnlocked;
  final int streakMonths;

  /// Emergency fund as a multiple of the required 3-month cushion. 1.0 means
  /// the cushion is exactly met.
  final double emergencyFundRatio;

  final UnlockRoute? unlockedBy;

  int get monthsRemaining =>
      (kRequiredStreakMonths - streakMonths).clamp(0, kRequiredStreakMonths);

  /// Progress toward whichever route is closer, for the locked-state indicator.
  double get progress {
    final byStreak = streakMonths / kRequiredStreakMonths;
    final byFund = emergencyFundRatio;
    return (byStreak > byFund ? byStreak : byFund).clamp(0.0, 1.0);
  }
}

enum UnlockRoute { savingsStreak, emergencyFund }

/// Counts consecutive successful months ending at the most recent **completed**
/// month.
///
/// The current month is excluded on purpose: it is still in progress, and a
/// streak that counts an unfinished month would break the moment the user
/// looked at it on the 2nd.
int savingsStreak(List<SavingsMonth> history, {Period? asOf}) {
  if (history.isEmpty) return 0;

  final current = asOf ?? Period.current();
  final byPeriod = {for (final m in history) m.period: m};

  var cursor = current.previous;
  var streak = 0;
  while (true) {
    final month = byPeriod[cursor];
    if (month == null || !month.isSuccessful) break;
    streak++;
    cursor = cursor.previous;
  }
  return streak;
}

/// Total saved, against three months of average essential spend.
///
/// Returns 0 when there is no essential-spend history to compare against —
/// an unknown denominator must not read as a satisfied cushion.
double emergencyFundRatio({
  required Money totalSaved,
  required Money averageMonthlyEssentials,
}) {
  if (averageMonthlyEssentials.isZero) return 0;
  final required = averageMonthlyEssentials * kEmergencyFundMonths;
  return totalSaved.ratioOf(required);
}

/// Decides whether investing features are available.
///
/// Either route unlocks: six consecutive months of meeting the savings target,
/// or an emergency fund covering three months of essentials. Both are ways of
/// demonstrating the same thing — that saving has become a habit rather than a
/// leftover.
///
/// **Unlocking is permanent.** [wasPreviouslyUnlocked] short-circuits the
/// calculation, so a user who later breaks a streak keeps access. The PRD
/// frames this as an achievement to celebrate; taking it back would make it a
/// punishment the product never warned about.
InvestingStatus evaluateInvestingUnlock({
  required List<SavingsMonth> history,
  required Money totalSaved,
  required Money averageMonthlyEssentials,
  bool wasPreviouslyUnlocked = false,
  Period? asOf,
}) {
  final streak = savingsStreak(history, asOf: asOf);
  final ratio = emergencyFundRatio(
    totalSaved: totalSaved,
    averageMonthlyEssentials: averageMonthlyEssentials,
  );

  if (wasPreviouslyUnlocked) {
    return InvestingStatus(
      isUnlocked: true,
      streakMonths: streak,
      emergencyFundRatio: ratio,
      unlockedBy: null,
    );
  }

  final byStreak = streak >= kRequiredStreakMonths;
  final byFund = ratio >= 1.0;

  return InvestingStatus(
    isUnlocked: byStreak || byFund,
    streakMonths: streak,
    emergencyFundRatio: ratio,
    unlockedBy: byStreak
        ? UnlockRoute.savingsStreak
        : byFund
        ? UnlockRoute.emergencyFund
        : null,
  );
}
