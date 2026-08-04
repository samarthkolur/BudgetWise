import 'package:budgetwise/core/budget/health_score.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

HealthScoreInput _input({
  Money savingsTarget = const Money(1000000),
  Money savingsActual = const Money(1000000),
  Money totalAllocated = const Money(4000000),
  Money totalSpent = const Money(3500000),
  int categoriesExceeded = 0,
  int categoryCount = 5,
  int daysWithExpenses = 30,
  int daysElapsed = 30,
  bool investingUnlocked = false,
  Money investmentTarget = const Money.zero(),
  Money investmentActual = const Money.zero(),
  Money goalTarget = const Money.zero(),
  Money goalContributed = const Money.zero(),
}) => HealthScoreInput(
  savingsTarget: savingsTarget,
  savingsActual: savingsActual,
  totalAllocated: totalAllocated,
  totalSpent: totalSpent,
  categoriesExceeded: categoriesExceeded,
  categoryCount: categoryCount,
  daysWithExpenses: daysWithExpenses,
  daysElapsed: daysElapsed,
  investingUnlocked: investingUnlocked,
  investmentTarget: investmentTarget,
  investmentActual: investmentActual,
  goalTargetThisMonth: goalTarget,
  goalContributed: goalContributed,
);

void main() {
  group('computeHealthScore', () {
    test('a perfect month scores 100', () {
      expect(computeHealthScore(_input()).score, 100);
    });

    test('rewards discipline, not income', () {
      // A student on ₹5,000 and a professional on ₹50,000, both saving 20% and
      // both staying inside budget, must score identically.
      final student = computeHealthScore(
        _input(
          savingsTarget: Money.fromRupees(1000),
          savingsActual: Money.fromRupees(1000),
          totalAllocated: Money.fromRupees(4000),
          totalSpent: Money.fromRupees(3500),
        ),
      );
      final professional = computeHealthScore(
        _input(
          savingsTarget: Money.fromRupees(10000),
          savingsActual: Money.fromRupees(10000),
          totalAllocated: Money.fromRupees(40000),
          totalSpent: Money.fromRupees(35000),
        ),
      );
      expect(student.score, professional.score);
    });

    test('missing the savings target costs the heaviest component', () {
      final half = computeHealthScore(
        _input(savingsActual: const Money(500000)),
      );
      expect(half.score, lessThan(100));
      final savings = half.components.firstWhere(
        (c) => c.key == 'savings_completion',
      );
      expect(savings.ratio, closeTo(0.5, 0.001));
    });

    test('spending under the plan is never penalised', () {
      final frugal = computeHealthScore(
        _input(totalSpent: const Money(1000000)),
      );
      final exact = computeHealthScore(
        _input(totalSpent: const Money(4000000)),
      );
      expect(frugal.score, exact.score);
    });

    test(
      'exceeded categories reduce the overspend component proportionally',
      () {
        final result = computeHealthScore(
          _input(categoriesExceeded: 2, categoryCount: 4),
        );
        final component = result.components.firstWhere(
          (c) => c.key == 'overspend_avoidance',
        );
        expect(component.ratio, closeTo(0.5, 0.001));
      },
    );

    test('sporadic logging reduces the score', () {
      final result = computeHealthScore(_input(daysWithExpenses: 6));
      final component = result.components.firstWhere(
        (c) => c.key == 'logging_consistency',
      );
      expect(component.ratio, closeTo(0.2, 0.001));
    });

    test('having no goals is not a penalty', () {
      final withoutGoals = computeHealthScore(_input());
      final goalComponent = withoutGoals.components.firstWhere(
        (c) => c.key == 'goal_progress',
      );
      expect(goalComponent.ratio, 1.0);
    });

    test('locked investing rescales rather than capping the score at 95', () {
      final locked = computeHealthScore(_input());
      expect(locked.score, 100);
      expect(
        locked.components.any((c) => c.key == 'investment_completion'),
        isFalse,
      );

      final unlocked = computeHealthScore(
        _input(
          investingUnlocked: true,
          investmentTarget: const Money(500000),
          investmentActual: const Money(500000),
        ),
      );
      expect(unlocked.score, 100);
      expect(
        unlocked.components.any((c) => c.key == 'investment_completion'),
        isTrue,
      );
    });

    test('is deterministic for identical input', () {
      final a = computeHealthScore(_input(savingsActual: const Money(731234)));
      final b = computeHealthScore(_input(savingsActual: const Money(731234)));
      expect(a.score, b.score);
    });

    test('stays inside 0–100 for hostile input', () {
      final result = computeHealthScore(
        _input(
          savingsActual: const Money(99999999),
          totalSpent: const Money(99999999),
          categoriesExceeded: 99,
          daysWithExpenses: 99,
          daysElapsed: 1,
        ),
      );
      expect(result.score, inInclusiveRange(0, 100));
    });

    test('bands read as encouragement at the low end', () {
      expect(const HealthScore(score: 90, components: []).band, 'Excellent');
      expect(const HealthScore(score: 72, components: []).band, 'Strong');
      expect(const HealthScore(score: 55, components: []).band, 'Building');
      expect(
        const HealthScore(score: 20, components: []).band,
        'Getting started',
      );
    });
  });
}
