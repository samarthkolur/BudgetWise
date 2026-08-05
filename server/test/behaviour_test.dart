import 'package:test/test.dart';

import 'support/harness.dart';

/// The rules Postgres used to enforce with constraints, now enforced by code.
///
/// Every case here maps to a `check`, a unique index or a trigger from the SQL
/// schema. They are tested against the running API rather than the repository
/// directly, so the mapping from a broken rule to the status code the client
/// sees is covered too.
void main() {
  late Harness harness;
  late Session user;

  setUpAll(() async {
    harness = await Harness.start();
  });

  tearDownAll(() => harness.stop());

  setUp(() async {
    await harness.reset();
    user = await harness.signIn(subject: 'google-u', email: 'u@test.local');
  });

  group('budget creation', () {
    // Was: `check (allocated total = spendable)` inside fn_create_month_budget.
    test(
      'refuses an allocation that does not sum to spendable income',
      () async {
        final response = await user.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 5000000,
          'savingsMode': 'percent',
          'savingsPercent': 20.0,
          'savingsTargetMinor': 1000000,
          // Spendable is 40,00,000; this sums to 39,00,000.
          'categories': categoriesFor(3900000),
        });
        expect(response.statusCode, 400);

        // And nothing survives the refusal — the compensating delete ran.
        expect(
          await jsonBody<List<dynamic>>(await user.get('/v1/budgets')),
          isEmpty,
        );
      },
    );

    // Was: `check (savings_target_minor <= income_minor)`.
    test('refuses savings above income', () async {
      final response = await user.post('/v1/budgets', {
        'period': '2026-08-01',
        'incomeMinor': 100000,
        'savingsMode': 'fixed',
        'savingsTargetMinor': 500000,
        'categories': categoriesFor(0),
      });
      expect(response.statusCode, 400);
    });

    // Was: `unique (user_id, period)`.
    test('refuses a second budget for the same month', () async {
      Map<String, Object?> body() => {
        'period': '2026-08-01',
        'incomeMinor': 1000000,
        'savingsMode': 'percent',
        'savingsPercent': 10.0,
        'savingsTargetMinor': 100000,
        'categories': categoriesFor(900000),
      };

      expect((await user.post('/v1/budgets', body())).statusCode, 201);
      expect((await user.post('/v1/budgets', body())).statusCode, 409);
    });

    test('creates the budget and its categories together', () async {
      final budget = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 5000000,
          'savingsMode': 'percent',
          'savingsPercent': 20.0,
          'savingsTargetMinor': 1000000,
          'categories': categoriesFor(4000000),
        }),
      );

      final categories = await jsonBody<List<dynamic>>(
        await user.get('/v1/budgets/${budget['id']}/categories'),
      );
      expect(categories, hasLength(2));
    });
  });

  group('expenses', () {
    late String budgetId;
    late String categoryId;

    setUp(() async {
      final budget = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 5000000,
          'savingsMode': 'percent',
          'savingsPercent': 20.0,
          'savingsTargetMinor': 1000000,
          'categories': categoriesFor(4000000),
        }),
      );
      budgetId = budget['id'] as String;
      final categories = await jsonBody<List<dynamic>>(
        await user.get('/v1/budgets/$budgetId/categories'),
      );
      categoryId =
          (categories.first as Map<String, dynamic>)['categoryId'] as String;
    });

    // Was: `check (amount_minor > 0)`.
    test('refuses a zero or negative amount', () async {
      for (final amount in [0, -500]) {
        final response = await user.post('/v1/expenses', {
          'budgetId': budgetId,
          'categoryId': categoryId,
          'amountMinor': amount,
          'spentOn': '2026-08-04',
        });
        expect(response.statusCode, 400, reason: 'amount $amount was accepted');
      }
    });

    // Was: v_category_spend's overspend/remaining split.
    test(
      'states overspend separately and never a negative remainder',
      () async {
        // Category allocation is 20,00,000; spend 24,00,000.
        await user.post('/v1/expenses', {
          'budgetId': budgetId,
          'categoryId': categoryId,
          'amountMinor': 2400000,
          'spentOn': '2026-08-04',
        });

        final categories = await jsonBody<List<dynamic>>(
          await user.get('/v1/budgets/$budgetId/categories'),
        );
        final food =
            categories.firstWhere(
                  (c) =>
                      (c as Map<String, dynamic>)['categoryId'] == categoryId,
                )
                as Map<String, dynamic>;

        expect(food['spentMinor'], 2400000);
        expect(food['remainingMinor'], 0);
        expect(food['overspendMinor'], 400000);
        expect(food['pctUsed'], closeTo(1.2, 0.001));
      },
    );

    test('deleting an expense removes it from the totals', () async {
      final expense = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/expenses', {
          'budgetId': budgetId,
          'categoryId': categoryId,
          'amountMinor': 50000,
          'spentOn': '2026-08-04',
        }),
      );

      expect(
        (await user.delete('/v1/expenses/${expense['id']}')).statusCode,
        204,
      );

      final summary = await jsonBody<Map<String, dynamic>>(
        await user.get('/v1/summaries/2026-08-01'),
      );
      expect(summary['spentMinor'], 0);
    });

    // Was: v_budget_summary taking savings off the top.
    test('the summary takes savings off the top', () async {
      await user.post('/v1/expenses', {
        'budgetId': budgetId,
        'categoryId': categoryId,
        'amountMinor': 620000,
        'spentOn': '2026-08-04',
      });

      final summary = await jsonBody<Map<String, dynamic>>(
        await user.get('/v1/summaries/2026-08-01'),
      );
      expect(summary['spendableMinor'], 4000000);
      expect(summary['spentMinor'], 620000);
      expect(summary['remainingMinor'], 3380000);
      expect(summary['categoryCount'], 2);
    });
  });

  group('goals', () {
    // Was: the sync_goal_saved trigger, which recomputed rather than
    // incremented so an edit or delete could not drift the total.
    test('goal totals recompute and flip to achieved', () async {
      final goal = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/goals', {
          'title': 'Emergency fund',
          'targetMinor': 1000000,
        }),
      );
      final goalId = goal['id'] as String;

      await user.post('/v1/goals/$goalId/contribute', {'amountMinor': 300000});
      await user.post('/v1/goals/$goalId/contribute', {'amountMinor': 200000});

      var goals = await jsonBody<List<dynamic>>(await user.get('/v1/goals'));
      expect((goals.single as Map<String, dynamic>)['savedMinor'], 500000);
      expect((goals.single as Map<String, dynamic>)['status'], 'active');

      await user.post('/v1/goals/$goalId/contribute', {'amountMinor': 500000});
      goals = await jsonBody<List<dynamic>>(await user.get('/v1/goals'));
      expect((goals.single as Map<String, dynamic>)['savedMinor'], 1000000);
      expect((goals.single as Map<String, dynamic>)['status'], 'achieved');
    });

    test('refuses a non-positive target', () async {
      final response = await user.post('/v1/goals', {
        'title': 'Nothing',
        'targetMinor': 0,
      });
      expect(response.statusCode, 400);
    });
  });

  group('investing gate', () {
    // Was: the investments INSERT policy calling fn_investing_unlocked.
    test('a new user is locked, and the write is refused', () async {
      final status = await jsonBody<Map<String, dynamic>>(
        await user.get('/v1/investing/status'),
      );
      expect(status['isUnlocked'], isFalse);
      expect(status['streakMonths'], 0);

      final budget = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 1000000,
          'savingsMode': 'percent',
          'savingsPercent': 10.0,
          'savingsTargetMinor': 100000,
          'categories': categoriesFor(900000),
        }),
      );

      final response = await user.post('/v1/investing', {
        'budgetId': budget['id'],
        'amountMinor': 100000,
        'instrument': 'mutual_fund',
      });
      // 403, not 400: the refusal is about what the user has earned.
      expect(response.statusCode, 403);
    });
  });

  group('savings confirmation', () {
    test('writes both the stamp and the entry', () async {
      final budget = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 5000000,
          'savingsMode': 'percent',
          'savingsPercent': 20.0,
          'savingsTargetMinor': 1000000,
          'categories': categoriesFor(4000000),
        }),
      );

      await user.post('/v1/budgets/${budget['id']}/confirm-savings', {
        'amountMinor': 1000000,
      });

      final summary = await jsonBody<Map<String, dynamic>>(
        await user.get('/v1/summaries/2026-08-01'),
      );
      // Both, not one: the stamp drives the reminder card, the entry drives the
      // streak. Setting only the stamp turns the card green while the unlock
      // never progresses.
      expect(summary['savingsConfirmedAt'], isNotNull);
      expect(summary['savedMinor'], 1000000);
    });
  });

  group('account', () {
    test('onboarding completion is recorded', () async {
      var me = await jsonBody<Map<String, dynamic>>(await user.get('/v1/me'));
      expect(me['onboardingCompletedAt'], isNull);

      await user.patch('/v1/me', {'onboardingCompleted': true});

      me = await jsonBody<Map<String, dynamic>>(await user.get('/v1/me'));
      expect(me['onboardingCompletedAt'], isNotNull);
    });

    test('the response never leaks ownerId', () async {
      final budget = await jsonBody<Map<String, dynamic>>(
        await user.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 1000000,
          'savingsMode': 'percent',
          'savingsPercent': 10.0,
          'savingsTargetMinor': 100000,
          'categories': categoriesFor(900000),
        }),
      );
      expect(budget.containsKey('ownerId'), isFalse);
    });
  });
}
