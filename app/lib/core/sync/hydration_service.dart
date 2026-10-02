import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:sqflite/sqflite.dart';

/// Pulls a freshly signed-in account's server data down into the local
/// database once, so the local fallback `Syncing*Repository` reads use when
/// offline has something real in it from the very first sign-in — rather than
/// staying empty until the first successful write happens to touch each
/// table.
///
/// Not a general-purpose two-way sync: this only ever writes server data
/// *into* local tables, upserting by id (`ConflictAlgorithm.replace`), and
/// only runs right after sign-in. Every write made afterward is kept current
/// in local storage by the `Syncing*Repository` classes themselves.
class HydrationService {
  HydrationService({required ApiClient api, required Future<LocalDatabase> dbFuture})
    : _api = api,
      _dbFuture = dbFuture;

  final ApiClient _api;
  final Future<LocalDatabase> _dbFuture;

  Future<void> hydrate() async {
    final db = (await _dbFuture).db;

    final profileRow = await _api.get('/v1/me') as Map<String, dynamic>?;
    if (profileRow != null) {
      await _hydrateProfile(db, Profile.fromJson(profileRow));
    }

    final budgetRows = await _api.get('/v1/budgets') as List;
    for (final row in budgetRows) {
      final budget = MonthlyBudget.fromJson(row as Map<String, dynamic>);
      await _upsertBudget(db, budget);

      final expenseRows =
          await _api.get('/v1/budgets/${budget.id}/expenses') as List;
      for (final expenseRow in expenseRows) {
        await _upsertExpense(
          db,
          Expense.fromJson(expenseRow as Map<String, dynamic>),
        );
      }
    }

    final goalRows = await _api.get('/v1/goals') as List;
    for (final row in goalRows) {
      await _upsertGoal(db, Goal.fromJson(row as Map<String, dynamic>));
    }
  }

  Future<void> _hydrateProfile(Database db, Profile profile) async {
    await db.delete('local_profile');
    await db.insert('local_profile', {
      'id': profile.id,
      'email': profile.email,
      'display_name': profile.displayName,
      'avatar_url': profile.avatarUrl,
      'currency': profile.currency,
      'locale': profile.locale,
      'onboarding_completed_at': profile.onboardingCompletedAt
          ?.toIso8601String(),
      'investing_unlocked_at': profile.investingUnlockedAt?.toIso8601String(),
    });
  }

  Future<void> _upsertBudget(Database db, MonthlyBudget budget) async {
    await db.insert('budgets', {
      'id': budget.id,
      'period': budget.period.isoDate,
      'income_minor': budget.income.minor,
      'savings_target_minor': budget.savingsTarget.minor,
      'savings_mode': budget.savingsMode.name,
      'savings_percent': budget.savingsPercent,
      'investment_target_minor': budget.investmentTarget?.minor,
      'savings_confirmed_at': budget.savingsConfirmedAt?.toIso8601String(),
      'status': budget.status,
      'carried_from_period': budget.carriedFromPeriod?.isoDate,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertExpense(Database db, Expense expense) async {
    await db.insert('expenses', {
      'id': expense.id,
      'budget_id': expense.budgetId,
      'amount_minor': expense.amount.minor,
      'spent_on': expense.spentOn.toIso8601String().substring(0, 10),
      'payment_method': expense.paymentMethod.name,
      'note': expense.note,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertGoal(Database db, Goal goal) async {
    await db.insert('goals', {
      'id': goal.id,
      'title': goal.title,
      'target_minor': goal.target.minor,
      'saved_minor': goal.saved.minor,
      'status': goal.status,
      'icon': goal.icon,
      'target_date': goal.targetDate?.toIso8601String(),
      'monthly_contribution_minor': goal.monthlyContribution?.minor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
