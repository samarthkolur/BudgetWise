import 'package:budgetwise/features/alerts/presentation/alerts_screen.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  final period = Period.current();

  testWidgets('renders real alerts derived from live budget state', (
    tester,
  ) async {
    final budget = MonthlyBudget(
      id: 'budget-1',
      period: period,
      income: const Money(5000000),
      savingsTarget: const Money(1000000),
      savingsMode: SavingsMode.percent,
      savingsPercent: 20,
    );
    final summary = BudgetSummary(
      budgetId: 'budget-1',
      period: period,
      income: const Money(5000000),
      savingsTarget: const Money(1000000),
      // Savings not confirmed — the "still pending" alert should appear.
      savedActual: const Money.zero(),
      allocated: const Money(4000000),
      spent: const Money(1500000),
      spendable: const Money(4000000),
      remaining: const Money(2500000),
      investedActual: const Money.zero(),
      categoryCount: 1,
      expenseCount: 0,
      daysWithExpenses: 0,
      savingsConfirmedAt: null,
    );

    await tester.pumpWidget(
      pumpableApp(
        child: const AlertsScreen(),
        budgetRepository: FakeBudgetRepository(
          budget: budget,
          summary: summary,
          categories: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Savings still pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the empty state when there is no plan for the month', (
    tester,
  ) async {
    await tester.pumpWidget(pumpableApp(child: const AlertsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
