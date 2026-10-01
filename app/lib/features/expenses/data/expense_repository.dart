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
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  });
  Future<Expense> update({
    required String id,
    required String categoryId,
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

  @override
  Future<Expense> add({
    required String budgetId,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async => guarded(() async {
    final row =
        await _api.post('/v1/expenses', {
              'budgetId': budgetId,
              'categoryId': categoryId,
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
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async => guarded(() async {
    final row =
        await _api.patch('/v1/expenses/$id', {
              'categoryId': categoryId,
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
    final rows = await db.rawQuery(
      'SELECT e.*, c.name AS category_name, c.icon AS category_icon '
      'FROM expenses e JOIN categories c ON c.id = e.category_id '
      'WHERE e.budget_id = ? ORDER BY e.spent_on DESC',
      [budgetId],
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Expense> add({
    required String budgetId,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    final db = (await _dbFuture).db;
    final id = const Uuid().v4();
    await db.insert('expenses', {
      'id': id,
      'budget_id': budgetId,
      'category_id': categoryId,
      'amount_minor': amount.minor,
      'spent_on': dateOnly(spentOn),
      'payment_method': paymentMethod.name,
      'note': note,
    });
    return _mustFind(id);
  }

  @override
  Future<Expense> update({
    required String id,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    final db = (await _dbFuture).db;
    await db.update(
      'expenses',
      {
        'category_id': categoryId,
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
    final rows = await db.rawQuery(
      'SELECT e.*, c.name AS category_name, c.icon AS category_icon '
      'FROM expenses e JOIN categories c ON c.id = e.category_id '
      'WHERE e.id = ?',
      [id],
    );
    return _fromRow(rows.first);
  }

  static Expense _fromRow(Map<String, Object?> row) => Expense(
    id: row['id']! as String,
    budgetId: row['budget_id']! as String,
    categoryId: row['category_id']! as String,
    amount: Money(row['amount_minor']! as int),
    spentOn: DateTime.parse(row['spent_on']! as String),
    paymentMethod: PaymentMethod.fromDb(row['payment_method']! as String),
    note: row['note'] as String?,
    categoryName: row['category_name'] as String?,
    categoryIcon: row['category_icon'] as String?,
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
