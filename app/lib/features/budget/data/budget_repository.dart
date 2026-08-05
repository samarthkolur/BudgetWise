import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';

/// Every read and write of a month's plan.
///
/// The only layer that knows the API's URL shapes. Note what is absent: no
/// owner or user id anywhere. The server derives it from the access token, and
/// sending one from here would be both redundant and a lie the server ignores.
class BudgetRepository {
  BudgetRepository(this._api);

  final ApiClient _api;

  /// The plan for the current month, or null when none exists yet — which is
  /// precisely the signal the router uses to send the user into onboarding.
  Future<MonthlyBudget?> currentBudget() async => guarded(() async {
    final row = await _api.get('/v1/budgets/current');
    return row == null
        ? null
        : MonthlyBudget.fromJson(row as Map<String, dynamic>);
  });

  Future<BudgetSummary?> summaryFor(Period period) async => guarded(() async {
    final row = await _api.get('/v1/summaries/${period.isoDate}');
    return row == null
        ? null
        : BudgetSummary.fromJson(row as Map<String, dynamic>);
  });

  Future<List<CategorySpend>> categoriesFor(String budgetId) async =>
      guarded(() async {
        final rows = await _api.get('/v1/budgets/$budgetId/categories') as List;
        return rows
            .map((r) => CategorySpend.fromJson(r as Map<String, dynamic>))
            .toList();
      });

  Future<List<MonthlyBudget>> allBudgets() async => guarded(() async {
    final rows = await _api.get('/v1/budgets') as List;
    return rows
        .map((r) => MonthlyBudget.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  Future<List<BudgetSummary>> allSummaries() async => guarded(() async {
    final rows = await _api.get('/v1/summaries') as List;
    return rows
        .map((r) => BudgetSummary.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  /// Creates a month's plan and all its categories in one request.
  ///
  /// One call, not two: the server writes the budget and its categories
  /// together, and refuses an allocation that does not sum to spendable income
  /// using the same largest-remainder arithmetic this app used to build it —
  /// both sides import budgetwise_domain, so they cannot drift.
  Future<MonthlyBudget> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    required List<Allocation<CategoryTemplate>> allocations,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
  }) async => guarded(() async {
    final row =
        await _api.post('/v1/budgets', {
              'period': period.isoDate,
              'incomeMinor': income.minor,
              'savingsMode': savingsMode.name,
              'savingsPercent': savingsPercent,
              'savingsTargetMinor': savingsTarget.minor,
              'investmentTargetMinor': investmentTarget?.minor,
              'carriedFromPeriod': carriedFrom?.isoDate,
              'categories': [
                for (var i = 0; i < allocations.length; i++)
                  {
                    'categoryKey': allocations[i].key.key,
                    'displayName': allocations[i].key.name,
                    'icon': allocations[i].key.icon,
                    'allocatedMinor': allocations[i].amount.minor,
                    'allocatedPercent': allocations[i].percent,
                    'sortOrder': i,
                  },
              ],
            })
            as Map<String, dynamic>;
    return MonthlyBudget.fromJson(row);
  });

  /// Records that the user moved their savings.
  ///
  /// The server writes both the confirmation stamp and the savings entry. The
  /// stamp drives the reminder card; the entry is what the streak and the
  /// emergency-fund ratio are computed from.
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  }) async => guarded(
    () => _api.post('/v1/budgets/$budgetId/confirm-savings', {
      'amountMinor': amount.minor,
      'destination': destination,
    }),
  );

  Future<void> updateCategoryAllocation({
    required String categoryId,
    required Money allocated,
    required double percent,
  }) async => guarded(
    () => _api.patch('/v1/categories/$categoryId', {
      'allocatedMinor': allocated.minor,
      'allocatedPercent': percent,
    }),
  );
}
