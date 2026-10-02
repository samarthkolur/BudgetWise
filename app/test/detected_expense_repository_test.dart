import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise/features/sms_detection/data/detected_expense_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DetectedTransaction _transaction({String merchant = 'AMAZON PAY'}) =>
    DetectedTransaction(
      amount: const Money(49900),
      occurredOn: DateTime(2026, 1, 12),
      merchant: merchant,
      rawSender: 'HDFCBK',
      rawBody: 'Rs.499.00 debited ... at $merchant.',
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Future<LocalDatabase> dbFuture;
  late LocalDetectedExpenseRepository detected;
  late LocalExpenseRepository expenses;
  late String budgetId;

  setUp(() async {
    dbFuture = LocalDatabase.open(path: inMemoryDatabasePath);
    detected = LocalDetectedExpenseRepository(dbFuture);
    expenses = LocalExpenseRepository(dbFuture);

    final budget = await LocalBudgetRepository(dbFuture).createMonth(
      period: Period(2026, 1),
      income: const Money(1000000),
      savingsMode: SavingsMode.percent,
      savingsTarget: const Money(0),
      savingsPercent: 0,
    );
    budgetId = budget.id;
  });

  // sqflite treats an open path as a live handle rather than opening a fresh
  // one — without closing here, the next test's `openDatabase(':memory:')`
  // would hand back this same database instead of an empty one.
  tearDown(() async => (await dbFuture).db.close());

  test('recordCandidates dedups by sms_dedup_key', () async {
    await detected.recordCandidates(budgetId, [
      (dedupKey: 'sms-1', transaction: _transaction()),
    ]);
    // Re-recording the same SMS id (a re-scan of an overlapping window)
    // must not produce a second row.
    await detected.recordCandidates(budgetId, [
      (dedupKey: 'sms-1', transaction: _transaction()),
    ]);

    final pending = await detected.pendingFor(budgetId);
    expect(pending, hasLength(1));
  });

  test('pendingFor only returns pending rows for the given budget', () async {
    await detected.recordCandidates(budgetId, [
      (dedupKey: 'sms-1', transaction: _transaction(merchant: 'SWIGGY')),
      (dedupKey: 'sms-2', transaction: _transaction(merchant: 'UBER')),
    ]);

    final pending = await detected.pendingFor(budgetId);
    expect(pending, hasLength(2));
    expect(
      pending.map((d) => d.merchant),
      containsAll(['SWIGGY', 'UBER']),
    );
  });

  test(
    'confirm files a real expense and removes the row from pending',
    () async {
      await detected.recordCandidates(budgetId, [
        (dedupKey: 'sms-1', transaction: _transaction()),
      ]);
      final pendingBefore = await detected.pendingFor(budgetId);

      await detected.confirm(
        detected: pendingBefore.single,
        expenses: expenses,
      );

      final pendingAfter = await detected.pendingFor(budgetId);
      expect(pendingAfter, isEmpty);

      final filed = await expenses.forBudget(budgetId);
      expect(filed, hasLength(1));
      expect(filed.single.amount, const Money(49900));
      expect(filed.single.paymentMethod, PaymentMethod.upi);
      expect(filed.single.note, 'AMAZON PAY');
    },
  );

  test(
    'dismiss removes a single row from pending without filing an expense',
    () async {
      await detected.recordCandidates(budgetId, [
        (dedupKey: 'sms-1', transaction: _transaction()),
      ]);
      final pendingBefore = await detected.pendingFor(budgetId);

      await detected.dismiss(pendingBefore.single.id);

      expect(await detected.pendingFor(budgetId), isEmpty);
      expect(await expenses.forBudget(budgetId), isEmpty);
    },
  );

  test('dismissAllPending clears every pending row for the budget', () async {
    await detected.recordCandidates(budgetId, [
      (dedupKey: 'sms-1', transaction: _transaction(merchant: 'SWIGGY')),
      (dedupKey: 'sms-2', transaction: _transaction(merchant: 'UBER')),
    ]);

    await detected.dismissAllPending(budgetId);

    expect(await detected.pendingFor(budgetId), isEmpty);
  });
}
