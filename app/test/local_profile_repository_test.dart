import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fresh in-memory database per test — [inMemoryDatabasePath] opens a new,
/// isolated SQLite database each time, so nothing here needs manual cleanup.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Future<LocalDatabase> dbFuture;
  late LocalProfileRepository profiles;

  setUp(() {
    dbFuture = LocalDatabase.open(path: inMemoryDatabasePath);
    profiles = LocalProfileRepository(dbFuture);
  });

  // sqflite treats an open path as a live handle rather than opening a fresh
  // one — without closing here, the next test's `openDatabase(':memory:')`
  // would hand back this same database instead of an empty one.
  tearDown(() async => (await dbFuture).db.close());

  test('creates a default local profile on first access', () async {
    final profile = await profiles.current();

    expect(profile.id, isNotEmpty);
    expect(profile.currency, 'INR');
    expect(profile.locale, 'en_IN');
    expect(profile.email, isNull);
    expect(profile.hasCompletedOnboarding, isFalse);
    expect(profile.isInvestingUnlocked, isFalse);
  });

  test('returns the same profile on repeated access, not a new one', () async {
    final first = await profiles.current();
    final second = await profiles.current();

    expect(second.id, first.id);
  });

  test('completeOnboarding stamps the timestamp and persists it', () async {
    await profiles.current();
    final updated = await profiles.completeOnboarding();

    expect(updated.hasCompletedOnboarding, isTrue);
    final reread = await profiles.current();
    expect(reread.hasCompletedOnboarding, isTrue);
  });

  test('investingStatus is always locked without a server to verify it', () async {
    final status = await profiles.investingStatus();

    expect(status.isUnlocked, isFalse);
    expect(status.streakMonths, 0);
  });

  test('deleteAccount clears the profile and every other local table', () async {
    final db = await dbFuture;
    final budgets = LocalBudgetRepository(dbFuture);
    const template = CategoryTemplate(
      key: 'food',
      name: 'Food',
      icon: '🍽️',
      defaultPercent: 100,
      isEssential: true,
    );

    await profiles.current();
    await budgets.createMonth(
      period: Period(2026, 8),
      income: const Money(1000000),
      savingsMode: SavingsMode.percent,
      savingsTarget: const Money.zero(),
      savingsPercent: 0,
      allocations: allocateByPercent(
        total: const Money(1000000),
        percents: {template: 100},
      ),
    );

    await profiles.deleteAccount();

    expect(await db.db.query('local_profile'), isEmpty);
    expect(await db.db.query('budgets'), isEmpty);
    expect(await db.db.query('categories'), isEmpty);
  });
}
