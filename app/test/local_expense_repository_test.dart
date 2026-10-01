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
  defaultPercent: 100,
  isEssential: true,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Future<LocalDatabase> dbFuture;
  late LocalExpenseRepository expenses;
  late String budgetId;
  late String categoryId;

  setUp(() async {
    dbFuture = LocalDatabase.open(path: inMemoryDatabasePath);
    expenses = LocalExpenseRepository(dbFuture);

    final budgetRepo = LocalBudgetRepository(dbFuture);
    final budget = await budgetRepo.createMonth(
      period: Period(2026, 8),
      income: const Money(1000000),
      savingsMode: SavingsMode.percent,
      savingsTarget: const Money.zero(),
      savingsPercent: 0,
      allocations: allocateByPercent(
        total: const Money(1000000),
        percents: {_food: 100},
      ),
    );
    budgetId = budget.id;
    categoryId = (await budgetRepo.categoriesFor(budgetId)).single.id;
  });

  // sqflite treats an open path as a live handle rather than opening a fresh
  // one — without closing here, the next test's `openDatabase(':memory:')`
  // would hand back this same database instead of an empty one.
  tearDown(() async => (await dbFuture).db.close());

  test('add creates an expense with its category joined in', () async {
    final expense = await expenses.add(
      budgetId: budgetId,
      categoryId: categoryId,
      amount: const Money(2500),
      spentOn: DateTime(2026, 8, 12),
      paymentMethod: PaymentMethod.upi,
      note: 'Lunch',
    );

    expect(expense.amount, const Money(2500));
    expect(expense.categoryName, 'Food');
    expect(expense.note, 'Lunch');
    expect(expense.spentOn, DateTime(2026, 8, 12));
  });

  test('forBudget returns every expense, most recent first', () async {
    await expenses.add(
      budgetId: budgetId,
      categoryId: categoryId,
      amount: const Money(100),
      spentOn: DateTime(2026, 8),
      paymentMethod: PaymentMethod.cash,
    );
    await expenses.add(
      budgetId: budgetId,
      categoryId: categoryId,
      amount: const Money(200),
      spentOn: DateTime(2026, 8, 10),
      paymentMethod: PaymentMethod.card,
    );

    final list = await expenses.forBudget(budgetId);
    expect(list, hasLength(2));
    expect(list.first.spentOn, DateTime(2026, 8, 10));
  });

  test('update changes amount, date, method and note', () async {
    final expense = await expenses.add(
      budgetId: budgetId,
      categoryId: categoryId,
      amount: const Money(500),
      spentOn: DateTime(2026, 8),
      paymentMethod: PaymentMethod.cash,
    );

    final updated = await expenses.update(
      id: expense.id,
      categoryId: categoryId,
      amount: const Money(750),
      spentOn: DateTime(2026, 8, 2),
      paymentMethod: PaymentMethod.card,
      note: 'Updated',
    );

    expect(updated.amount, const Money(750));
    expect(updated.paymentMethod, PaymentMethod.card);
    expect(updated.note, 'Updated');
    expect(updated.spentOn, DateTime(2026, 8, 2));
  });

  test('delete removes the expense', () async {
    final expense = await expenses.add(
      budgetId: budgetId,
      categoryId: categoryId,
      amount: const Money(500),
      spentOn: DateTime(2026, 8),
      paymentMethod: PaymentMethod.cash,
    );

    await expenses.delete(expense.id);

    expect(await expenses.forBudget(budgetId), isEmpty);
  });
}
