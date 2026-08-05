import 'package:mongo_dart/mongo_dart.dart';

/// Collection names, in one place so a typo is a compile error rather than a
/// silently empty query. Mongo creates a collection on first write, so a
/// misspelled name does not fail — it quietly makes a second, empty one.
abstract final class Col {
  static const users = 'users';
  static const budgets = 'budgets';
  static const categories = 'categories';
  static const expenses = 'expenses';
  static const savings = 'savings_entries';
  static const goals = 'goals';
  static const goalContributions = 'goal_contributions';
  static const investments = 'investments';
  static const healthScores = 'health_scores';
  static const refreshTokens = 'refresh_tokens';

  static const List<String> all = [
    users,
    budgets,
    categories,
    expenses,
    savings,
    goals,
    goalContributions,
    investments,
    healthScores,
    refreshTokens,
  ];
}

/// The database handle, plus the indexes that make ownership scoping fast and
/// the uniqueness rules the schema depends on.
///
/// **A relational schema enforced most of this with constraints; Mongo does not.** What
/// used to be a `check` or a composite foreign key is now either a unique index
/// (where Mongo can express it) or an explicit guard in the repository layer
/// (where it cannot). Every such move is noted at the place it now lives, so
/// nobody assumes the database is still catching it.
class Mongo {
  Mongo(this.db);

  final Db db;

  static Future<Mongo> connect(String uri, {String? databaseName}) async {
    final db = Db(uri);
    await db.open();
    return Mongo(db);
  }

  DbCollection collection(String name) => db.collection(name);

  Future<void> close() => db.close();

  /// Creates every index the app relies on. Safe to run repeatedly.
  ///
  /// Called at startup rather than kept in a migration tool: Mongo index
  /// creation is idempotent and cheap, and a server that guarantees its own
  /// indexes cannot be deployed against a database that silently lacks them.
  Future<void> ensureIndexes() async {
    // Users — one account per Google subject, and email is informational only.
    await db.createIndex(Col.users, keys: {'googleSub': 1}, unique: true);

    // One budget per user per month. This is the `unique (user_id, period)`
    // constraint from the SQL schema, and the only place Mongo can still
    // enforce it for us.
    await db.createIndex(
      Col.budgets,
      keys: {'ownerId': 1, 'period': 1},
      unique: true,
    );

    // One row per category per budget.
    await db.createIndex(
      Col.categories,
      keys: {'budgetId': 1, 'categoryKey': 1},
      unique: true,
    );
    await db.createIndex(Col.categories, keys: {'ownerId': 1, 'budgetId': 1});

    // Every read of a user's data starts with ownerId, so it leads every index.
    await db.createIndex(Col.expenses, keys: {'ownerId': 1, 'spentOn': -1});
    await db.createIndex(Col.expenses, keys: {'ownerId': 1, 'budgetId': 1});
    await db.createIndex(Col.expenses, keys: {'ownerId': 1, 'categoryId': 1});

    await db.createIndex(Col.savings, keys: {'ownerId': 1, 'budgetId': 1});
    await db.createIndex(Col.goals, keys: {'ownerId': 1, 'status': 1});
    await db.createIndex(
      Col.goalContributions,
      keys: {'ownerId': 1, 'goalId': 1},
    );
    await db.createIndex(Col.investments, keys: {'ownerId': 1, 'budgetId': 1});

    await db.createIndex(
      Col.healthScores,
      keys: {'budgetId': 1},
      unique: true,
    );

    // Refresh tokens expire themselves. A TTL index means a stolen token stops
    // working even if nobody remembers to prune the collection.
    await db.createIndex(
      Col.refreshTokens,
      keys: {'tokenHash': 1},
      unique: true,
    );
    await db.createIndex(Col.refreshTokens, keys: {'ownerId': 1});
    // TTL index: Mongo removes each token once `expiresAt` passes, so an
    // abandoned or stolen refresh token stops working even if nobody prunes the
    // collection.
    //
    // Issued through runCommand because mongo_dart's createIndex helpers do not
    // expose expireAfterSeconds on either the Db or the DbCollection signature —
    // the option exists in CreateIndexOptions but is not reachable from the
    // public API.
    await db.runCommand({
      'createIndexes': Col.refreshTokens,
      'indexes': [
        {
          'key': {'expiresAt': 1},
          'name': 'refresh_token_ttl',
          'expireAfterSeconds': 0,
        },
      ],
    });
  }

  /// Deletes everything a user owns.
  ///
  /// A relational schema did this with `on delete cascade`. Mongo has no foreign keys at
  /// all, so the cascade is this list — and it is the reason every collection
  /// carries `ownerId` rather than relying on a parent reference. A collection
  /// added later without `ownerId` would silently survive account deletion,
  /// which is why the test suite asserts the count of remaining documents
  /// across *every* collection rather than the ones it happens to know about.
  Future<void> deleteEverythingOwnedBy(ObjectId ownerId) async {
    for (final name in Col.all) {
      if (name == Col.users) continue;
      await db.collection(name).deleteMany(where.eq('ownerId', ownerId));
    }
    await db.collection(Col.users).deleteOne(where.id(ownerId));
  }
}
