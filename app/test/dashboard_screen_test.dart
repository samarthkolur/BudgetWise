import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/dashboard/presentation/dashboard_screen.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() {
    EditableText.debugDeterministicCursor = true;
  });

  final period = Period.current();
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
    savedActual: const Money(1000000),
    spent: const Money(1500000),
    spendable: const Money(4000000),
    remaining: const Money(2500000),
    investedActual: const Money.zero(),
    expenseCount: 2,
    daysWithExpenses: 2,
    savingsConfirmedAt: DateTime.now(),
  );
  final expenses = [
    Expense(
      id: 'exp-1',
      budgetId: 'budget-1',
      amount: const Money(800000),
      spentOn: DateTime.now(),
      paymentMethod: PaymentMethod.upi,
      note: 'Food',
    ),
    Expense(
      id: 'exp-2',
      budgetId: 'budget-1',
      amount: const Money(700000),
      spentOn: DateTime.now(),
      paymentMethod: PaymentMethod.cash,
      note: 'Transport',
    ),
  ];

  testWidgets(
    'renders the hero figure, stats, and expenditure history with no exceptions',
    (
      tester,
    ) async {
      await tester.pumpWidget(
        pumpableApp(
          child: const DashboardScreen(),
          budgetRepository: FakeBudgetRepository(
            budget: budget,
            summary: summary,
          ),
          expenseRepository: FakeExpenseRepository(seed: expenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SAFE TO SPEND TODAY'), findsOneWidget);
      expect(find.text('Food'), findsWidgets);
      expect(find.text('Transport'), findsWidgets);
      expect(find.text('Expenditure history'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows the empty state when there is no plan for the month', (
    tester,
  ) async {
    await tester.pumpWidget(pumpableApp(child: const DashboardScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No plan for this month yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
