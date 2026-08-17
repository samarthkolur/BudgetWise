import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Future<LocalDatabase> dbFuture;
  late LocalGoalRepository goals;

  setUp(() {
    dbFuture = LocalDatabase.open(path: inMemoryDatabasePath);
    goals = LocalGoalRepository(dbFuture);
  });

  // sqflite treats an open path as a live handle rather than opening a fresh
  // one — without closing here, the next test's `openDatabase(':memory:')`
  // would hand back this same database instead of an empty one.
  tearDown(() async => (await dbFuture).db.close());

  test('create starts a goal at zero saved and active', () async {
    final goal = await goals.create(
      title: 'Laptop',
      target: const Money(5000000),
    );

    expect(goal.saved, const Money.zero());
    expect(goal.status, 'active');
    expect(goal.isAchieved, isFalse);

    final all = await goals.all();
    expect(all, hasLength(1));
    expect(all.single.id, goal.id);
  });

  test('contribute accumulates rather than overwriting', () async {
    final goal = await goals.create(
      title: 'Laptop',
      target: const Money(5000000),
    );

    await goals.contribute(goalId: goal.id, amount: const Money(1000000));
    await goals.contribute(goalId: goal.id, amount: const Money(500000));

    final saved = (await goals.all()).single;
    expect(saved.saved, const Money(1500000));
    expect(saved.isAchieved, isFalse);
  });

  test(
    'contribute marks the goal achieved once saved reaches the target',
    () async {
      final goal = await goals.create(
        title: 'Emergency fund',
        target: const Money(1000000),
      );

      await goals.contribute(goalId: goal.id, amount: const Money(1000000));

      final achieved = (await goals.all()).single;
      expect(achieved.status, 'achieved');
      expect(achieved.isAchieved, isTrue);
    },
  );

  test('delete removes the goal', () async {
    final goal = await goals.create(
      title: 'Trip',
      target: const Money(2000000),
    );

    await goals.delete(goal.id);

    expect(await goals.all(), isEmpty);
  });
}
