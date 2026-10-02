import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Two implementations: [ApiExpenseRepository] talks to the server,
/// [LocalExpenseRepository] talks to the on-device database. Neither the
/// providers nor the screens that consume this interface know or care which
/// one they got.
abstract class ExpenseRepository {
  Future<List<Expense>> forBudget(String budgetId);
  Future<Expense> add({
    required String budgetId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
    String? id,
  });
  Future<Expense> update({
    required String id,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  });
  Future<void> delete(String id);
}

class ApiExpenseRepository implements ExpenseRepository {
  ApiExpenseRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Expense>> forBudget(String budgetId) async => guarded(() async {
    final rows = await _api.get('/v1/budgets/$budgetId/expenses') as List;
    return rows
        .map((r) => Expense.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  /// [id] is only ever passed by `SyncingExpenseRepository`, replaying an
  /// expense that was already written to the local database while offline —
  /// the server accepts a client-supplied id on create so the synced row
  /// keeps the exact id its local copy already has, with no remapping step.
  /// Every other caller omits it and lets the server generate one.
  @override
  Future<Expense> add({
    required String budgetId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
    String? id,
  }) async => guarded(() async {
    final row =
        await _api.post('/v1/expenses', {
              if (id != null) 'id': id,
              'budgetId': budgetId,
              'amountMinor': amount.minor,
              'spentOn': dateOnly(spentOn),
              'paymentMethod': paymentMethod.name,
              'note': note,
            })
            as Map<String, dynamic>;
    return Expense.fromJson(row);
  });

  @override
  Future<Expense> update({
    required String id,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async => guarded(() async {
    final row =
        await _api.patch('/v1/expenses/$id', {
              'amountMinor': amount.minor,
              'spentOn': dateOnly(spentOn),
              'paymentMethod': paymentMethod.name,
              'note': note,
            })
            as Map<String, dynamic>;
    return Expense.fromJson(row);
  });

  @override
  Future<void> delete(String id) async =>
      guarded(() => _api.delete('/v1/expenses/$id'));
}

/// Talks to the on-device database, used whenever no one is signed in.
class LocalExpenseRepository implements ExpenseRepository {
  LocalExpenseRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  @override
  Future<List<Expense>> forBudget(String budgetId) async {
    final db = (await _dbFuture).db;
    final rows = await db.query(
      'expenses',
      where: 'budget_id = ?',
      whereArgs: [budgetId],
      orderBy: 'spent_on DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Expense> add({
    required String budgetId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
    String? id,
  }) async {
    final db = (await _dbFuture).db;
    final resolvedId = id ?? const Uuid().v4();
    await db.insert('expenses', {
      'id': resolvedId,
      'budget_id': budgetId,
      'amount_minor': amount.minor,
      'spent_on': dateOnly(spentOn),
      'payment_method': paymentMethod.name,
      'note': note,
    });
    return _mustFind(resolvedId);
  }

  @override
  Future<Expense> update({
    required String id,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    final db = (await _dbFuture).db;
    await db.update(
      'expenses',
      {
        'amount_minor': amount.minor,
        'spent_on': dateOnly(spentOn),
        'payment_method': paymentMethod.name,
        'note': note,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return _mustFind(id);
  }

  @override
  Future<void> delete(String id) async {
    final db = (await _dbFuture).db;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<Expense> _mustFind(String id) async {
    final db = (await _dbFuture).db;
    final rows = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    return _fromRow(rows.first);
  }

  static Expense _fromRow(Map<String, Object?> row) => Expense(
    id: row['id']! as String,
    budgetId: row['budget_id']! as String,
    amount: Money(row['amount_minor']! as int),
    spentOn: DateTime.parse(row['spent_on']! as String),
    paymentMethod: PaymentMethod.fromDb(row['payment_method']! as String),
    note: row['note'] as String?,
  );
}

/// Date only. The time an expense was entered is not the day it belongs to,
/// and sending an instant would put a purchase logged at 00:30 on the wrong
/// day in some timezones. Shared by both repositories so a local expense and
/// a synced one land on the same day.
String dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
