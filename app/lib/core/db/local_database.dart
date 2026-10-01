import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The on-device store, used whenever no one is signed in.
///
/// One database, five tables, no ORM and no codegen — the same "hand-written
/// mapping" convention every model in this app already uses for JSON, applied
/// to SQL rows instead. Opened lazily and kept open for the app's lifetime;
/// there is exactly one of these per process, held by `localDatabaseProvider`
/// in `core/providers.dart`.
class LocalDatabase {
  LocalDatabase._(this._db);

  final Database _db;
  Database get db => _db;

  /// [path] is an override for tests — production always uses the default
  /// on-device location. Pass [inMemoryDatabasePath] to get an isolated,
  /// throwaway database per test.
  static Future<LocalDatabase> open({String? path}) async {
    final resolvedPath =
        path ?? p.join(await getDatabasesPath(), 'budgetwise_local.db');
    final db = await openDatabase(
      resolvedPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_profile (
            id TEXT PRIMARY KEY,
            email TEXT,
            display_name TEXT,
            avatar_url TEXT,
            currency TEXT NOT NULL,
            locale TEXT NOT NULL,
            onboarding_completed_at TEXT,
            investing_unlocked_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE budgets (
            id TEXT PRIMARY KEY,
            period TEXT NOT NULL UNIQUE,
            income_minor INTEGER NOT NULL,
            savings_target_minor INTEGER NOT NULL,
            savings_mode TEXT NOT NULL,
            savings_percent REAL,
            investment_target_minor INTEGER,
            savings_confirmed_at TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            carried_from_period TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
            key TEXT NOT NULL,
            name TEXT NOT NULL,
            icon TEXT NOT NULL,
            allocated_minor INTEGER NOT NULL,
            allocated_percent REAL NOT NULL,
            sort_order INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses (
            id TEXT PRIMARY KEY,
            budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
            category_id TEXT NOT NULL REFERENCES categories(id),
            amount_minor INTEGER NOT NULL,
            spent_on TEXT NOT NULL,
            payment_method TEXT NOT NULL,
            note TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE goals (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            target_minor INTEGER NOT NULL,
            saved_minor INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'active',
            icon TEXT,
            target_date TEXT,
            monthly_contribution_minor INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_categories_budget ON categories(budget_id)',
        );
        await db.execute(
          'CREATE INDEX idx_expenses_budget ON expenses(budget_id)',
        );
        await db.execute(
          'CREATE INDEX idx_expenses_category ON expenses(category_id)',
        );
      },
    );
    return LocalDatabase._(db);
  }
}
