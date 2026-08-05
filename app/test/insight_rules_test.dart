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
  allocated: Money(spendable),
  spent: Money(spent),
  spendable: Money(spendable),
  remaining: Money(spendable - spent > 0 ? spendable - spent : 0),
  investedActual: const Money.zero(),
  categoryCount: 2,
  expenseCount: 3,
  daysWithExpenses: daysWithExpenses,
  savingsConfirmedAt: DateTime(2026, 8, 2),
);

CategorySpend _category({
  String key = 'food',
  String name = 'Food',
  int allocated = 2000000,
  int spent = 0,
}) => CategorySpend(
  id: 'c-$key',
  budgetId: 'b1',
  key: key,
  name: name,
  icon: '🍽️',
  allocated: Money(allocated),
  spent: Money(spent),
  allocatedPercent: 50,
  expenseCount: 1,
  sortOrder: 0,
);

void main() {
  // Mid-month: 15 days elapsed of 31, so roughly 48% of the month is gone.
  final midMonth = DateTime(2026, 8, 15);

  group('pace', () {
    test('warns when spending has outrun the month', () {
      final insights = generateInsights(
        summary: _summary(spent: 3200000), // 80% spent, ~48% elapsed
        categories: [_category(allocated: 4000000, spent: 3200000)],
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
        categories: [_category(allocated: 4000000, spent: 400000)],
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
        categories: [_category(allocated: 4000000, spent: 1900000)],
        now: midMonth,
      );
      expect(insights.where((i) => i.kind.startsWith('pace_')), isEmpty);
    });

    test('stays quiet in the first days, when the ratio is meaningless', () {
      // Two days in, a single large expense makes any projection nonsense.
      final insights = generateInsights(
        summary: _summary(spent: 3000000),
        categories: [_category(allocated: 4000000, spent: 3000000)],
        now: DateTime(2026, 8, 2),
      );
      expect(insights.where((i) => i.kind.startsWith('pace_')), isEmpty);
    });
  });

  group('categories', () {
    test('reports an overspend as its own figure', () {
      final insights = generateInsights(
        summary: _summary(spent: 2400000),
        categories: [_category(spent: 2400000)],
        now: midMonth,
      );
      final exceeded = insights.singleWhere(
        (i) => i.kind == 'category_exceeded',
      );
      expect(exceeded.title, contains('Food'));
      expect(exceeded.body, contains('₹4,000'));
    });

    test('warns before the limit while there is still time to act', () {
      final insights = generateInsights(
        summary: _summary(spent: 1600000),
        categories: [_category(spent: 1600000)], // 80%
        now: midMonth,
      );
      expect(
        insights.where((i) => i.kind == 'category_warning'),
        hasLength(1),
      );
    });

    test('does not warn in the last days, when the advice is useless', () {
      // At 80% with two days left, "you are at 80%" is not actionable — the
      // month is nearly over and the money was budgeted to be spent.
      final insights = generateInsights(
        summary: _summary(spent: 1600000),
        categories: [_category(spent: 1600000)],
        now: DateTime(2026, 8, 30),
      );
      expect(insights.where((i) => i.kind == 'category_warning'), isEmpty);
    });
  });

  group('month-on-month movement', () {
    test('reports a large change', () {
      final insights = generateInsights(
        summary: _summary(spent: 1000000),
        categories: [_category(spent: 1000000)],
        lastMonthCategories: [_category(spent: 500000)],
        now: midMonth,
      );
      final trend = insights.singleWhere((i) => i.kind == 'category_trend');
      expect(trend.title, contains('up'));
      expect(trend.title, contains('100%'));
    });

    test('ignores a small change, which is noise dressed as a finding', () {
      final insights = generateInsights(
        summary: _summary(spent: 1050000),
        categories: [_category(spent: 1050000)],
        lastMonthCategories: [_category(spent: 1000000)], // 5%
        now: midMonth,
      );
      expect(insights.where((i) => i.kind == 'category_trend'), isEmpty);
    });
  });

  group('savings', () {
    test('celebrates when the month is fully saved', () {
      final insights = generateInsights(
        summary: _summary(),
        categories: [_category()],
        now: midMonth,
      );
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
          categories: [_category()],
          now: midMonth,
        ).where((i) => i.kind == 'savings_pending'),
        isEmpty,
        reason: 'mid-month there is still plenty of time',
      );

      expect(
        generateInsights(
          summary: outstanding,
          categories: [_category()],
          now: DateTime(2026, 8, 28),
        ).where((i) => i.kind == 'savings_pending'),
        hasLength(1),
      );
    });
  });

  group('always says something', () {
    test('a quiet month still gets a line', () {
      // An empty insights screen looks broken rather than calm.
      final insights = generateInsights(
        summary: _summary(spent: 1900000),
        categories: [_category(allocated: 4000000, spent: 1900000)],
        now: midMonth,
      );
      expect(insights, isNotEmpty);
    });

    test('is deterministic for identical input', () {
      List<String> run() => generateInsights(
        summary: _summary(spent: 3200000),
        categories: [_category(spent: 2400000)],
        now: midMonth,
      ).map((i) => i.kind).toList();

      expect(run(), run());
    });
  });
}
