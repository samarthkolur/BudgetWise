import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

/// A [DetectedTransaction] once it has a row of its own, so the review sheet
/// has something with an id to categorize or dismiss.
class DetectedExpense {
  const DetectedExpense({
    required this.id,
    required this.budgetId,
    required this.amount,
    required this.occurredOn,
    required this.merchant,
    required this.rawSender,
    required this.rawBody,
  });

  final String id;
  final String budgetId;
  final Money amount;
  final DateTime occurredOn;
  final String? merchant;
  final String rawSender;
  final String rawBody;
}

/// One implementation only — [LocalDetectedExpenseRepository] — unlike every
/// other repository in this app, which chooses between an API- and a
/// local-backed implementation. SMS only ever exists on the phone it arrived
/// on, so there is nothing for an API version to talk to. The interface still
/// exists so widget tests can swap in a fake the same way they do for every
/// other repository.
abstract class DetectedExpenseRepository {
  /// Inserts each candidate, skipping any whose `dedupKey` (the SMS
  /// provider's own row id, from `RawSmsMessage`) has already been recorded,
  /// so re-scanning overlapping windows never produces duplicate rows.
  Future<void> recordCandidates(
    String budgetId,
    List<({String dedupKey, DetectedTransaction transaction})> candidates,
  );

  Future<List<DetectedExpense>> pendingFor(String budgetId);

  /// Files [detected] as a real expense through the same [ExpenseRepository]
  /// every hand-entered expense uses, then marks this row confirmed. No
  /// payment method is inferred from the SMS text, so this defaults to UPI —
  /// the common case for SMS-triggered debit alerts — and the resulting
  /// expense can be corrected like any other.
  Future<void> confirm({
    required DetectedExpense detected,
    required ExpenseRepository expenses,
  });

  Future<void> dismiss(String id);

  Future<void> dismissAllPending(String budgetId);
}

class LocalDetectedExpenseRepository implements DetectedExpenseRepository {
  LocalDetectedExpenseRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  @override
  Future<void> recordCandidates(
    String budgetId,
    List<({String dedupKey, DetectedTransaction transaction})> candidates,
  ) async {
    if (candidates.isEmpty) return;
    final db = (await _dbFuture).db;
    final batch = db.batch();
    const uuid = Uuid();
    final now = DateTime.now().toIso8601String();

    for (final candidate in candidates) {
      final transaction = candidate.transaction;
      batch.insert('detected_expenses', {
        'id': uuid.v4(),
        'budget_id': budgetId,
        'sms_dedup_key': candidate.dedupKey,
        'amount_minor': transaction.amount.minor,
        'occurred_on': transaction.occurredOn.toIso8601String(),
        'merchant': transaction.merchant,
        'raw_sender': transaction.rawSender,
        'raw_body': transaction.rawBody,
        'status': 'pending',
        'detected_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<DetectedExpense>> pendingFor(String budgetId) async {
    final db = (await _dbFuture).db;
    final rows = await db.query(
      'detected_expenses',
      where: 'budget_id = ? AND status = ?',
      whereArgs: [budgetId, 'pending'],
      orderBy: 'detected_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<void> confirm({
    required DetectedExpense detected,
    required ExpenseRepository expenses,
  }) async {
    final expense = await expenses.add(
      budgetId: detected.budgetId,
      amount: detected.amount,
      spentOn: detected.occurredOn,
      paymentMethod: PaymentMethod.upi,
      note: detected.merchant,
    );

    final db = (await _dbFuture).db;
    await db.update(
      'detected_expenses',
      {'status': 'confirmed', 'expense_id': expense.id},
      where: 'id = ?',
      whereArgs: [detected.id],
    );
  }

  @override
  Future<void> dismiss(String id) async {
    final db = (await _dbFuture).db;
    await db.update(
      'detected_expenses',
      {'status': 'dismissed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> dismissAllPending(String budgetId) async {
    final db = (await _dbFuture).db;
    await db.update(
      'detected_expenses',
      {'status': 'dismissed'},
      where: 'budget_id = ? AND status = ?',
      whereArgs: [budgetId, 'pending'],
    );
  }

  static DetectedExpense _fromRow(Map<String, Object?> row) => DetectedExpense(
    id: row['id']! as String,
    budgetId: row['budget_id']! as String,
    amount: Money(row['amount_minor']! as int),
    occurredOn: DateTime.parse(row['occurred_on']! as String),
    merchant: row['merchant'] as String?,
    rawSender: row['raw_sender']! as String,
    rawBody: row['raw_body']! as String,
  );
}
