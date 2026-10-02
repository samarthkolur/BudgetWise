import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Future<LocalDatabase> dbFuture;
  late LocalBudgetRepository budgets;

  setUp(() {
    dbFuture = LocalDatabase.open(path: inMemoryDatabasePath);
    budgets = LocalBudgetRepository(dbFuture);
  });

  // sqflite treats an open path as a live handle rather than opening a fresh
  // one — without closing here, the next test's `openDatabase(':memory:')`
  // would hand back this same database instead of an empty one.
  tearDown(() async => (await dbFuture).db.close());

  Future<MonthlyBudget> createTestMonth() => budgets.createMonth(
    period: Period(2026, 8),
    income: const Money(1000000),
    savingsMode: SavingsMode.percent,
    savingsTarget: const Money(200000),
    savingsPercent: 20,
  );

  test('createMonth writes the budget', () async {
    final budget = await createTestMonth();

    expect(budget.period, Period(2026, 8));
    expect(budget.income, const Money(1000000));
    expect(budget.savingsMode, SavingsMode.percent);
  });

  test(
    'currentBudget finds the budget for the current calendar month',
    () async {
      final now = Period.current();
      final budget = await budgets.createMonth(
        period: now,
        income: const Money(500000),
        savingsMode: SavingsMode.fixed,
        savingsTarget: const Money(100000),
      );

      final current = await budgets.currentBudget();
      expect(current?.id, budget.id);
    },
  );

  test('currentBudget is null when no budget exists for this month', () async {
    expect(await budgets.currentBudget(), isNull);
  });

  test('summaryFor sums expenses independently of the plan', () async {
    final budget = await createTestMonth();

    final expenses = LocalExpenseRepository(dbFuture);
    await expenses.add(
      budgetId: budget.id,
      amount: const Money(15000),
      spentOn: DateTime(2026, 8, 5),
      paymentMethod: PaymentMethod.upi,
    );
    await expenses.add(
      budgetId: budget.id,
      amount: const Money(5000),
      spentOn: DateTime(2026, 8, 6),
      paymentMethod: PaymentMethod.cash,
    );

    final summary = await budgets.summaryFor(budget.period);
    expect(summary, isNotNull);
    expect(summary!.spent, const Money(20000));
    expect(summary.expenseCount, 2);
    expect(summary.daysWithExpenses, 2);
    expect(summary.remaining, summary.spendable - const Money(20000));
  });

  test('summaryFor is null when no budget exists for the period', () async {
    expect(await budgets.summaryFor(Period(2099, 1)), isNull);
  });

  test('savedActual is zero until savings are confirmed', () async {
    final budget = await createTestMonth();

    var summary = await budgets.summaryFor(budget.period);
    expect(summary!.savedActual, const Money.zero());
    expect(summary.isSavingsConfirmed, isFalse);

    await budgets.confirmSavings(
      budgetId: budget.id,
      amount: budget.savingsTarget,
    );

    summary = await budgets.summaryFor(budget.period);
    expect(summary!.savedActual, budget.savingsTarget);
    expect(summary.isSavingsConfirmed, isTrue);
  });

  test('allBudgets and allSummaries return every created month', () async {
    await createTestMonth();
    await budgets.createMonth(
      period: Period(2026, 7),
      income: const Money(500000),
      savingsMode: SavingsMode.percent,
      savingsTarget: const Money(100000),
      savingsPercent: 20,
    );

    expect(await budgets.allBudgets(), hasLength(2));
    expect(await budgets.allSummaries(), hasLength(2));
  });
}
