import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';

class ExpenseRepository {
  ExpenseRepository(this._api);

  final ApiClient _api;

  Future<List<Expense>> forBudget(String budgetId) async => guarded(() async {
    final rows = await _api.get('/v1/budgets/$budgetId/expenses') as List;
    return rows
        .map((r) => Expense.fromJson(r as Map<String, dynamic>))
        .toList();
  });

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
              'spentOn': _dateOnly(spentOn),
              'paymentMethod': paymentMethod.name,
              'note': note,
            })
            as Map<String, dynamic>;
    return Expense.fromJson(row);
  });

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
              'spentOn': _dateOnly(spentOn),
              'paymentMethod': paymentMethod.name,
              'note': note,
            })
            as Map<String, dynamic>;
    return Expense.fromJson(row);
  });

  Future<void> delete(String id) async =>
      guarded(() => _api.delete('/v1/expenses/$id'));

  /// Date only. The time an expense was entered is not the day it belongs to,
  /// and sending an instant would put a purchase logged at 00:30 on the wrong
  /// day in some timezones.
  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
