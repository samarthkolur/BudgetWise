import 'package:budgetwise/core/budget/budget_math.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/features/budget/domain/models.dart';

enum InsightTone { info, warning, celebration }

class Insight {
  const Insight({
    required this.kind,
    required this.tone,
    required this.title,
    required this.body,
  });

  final String kind;
  final InsightTone tone;
  final String title;
  final String body;
}

/// Turns a month's numbers into sentences.
///
/// The PRD asks for meaningful observations rather than raw graphs, so every
/// rule states a fact and its consequence — "you're at 82% of Food with 12 days
/// left" rather than a bar at 82%. Pure and deterministic: the same month always
/// produces the same insights, which is what makes them testable.
///
/// Ordered by usefulness, not severity: an overspend the user can still act on
/// matters more than one they cannot.
List<Insight> generateInsights({
  required BudgetSummary summary,
  required List<CategorySpend> categories,
  List<BudgetSummary> history = const [],
  List<CategorySpend> lastMonthCategories = const [],
  DateTime? now,
}) {
  final insights = <Insight>[];
  final daysLeft = summary.period.daysRemaining(now: now);
  final daysElapsed = summary.period.daysElapsed(now: now);

  // 1. Pace. The single most actionable number mid-month: are they spending
  //    faster than the month is passing?
  if (daysElapsed >= 3 && summary.spendable.isPositive) {
    final spentRatio = summary.spent.ratioOf(summary.spendable);
    final timeRatio = daysElapsed / summary.period.totalDays;

    if (spentRatio > timeRatio + 0.15) {
      final projected = Money(
        (summary.spent.minor / daysElapsed * summary.period.totalDays).round(),
      );
      insights.add(
        Insight(
          kind: 'pace_ahead',
          tone: InsightTone.warning,
          title: 'Spending is ahead of the month',
          body:
              "You've used ${(spentRatio * 100).toStringAsFixed(0)}% of your budget "
              'with ${(timeRatio * 100).toStringAsFixed(0)}% of the month gone. '
              'At this rate you would finish around ${projected.formatCompact()}.',
        ),
      );
    } else if (spentRatio < timeRatio - 0.15) {
      insights.add(
        Insight(
          kind: 'pace_behind',
          tone: InsightTone.celebration,
          title: "You're comfortably under",
          body:
              'Only ${(spentRatio * 100).toStringAsFixed(0)}% spent with '
              '$daysLeft ${daysLeft == 1 ? "day" : "days"} to go. '
              '${summary.remaining.formatCompact()} still available.',
        ),
      );
    }
  }

  // 2. Categories approaching or past their limit.
  for (final category in categories) {
    final progress = category.progress;
    if (progress.isExceeded) {
      insights.add(
        Insight(
          kind: 'category_exceeded',
          tone: InsightTone.warning,
          title: '${category.name} is over budget',
          body:
              '${progress.overspend.formatCompact()} past its '
              '${category.allocated.formatCompact()} allocation.',
        ),
      );
    } else if (progress.status == CategoryStatus.warning && daysLeft > 3) {
      insights.add(
        Insight(
          kind: 'category_warning',
          tone: InsightTone.warning,
          title:
              '${category.name} is at ${(progress.ratio * 100).toStringAsFixed(0)}%',
          body:
              '${progress.remaining.formatCompact()} left with $daysLeft '
              '${daysLeft == 1 ? "day" : "days"} to go.',
        ),
      );
    }
  }

  // 3. Month-on-month movement, only where it is large enough to mean something.
  if (lastMonthCategories.isNotEmpty) {
    final previous = {for (final c in lastMonthCategories) c.key: c.spent};
    for (final category in categories) {
      final before = previous[category.key];
      if (before == null || before.isZero || category.spent.isZero) continue;

      final change = (category.spent.minor - before.minor) / before.minor;
      if (change.abs() < 0.25) continue;

      insights.add(
        Insight(
          kind: 'category_trend',
          tone: change > 0 ? InsightTone.info : InsightTone.celebration,
          title:
              '${category.name} is ${change > 0 ? "up" : "down"} '
              '${(change.abs() * 100).toStringAsFixed(0)}%',
          body:
              '${category.spent.formatCompact()} this month against '
              '${before.formatCompact()} last month.',
        ),
      );
    }
  }

  // 4. Savings — the behaviour the product exists to build, so it is called out
  //    whether or not it went well.
  if (!summary.savingsTarget.isZero) {
    if (summary.savingsOutstanding.isZero) {
      insights.add(
        Insight(
          kind: 'savings_complete',
          tone: InsightTone.celebration,
          title: 'Savings done for ${summary.period.shortLabel}',
          body:
              '${summary.savedActual.formatCompact()} set aside before spending '
              'started. That is the habit working.',
        ),
      );
    } else if (daysLeft <= 7) {
      insights.add(
        Insight(
          kind: 'savings_pending',
          tone: InsightTone.warning,
          title: 'Savings still pending',
          body:
              '${summary.savingsOutstanding.formatCompact()} left to move with '
              'only $daysLeft ${daysLeft == 1 ? "day" : "days"} of the month remaining.',
        ),
      );
    }
  }

  // 5. Logging consistency. The app can only help with money it hears about.
  if (daysElapsed >= 7) {
    final loggedRatio = summary.daysWithExpenses / daysElapsed;
    if (loggedRatio < 0.3) {
      insights.add(
        Insight(
          kind: 'logging_sparse',
          tone: InsightTone.info,
          title: 'Some days are missing',
          body:
              'You logged expenses on ${summary.daysWithExpenses} of $daysElapsed days. '
              'The numbers here are only as good as what goes in.',
        ),
      );
    }
  }

  // 6. A quiet month with nothing to report still gets one line, because an
  //    empty insights screen looks broken.
  if (insights.isEmpty) {
    insights.add(
      Insight(
        kind: 'on_track',
        tone: InsightTone.celebration,
        title: 'Nothing needs your attention',
        body: 'Spending is in line with your plan for ${summary.period.label}.',
      ),
    );
  }

  return insights;
}

/// Compares a month against the one before it, for the trend strip.
class MonthComparison {
  const MonthComparison({
    required this.period,
    required this.spent,
    required this.spendable,
  });

  final Period period;
  final Money spent;
  final Money spendable;

  double get ratio => spent.ratioOf(spendable).clamp(0.0, 1.5);
}
