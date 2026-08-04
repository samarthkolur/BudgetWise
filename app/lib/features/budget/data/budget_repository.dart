import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/money/allocation.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every read and write of a month's plan.
///
/// The only layer that knows Supabase exists. Driver exceptions are mapped to
/// [AppFailure] here so nothing above this file branches on a Postgres error
/// code, and no constraint name ever reaches a user.
///
/// Note what is absent: no `.eq('user_id', ...)` filters. RLS applies them in
/// the database on every statement, and adding them here would suggest the
/// client is what keeps users apart. It is not, and a reader who believed that
/// might one day "optimise" the filter away.
class BudgetRepository {
  BudgetRepository(this._db);

  final SupabaseClient _db;

  /// The plan for [period], or null when none exists yet — which is precisely
  /// the signal the router uses to send the user into onboarding.
  Future<MonthlyBudget?> budgetFor(Period period) async {
    try {
      final row = await _db
          .from('monthly_budgets')
          .select()
          .eq('period', period.isoDate)
          .maybeSingle();
      return row == null ? null : MonthlyBudget.fromJson(row);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<BudgetSummary?> summaryFor(Period period) async {
    try {
      final row = await _db
          .from('v_budget_summary')
          .select()
          .eq('period', period.isoDate)
          .maybeSingle();
      return row == null ? null : BudgetSummary.fromJson(row);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<List<CategorySpend>> categoriesFor(String budgetId) async {
    try {
      final rows = await _db
          .from('v_category_spend')
          .select()
          .eq('budget_id', budgetId)
          .order('sort_order');
      return rows.map(CategorySpend.fromJson).toList();
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Every month the user has ever planned, newest first. Drives the ledger's
  /// month switcher and the streak calculation.
  Future<List<MonthlyBudget>> allBudgets() async {
    try {
      final rows = await _db
          .from('monthly_budgets')
          .select()
          .order('period', ascending: false);
      return rows.map(MonthlyBudget.fromJson).toList();
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<List<BudgetSummary>> allSummaries() async {
    try {
      final rows = await _db
          .from('v_budget_summary')
          .select()
          .order('period', ascending: false);
      return rows.map(BudgetSummary.fromJson).toList();
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Creates a month's plan and all its categories in one transaction.
  ///
  /// Goes through the `fn_create_month_budget` RPC rather than inserting the
  /// budget and then its categories: as two calls, a dropped connection between
  /// them leaves a plan with no categories, and the dashboard would render a
  /// budget that silently does not add up. The function also refuses an
  /// allocation that does not sum to spendable income, so the Dart allocator and
  /// the database cannot drift apart without someone noticing.
  Future<String> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    required List<Allocation<CategoryTemplate>> allocations,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
  }) async {
    try {
      final result = await _db.rpc<String>(
        'fn_create_month_budget',
        params: {
          'p_period': period.isoDate,
          'p_income_minor': income.minor,
          'p_savings_mode': savingsMode.name,
          'p_savings_percent': savingsPercent,
          'p_savings_target_minor': savingsTarget.minor,
          'p_investment_target_minor': investmentTarget?.minor,
          'p_carried_from_period': carriedFrom?.isoDate,
          'p_categories': [
            for (var i = 0; i < allocations.length; i++)
              {
                'category_key': allocations[i].key.key,
                'display_name': allocations[i].key.name,
                'icon': allocations[i].key.icon,
                'allocated_minor': allocations[i].amount.minor,
                'allocated_percent': allocations[i].percent,
                'sort_order': i,
              },
          ],
        },
      );
      return result;
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Records that the user moved their savings.
  ///
  /// Writes both the confirmation stamp and a matching `savings_entries` row.
  /// The stamp drives the reminder card; the entry is what the streak and the
  /// emergency-fund ratio are computed from. Setting only the stamp would make
  /// the card go green while the unlock never progressed.
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  }) async {
    try {
      await _db.from('savings_entries').insert({
        'user_id': _db.auth.currentUser!.id,
        'budget_id': budgetId,
        'amount_minor': amount.minor,
        'destination': destination,
      });
      await _db
          .from('monthly_budgets')
          .update({
            'savings_confirmed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', budgetId);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Adjusts a single category's allocation.
  ///
  /// Deliberately does not rebalance the others. The PRD suggests a source when
  /// a category overspends, but moving money without being asked would rewrite
  /// a plan the user made; the suggestion is a suggestion.
  Future<void> updateCategoryAllocation({
    required String categoryId,
    required Money allocated,
    required double percent,
  }) async {
    try {
      await _db
          .from('budget_categories')
          .update({
            'allocated_minor': allocated.minor,
            'allocated_percent': percent,
          })
          .eq('id', categoryId);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }
}
