import 'package:budgetwise_server/budgetwise_server.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// Cross-user isolation.
///
/// **This is the most important suite in the project.** Under Postgres, row-level
/// security enforced separation inside the database, and the SQL suite proved
/// it. MongoDB has no such mechanism: separation now depends entirely on
/// [OwnedCollection] scoping every query and on the repositories checking parent
/// ownership by hand.
///
/// Which means these tests are no longer a second opinion on the database —
/// they are the only thing standing between the two users. Every case here has
/// a direct ancestor in the old RLS suite, and the mapping is noted so nothing
/// silently stopped being covered in the migration.
void main() {
  late Harness harness;
  late Session alice;
  late Session bob;
  late String aliceBudgetId;
  late String aliceCategoryId;
  late String aliceExpenseId;
  late String aliceGoalId;

  setUpAll(() async {
    harness = await Harness.start();
    alice = await harness.signIn(
      subject: 'google-alice',
      email: 'alice@test.local',
    );
    bob = await harness.signIn(subject: 'google-bob', email: 'bob@test.local');

    // Alice: 50,000 income, 10,000 savings => 40,000 spendable.
    final budget = await jsonBody<Map<String, dynamic>>(
      await alice.post('/v1/budgets', {
        'period': '2026-08-01',
        'incomeMinor': 5000000,
        'savingsMode': 'percent',
        'savingsPercent': 20.0,
        'savingsTargetMinor': 1000000,
        'categories': categoriesFor(4000000),
      }),
    );
    aliceBudgetId = budget['id'] as String;

    final categories = await jsonBody<List<dynamic>>(
      await alice.get('/v1/budgets/$aliceBudgetId/categories'),
    );
    aliceCategoryId =
        (categories.first as Map<String, dynamic>)['categoryId'] as String;

    final expense = await jsonBody<Map<String, dynamic>>(
      await alice.post('/v1/expenses', {
        'budgetId': aliceBudgetId,
        'categoryId': aliceCategoryId,
        'amountMinor': 25000,
        'spentOn': '2026-08-04',
        'note': 'alice lunch',
      }),
    );
    aliceExpenseId = expense['id'] as String;

    final goal = await jsonBody<Map<String, dynamic>>(
      await alice.post('/v1/goals', {
        'title': 'Laptop',
        'targetMinor': 8000000,
      }),
    );
    aliceGoalId = goal['id'] as String;
  });

  tearDownAll(() => harness.stop());

  group('reads', () {
    // Was: "cross-user reads blocked on 9 tables".
    test("bob sees none of alice's budgets, expenses or goals", () async {
      expect(
        await jsonBody<List<dynamic>>(await bob.get('/v1/budgets')),
        isEmpty,
      );
      expect(
        await jsonBody<List<dynamic>>(await bob.get('/v1/goals')),
        isEmpty,
      );
      expect(
        await jsonBody<List<dynamic>>(await bob.get('/v1/summaries')),
        isEmpty,
      );

      // And alice still sees her own — a suite that passes because everything
      // is empty proves nothing.
      expect(
        await jsonBody<List<dynamic>>(await alice.get('/v1/budgets')),
        hasLength(1),
      );
    });

    test("bob cannot read alice's budget by id", () async {
      final response = await bob.get('/v1/budgets/$aliceBudgetId/categories');
      expect(response.statusCode, 404);
    });

    test("bob cannot list expenses on alice's budget", () async {
      final response = await bob.get('/v1/budgets/$aliceBudgetId/expenses');
      expect(response.statusCode, 404);
    });
  });

  group('writes', () {
    // Was: "composite FK rejects cross-user parent" — the subtle attack. Bob
    // owns the row he is creating; only the PARENT belongs to Alice. A naive
    // `ownerId = me` filter would wave this straight through.
    test("bob cannot attach an expense he owns to alice's budget", () async {
      final response = await bob.post('/v1/expenses', {
        'budgetId': aliceBudgetId,
        'categoryId': aliceCategoryId,
        'amountMinor': 5000,
        'spentOn': '2026-08-04',
      });
      expect(response.statusCode, 404);

      // And nothing was written.
      final expenses = await jsonBody<List<dynamic>>(
        await alice.get('/v1/budgets/$aliceBudgetId/expenses'),
      );
      expect(expenses, hasLength(1));
    });

    test("bob cannot contribute to alice's goal", () async {
      final response = await bob.post('/v1/goals/$aliceGoalId/contribute', {
        'amountMinor': 100000,
      });
      expect(response.statusCode, 404);
    });

    // Was: "cross-user update and delete affect nothing".
    test("bob cannot update or delete alice's expense", () async {
      final update = await bob.patch('/v1/expenses/$aliceExpenseId', {
        'categoryId': aliceCategoryId,
        'amountMinor': 1,
        'spentOn': '2026-08-04',
      });
      expect(update.statusCode, 404);

      expect(
        (await bob.delete('/v1/expenses/$aliceExpenseId')).statusCode,
        404,
      );

      // Alice's expense is untouched.
      final expenses = await jsonBody<List<dynamic>>(
        await alice.get('/v1/budgets/$aliceBudgetId/expenses'),
      );
      expect(
        (expenses.single as Map<String, dynamic>)['amountMinor'],
        25000,
      );
    });

    /// A forged ownerId in the body must be ignored rather than honoured.
    ///
    /// New for MongoDB: under Postgres a request body could not influence
    /// `user_id` at all. Two things stop it here — the route extracts typed
    /// fields rather than forwarding the body, and [OwnedCollection.insert]
    /// stamps the owner last. The first is what makes it safe today; the second
    /// is what keeps it safe if a handler is ever written more loosely.
    test('a forged ownerId in the request body is ignored', () async {
      final response = await bob.post('/v1/goals', {
        'title': 'Injected',
        'targetMinor': 100000,
        'ownerId': alice.userId,
      });
      expect(response.statusCode, 201);

      // It belongs to Bob, not Alice.
      final aliceGoals = await jsonBody<List<dynamic>>(
        await alice.get('/v1/goals'),
      );
      expect(
        aliceGoals.map((g) => (g as Map<String, dynamic>)['title']),
        isNot(contains('Injected')),
      );
      final bobGoals = await jsonBody<List<dynamic>>(
        await bob.get('/v1/goals'),
      );
      expect(
        bobGoals.map((g) => (g as Map<String, dynamic>)['title']),
        contains('Injected'),
      );
    });
  });

  group('authentication', () {
    test('no token is rejected', () async {
      expect((await harness.get('/v1/budgets')).statusCode, 401);
    });

    test('a garbage token is rejected', () async {
      expect(
        (await harness.get('/v1/budgets', token: 'not-a-jwt')).statusCode,
        401,
      );
    });

    /// A token signed with a different secret must not verify.
    ///
    /// This is the attack the JWT signature exists to stop: without checking it,
    /// anyone could mint a token claiming any owner id.
    test('a token signed with the wrong secret is rejected', () async {
      final forged = TokenService(
        secret: 'a-completely-different-secret-of-sufficient-length',
        accessTtl: const Duration(hours: 1),
        refreshTtl: const Duration(days: 1),
        refreshTokens: harness.mongo.collection('refresh_tokens'),
      );
      final pair = await forged.issue(
        ownerId: alice.ownerId,
        email: 'alice@test.local',
      );

      final response = await harness.get(
        '/v1/budgets',
        token: pair.accessToken,
      );
      expect(response.statusCode, 401);
    });

    /// The audience check — the reason a Google token for another app cannot be
    /// used to sign in here.
    test('a Google token minted for another app is rejected', () async {
      final foreign = harness.google.issue(
        subject: 'google-mallory',
        email: 'mallory@test.local',
        audienceOverride: 'some-other-app.apps.googleusercontent.com',
      );
      final response = await harness.post('/v1/auth/google', {
        'idToken': foreign,
      });
      expect(response.statusCode, 401);
    });

    test('an expired Google token is rejected', () async {
      final expired = harness.google.issue(
        subject: 'google-expired',
        email: 'expired@test.local',
        expiry: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final response = await harness.post('/v1/auth/google', {
        'idToken': expired,
      });
      expect(response.statusCode, 401);
    });

    test('signing in twice returns the same account', () async {
      final again = await harness.signIn(
        subject: 'google-alice',
        email: 'alice@test.local',
      );
      expect(again.userId, alice.userId);
    });
  });

  group('account deletion', () {
    // Was: "deleting the auth user cascades everywhere".
    test('deleting an account leaves nothing behind in any collection', () async {
      final carol = await harness.signIn(
        subject: 'google-carol',
        email: 'carol@test.local',
      );

      final budget = await jsonBody<Map<String, dynamic>>(
        await carol.post('/v1/budgets', {
          'period': '2026-08-01',
          'incomeMinor': 1000000,
          'savingsMode': 'percent',
          'savingsPercent': 10.0,
          'savingsTargetMinor': 100000,
          'categories': categoriesFor(900000),
        }),
      );
      await carol.post('/v1/goals', {'title': 'Trip', 'targetMinor': 500000});

      expect((await carol.delete('/v1/me')).statusCode, 204);

      // Checked across EVERY collection, not the ones this test happens to know
      // about — a collection added later without ownerId would survive deletion
      // silently, and this is what catches it.
      final ownerId = carol.ownerId;
      for (final name in Col.all) {
        final remaining = name == Col.users
            ? await harness.mongo.collection(name).count(where.id(ownerId))
            : await harness.mongo
                  .collection(name)
                  .count(where.eq('ownerId', ownerId));
        expect(remaining, 0, reason: 'collection "$name" kept carol\'s data');
      }

      // Alice is untouched.
      expect(
        await jsonBody<List<dynamic>>(await alice.get('/v1/budgets')),
        hasLength(1),
      );
      expect(budget['id'], isNotNull);
    });
  });
}
