import 'package:budgetwise_domain/src/money.dart';

/// The raw behaviour a month's score is computed from.
///
/// Deliberately not a database row: the score is a pure function of these
/// inputs, which is what lets it be tested against fixtures instead of against
/// a seeded Postgres.
class HealthScoreInput {
  const HealthScoreInput({
    required this.savingsTarget,
    required this.savingsActual,
    required this.totalAllocated,
    required this.totalSpent,
    required this.categoriesExceeded,
    required this.categoryCount,
    required this.daysWithExpenses,
    required this.daysElapsed,
    this.goalTargetThisMonth = const Money.zero(),
    this.goalContributed = const Money.zero(),
    this.investingUnlocked = false,
    this.investmentTarget = const Money.zero(),
    this.investmentActual = const Money.zero(),
  });

  final Money savingsTarget;
  final Money savingsActual;
  final Money totalAllocated;
  final Money totalSpent;
  final int categoriesExceeded;
  final int categoryCount;
  final int daysWithExpenses;
  final int daysElapsed;
  final Money goalTargetThisMonth;
  final Money goalContributed;
  final bool investingUnlocked;
  final Money investmentTarget;
  final Money investmentActual;
}

/// One weighted component of the score, kept individually so the UI can explain
/// the number rather than just show it. A score a user cannot act on is a
/// grade, and the PRD asked for motivation, not grading.
class ScoreComponent {
  const ScoreComponent({
    required this.key,
    required this.label,
    required this.earned,
    required this.available,
  });

  final String key;
  final String label;
  final double earned;
  final double available;

  double get ratio => available == 0 ? 0 : earned / available;
}

class HealthScore {
  const HealthScore({required this.score, required this.components});

  /// 0–100.
  final int score;
  final List<ScoreComponent> components;

  /// Bands used for the summary line. Thresholds are deliberately generous at
  /// the bottom: someone scoring 45 in their first month needs encouragement,
  /// not a failing grade.
  String get band {
    if (score >= 85) return 'Excellent';
    if (score >= 70) return 'Strong';
    if (score >= 50) return 'Building';
    return 'Getting started';
  }
}

const _weightSavings = 30.0;
const _weightAdherence = 25.0;
const _weightLogging = 15.0;
const _weightOverspend = 15.0;
const _weightGoals = 10.0;
const _weightInvestment = 5.0;

/// Scores a month's financial discipline out of 100.
///
/// The score rewards consistency, never income — a student saving ₹500 of
/// ₹5,000 scores exactly what a salaried user saving ₹5,000 of ₹50,000 does.
/// Every component is a ratio of achieved-to-intended, so the only way to move
/// the number is to do what you said you would.
///
/// While investing is locked, its 5 points are not simply lost: the remaining
/// components are rescaled to 100, so a locked user is not permanently capped
/// at 95 for a feature they have not been given access to yet.
HealthScore computeHealthScore(HealthScoreInput input) {
  // Spending at or under the plan. Spending far under is not penalised; the
  // plan is a ceiling, not a quota.
  final adherence = input.totalAllocated.isZero
      ? 1.0
      : 1 -
            (input.totalSpent.ratioOf(input.totalAllocated) - 1).clamp(
              0.0,
              1.0,
            );

  // The app cannot help with money it never hears about.
  final loggingRatio = input.daysElapsed <= 0
      ? 1.0
      : (input.daysWithExpenses / input.daysElapsed).clamp(0.0, 1.0);

  // Proportion of categories kept inside their limit.
  final overspendRatio = input.categoryCount <= 0
      ? 1.0
      : 1 - (input.categoriesExceeded / input.categoryCount).clamp(0.0, 1.0);

  final components = <ScoreComponent>[
    // The heaviest weight, because it is the behaviour the whole product
    // exists to build.
    ScoreComponent(
      key: 'savings_completion',
      label: 'Savings completed',
      earned: input.savingsTarget.isZero
          ? _weightSavings
          : _weightSavings *
                input.savingsActual
                    .ratioOf(input.savingsTarget)
                    .clamp(0.0, 1.0),
      available: _weightSavings,
    ),
    ScoreComponent(
      key: 'category_adherence',
      label: 'Stayed within budget',
      earned: _weightAdherence * adherence,
      available: _weightAdherence,
    ),
    ScoreComponent(
      key: 'logging_consistency',
      label: 'Recorded expenses regularly',
      earned: _weightLogging * loggingRatio,
      available: _weightLogging,
    ),
    ScoreComponent(
      key: 'overspend_avoidance',
      label: 'Avoided overspending',
      earned: _weightOverspend * overspendRatio,
      available: _weightOverspend,
    ),
    // A user with no goals is not penalised for not having any — goals are
    // optional, and scoring their absence would push people into creating
    // goals they do not want.
    ScoreComponent(
      key: 'goal_progress',
      label: 'Progress toward goals',
      earned: input.goalTargetThisMonth.isZero
          ? _weightGoals
          : _weightGoals *
                input.goalContributed
                    .ratioOf(input.goalTargetThisMonth)
                    .clamp(0.0, 1.0),
      available: _weightGoals,
    ),
    if (input.investingUnlocked)
      ScoreComponent(
        key: 'investment_completion',
        label: 'Investment completed',
        earned: input.investmentTarget.isZero
            ? _weightInvestment
            : _weightInvestment *
                  input.investmentActual
                      .ratioOf(input.investmentTarget)
                      .clamp(0.0, 1.0),
        available: _weightInvestment,
      ),
  ];

  final earned = components.fold<double>(0, (a, c) => a + c.earned);
  final available = components.fold<double>(0, (a, c) => a + c.available);
  final score = available == 0 ? 0 : (earned / available * 100).round();

  return HealthScore(score: score.clamp(0, 100), components: components);
}
