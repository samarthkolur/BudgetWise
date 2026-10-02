import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// The insight rules are the app's own logic — the arithmetic they read lives in
/// budgetwise_domain, but the decision about what is worth telling the user is
/// made here, and it is a product judgement rather than a calculation.
///
/// Pure and deterministic, so no widget is pumped and no clock is guessed at:
/// `now` is injected everywhere it matters.
BudgetSummary _summary({
  int income = 5000000,
  int savingsTarget = 1000000,
  int saved = 1000000,
  int spent = 0,
  int spendable = 4000000,
  int daysWithExpenses = 10,
  String period = '2026-08-01',
}) => BudgetSummary(
  budgetId: 'b1',
  period: Period.parse(period),
  income: Money(income),
  savingsTarget: Money(savingsTarget),
  savedActual: Money(saved),
  spent: Money(spent),
  spendable: Money(spendable),
  remaining: Money(spendable - spent > 0 ? spendable - spent : 0),
  investedActual: const Money.zero(),
  expenseCount: 3,
  daysWithExpenses: daysWithExpenses,
  savingsConfirmedAt: DateTime(2026, 8, 2),
);

void main() {
  // Mid-month: 15 days elapsed of 31, so roughly 48% of the month is gone.
  final midMonth = DateTime(2026, 8, 15);

  group('pace', () {
    test('warns when spending has outrun the month', () {
      final insights = generateInsights(
        summary: _summary(spent: 3200000), // 80% spent, ~48% elapsed
        now: midMonth,
      );

      final pace = insights.where((i) => i.kind == 'pace_ahead');
      expect(pace, hasLength(1));
      expect(pace.single.tone, InsightTone.warning);
      // It projects a finishing total rather than just scolding.
      expect(pace.single.body, contains('At this rate'));
    });

    test('celebrates when comfortably under', () {
      final insights = generateInsights(
        summary: _summary(spent: 400000), // 10% spent, ~48% elapsed
        now: midMonth,
      );
      expect(
        insights.where((i) => i.kind == 'pace_behind'),
        hasLength(1),
      );
    });

    test('says nothing when pace is roughly on track', () {
      final insights = generateInsights(
        summary: _summary(spent: 1900000), // ~48% spent, ~48% elapsed
        now: midMonth,
      );
      expect(insights.where((i) => i.kind.startsWith('pace_')), isEmpty);
    });

    test('stays quiet in the first days, when the ratio is meaningless', () {
      // Two days in, a single large expense makes any projection nonsense.
      final insights = generateInsights(
        summary: _summary(spent: 3000000),
        now: DateTime(2026, 8, 2),
      );
      expect(insights.where((i) => i.kind.startsWith('pace_')), isEmpty);
    });
  });

  group('savings', () {
    test('celebrates when the month is fully saved', () {
      final insights = generateInsights(summary: _summary(), now: midMonth);
      expect(
        insights.where((i) => i.kind == 'savings_complete'),
        hasLength(1),
      );
    });

    test('chases only near the end of the month', () {
      final outstanding = _summary(saved: 0);

      expect(
        generateInsights(
          summary: outstanding,
          now: midMonth,
        ).where((i) => i.kind == 'savings_pending'),
        isEmpty,
        reason: 'mid-month there is still plenty of time',
      );

      expect(
        generateInsights(
          summary: outstanding,
          now: DateTime(2026, 8, 28),
        ).where((i) => i.kind == 'savings_pending'),
        hasLength(1),
      );
    });
  });

  group('logging consistency', () {
    test('flags sparse logging after a week', () {
      final insights = generateInsights(
        summary: _summary(spent: 1900000, daysWithExpenses: 1),
        now: midMonth,
      );
      expect(
        insights.where((i) => i.kind == 'logging_sparse'),
        hasLength(1),
      );
    });

    test('stays quiet when logging is consistent', () {
      final insights = generateInsights(
        summary: _summary(spent: 1900000),
        now: midMonth,
      );
      expect(insights.where((i) => i.kind == 'logging_sparse'), isEmpty);
    });
  });

  group('always says something', () {
    test('a quiet month still gets a line', () {
      // An empty insights screen looks broken rather than calm.
      final insights = generateInsights(
        summary: _summary(spent: 1900000),
        now: midMonth,
      );
      expect(insights, isNotEmpty);
    });

    test('is deterministic for identical input', () {
      List<String> run() => generateInsights(
        summary: _summary(spent: 3200000),
        now: midMonth,
      ).map((i) => i.kind).toList();

      expect(run(), run());
    });
  });
}
