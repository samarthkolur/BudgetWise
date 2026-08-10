import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _food = CategoryTemplate(
  key: 'food',
  name: 'Food',
  icon: '🍽️',
  defaultPercent: 60,
  isEssential: true,
);
const _misc = CategoryTemplate(key: 'misc', name: 'Misc', icon: '✨', defaultPercent: 40);

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
    allocations: allocateByPercent(
      total: const Money(800000),
      percents: {_food: 60, _misc: 40},
    ),
  );

  test('createMonth writes the budget and its categories together', () async {
    final budget = await createTestMonth();

    expect(budget.period, Period(2026, 8));
    expect(budget.income, const Money(1000000));
    expect(budget.savingsMode, SavingsMode.percent);

    final categories = await budgets.categoriesFor(budget.id);
    expect(categories, hasLength(2));
    expect(categories.map((c) => c.key), containsAll(['food', 'misc']));
    // Largest-remainder split of ₹8,000 at 60/40 lands exactly on the total.
    expect(
      categories.fold<Money>(const Money.zero(), (a, c) => a + c.allocated),
      const Money(800000),
    );
  });

  test('currentBudget finds the budget for the current calendar month', () async {
    final now = Period.current();
    final budget = await budgets.createMonth(
      period: now,
      income: const Money(500000),
      savingsMode: SavingsMode.fixed,
      savingsTarget: const Money(100000),
      allocations: allocateByPercent(
        total: const Money(400000),
        percents: {_food: 100},
      ),
    );

    final current = await budgets.currentBudget();
    expect(current?.id, budget.id);
  });

  test('currentBudget is null when no budget exists for this month', () async {
    expect(await budgets.currentBudget(), isNull);
  });

  test('summaryFor sums allocations and expenses independently', () async {
    final budget = await createTestMonth();
    final categories = await budgets.categoriesFor(budget.id);
    final food = categories.firstWhere((c) => c.key == 'food');

    final expenses = LocalExpenseRepository(dbFuture);
    await expenses.add(
      budgetId: budget.id,
      categoryId: food.id,
      amount: const Money(15000),
      spentOn: DateTime(2026, 8, 5),
      paymentMethod: PaymentMethod.upi,
    );
    await expenses.add(
      budgetId: budget.id,
      categoryId: food.id,
      amount: const Money(5000),
      spentOn: DateTime(2026, 8, 6),
      paymentMethod: PaymentMethod.cash,
    );

    final summary = await budgets.summaryFor(budget.period);
    expect(summary, isNotNull);
    expect(summary!.spent, const Money(20000));
    expect(summary.allocated, const Money(800000));
    expect(summary.categoryCount, 2);
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

  test('categoriesFor reports spent and expense count per category, not pooled', () async {
    final budget = await createTestMonth();
    final categories = await budgets.categoriesFor(budget.id);
    final food = categories.firstWhere((c) => c.key == 'food');

    final expenses = LocalExpenseRepository(dbFuture);
    await expenses.add(
      budgetId: budget.id,
      categoryId: food.id,
      amount: const Money(1000),
      spentOn: DateTime(2026, 8),
      paymentMethod: PaymentMethod.upi,
    );

    final updated = await budgets.categoriesFor(budget.id);
    final updatedFood = updated.firstWhere((c) => c.key == 'food');
    final updatedMisc = updated.firstWhere((c) => c.key == 'misc');

    expect(updatedFood.spent, const Money(1000));
    expect(updatedFood.expenseCount, 1);
    expect(updatedMisc.spent, const Money.zero());
    expect(updatedMisc.expenseCount, 0);
  });

  test('updateCategoryAllocation changes only the targeted category', () async {
    final budget = await createTestMonth();
    final categories = await budgets.categoriesFor(budget.id);
    final food = categories.firstWhere((c) => c.key == 'food');
    final miscBefore = categories.firstWhere((c) => c.key == 'misc');

    await budgets.updateCategoryAllocation(
      categoryId: food.id,
      allocated: const Money(999900),
      percent: 99.99,
    );

    final updated = await budgets.categoriesFor(budget.id);
    final updatedFood = updated.firstWhere((c) => c.key == 'food');
    final updatedMisc = updated.firstWhere((c) => c.key == 'misc');

    expect(updatedFood.allocated, const Money(999900));
    expect(updatedFood.allocatedPercent, closeTo(99.99, 0.001));
    expect(updatedMisc.allocated, miscBefore.allocated);
  });

  test('allBudgets and allSummaries return every created month', () async {
    await createTestMonth();
    await budgets.createMonth(
      period: Period(2026, 7),
      income: const Money(500000),
      savingsMode: SavingsMode.percent,
      savingsTarget: const Money(100000),
      savingsPercent: 20,
      allocations: allocateByPercent(
        total: const Money(400000),
        percents: {_food: 100},
      ),
    );

    expect(await budgets.allBudgets(), hasLength(2));
    expect(await budgets.allSummaries(), hasLength(2));
  });
}
