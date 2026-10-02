import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// The on-device store, used whenever no one is signed in — plus two tables
/// that are always local regardless of sign-in state, because what they hold
/// (the SMS-detection queue and its on/off setting) only ever makes sense on
/// the physical device the SMS arrived on.
///
/// Six tables, no ORM and no codegen — the same "hand-written mapping"
/// convention every model in this app already uses for JSON, applied to SQL
/// rows instead. Opened lazily and kept open for the app's lifetime; there is
/// exactly one of these per process, held by `localDatabaseProvider` in
/// `core/providers.dart`.
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
      version: 4,
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
          CREATE TABLE expenses (
            id TEXT PRIMARY KEY,
            budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
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
          'CREATE INDEX idx_expenses_budget ON expenses(budget_id)',
        );
        await _createSmsDetectionTables(db);
        await _createSyncQueueTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createSmsDetectionTables(db);
        }
        if (oldVersion < 3) {
          await _dropCategories(db);
        }
        if (oldVersion < 4) {
          await _createSyncQueueTable(db);
        }
      },
    );
    return LocalDatabase._(db);
  }

  /// Detected-but-not-yet-confirmed expenses from the on-device SMS scan
  /// (opt-in, Android only — see `features/sms_detection`), and the single
  /// settings row that turns it on. Split out from `onCreate` so the same
  /// statements run for a fresh install and for an `onUpgrade` from version 1.
  static Future<void> _createSmsDetectionTables(Database db) async {
    await db.execute('''
      CREATE TABLE detected_expenses (
        id TEXT PRIMARY KEY,
        budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
        sms_dedup_key TEXT NOT NULL UNIQUE,
        amount_minor INTEGER NOT NULL,
        occurred_on TEXT NOT NULL,
        merchant TEXT,
        raw_sender TEXT NOT NULL,
        raw_body TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        expense_id TEXT REFERENCES expenses(id),
        detected_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_detected_expenses_budget '
      'ON detected_expenses(budget_id, status)',
    );
    await db.execute('''
      CREATE TABLE sms_detection_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        enabled INTEGER NOT NULL DEFAULT 0,
        last_checked_at TEXT
      )
    ''');
  }

  /// Version 2 → 3: categories removed everywhere — no per-category budget
  /// limits, just a plain debit/credit history. SQLite on older Android
  /// builds can't be trusted to support `ALTER TABLE ... DROP COLUMN`, so
  /// both affected tables are rebuilt rather than altered in place: create
  /// the new shape, copy what survives, drop the old table, rename. Existing
  /// expenses and detected-expenses carry over untouched except for the
  /// columns that no longer exist; the `categories` table itself is simply
  /// dropped, since nothing references it once this runs.
  static Future<void> _dropCategories(Database db) async {
    await db.execute('''
      CREATE TABLE expenses_v3 (
        id TEXT PRIMARY KEY,
        budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
        amount_minor INTEGER NOT NULL,
        spent_on TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        note TEXT
      )
    ''');
    await db.execute('''
      INSERT INTO expenses_v3
        (id, budget_id, amount_minor, spent_on, payment_method, note)
      SELECT id, budget_id, amount_minor, spent_on, payment_method, note
      FROM expenses
    ''');
    await db.execute('DROP TABLE expenses');
    await db.execute('ALTER TABLE expenses_v3 RENAME TO expenses');
    await db.execute(
      'CREATE INDEX idx_expenses_budget ON expenses(budget_id)',
    );

    await db.execute('''
      CREATE TABLE detected_expenses_v3 (
        id TEXT PRIMARY KEY,
        budget_id TEXT NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
        sms_dedup_key TEXT NOT NULL UNIQUE,
        amount_minor INTEGER NOT NULL,
        occurred_on TEXT NOT NULL,
        merchant TEXT,
        raw_sender TEXT NOT NULL,
        raw_body TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        expense_id TEXT REFERENCES expenses(id),
        detected_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      INSERT INTO detected_expenses_v3
        (id, budget_id, sms_dedup_key, amount_minor, occurred_on, merchant,
         raw_sender, raw_body, status, expense_id, detected_at)
      SELECT id, budget_id, sms_dedup_key, amount_minor, occurred_on,
             merchant, raw_sender, raw_body, status, expense_id, detected_at
      FROM detected_expenses
    ''');
    await db.execute('DROP TABLE detected_expenses');
    await db.execute(
      'ALTER TABLE detected_expenses_v3 RENAME TO detected_expenses',
    );
    await db.execute(
      'CREATE INDEX idx_detected_expenses_budget '
      'ON detected_expenses(budget_id, status)',
    );

    await db.execute('DROP TABLE IF EXISTS categories');
  }

  /// The offline-write outbox (version 3 → 4). A write made while signed in
  /// but offline lands here instead of failing the user's action; once
  /// connectivity returns, `SyncService` (see `core/sync/`) replays these in
  /// `created_at` order against the API and deletes each row as it succeeds.
  /// `payload_json` is the exact map the matching `Api*Repository` method
  /// would have sent, so replay is "call the same method again", not a
  /// second serialization format to keep in sync with the first.
  static Future<void> _createSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE pending_sync (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }
}
