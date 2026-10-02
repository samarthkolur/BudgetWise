import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Every read and write of a month's plan. Two implementations:
/// [ApiBudgetRepository] talks to the server, [LocalBudgetRepository] talks
/// to the on-device database. Neither the providers nor the screens that
/// consume this interface know or care which one they got.
abstract class BudgetRepository {
  Future<MonthlyBudget?> currentBudget();
  Future<BudgetSummary?> summaryFor(Period period);
  Future<List<MonthlyBudget>> allBudgets();
  Future<List<BudgetSummary>> allSummaries();
  Future<MonthlyBudget> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
    String? id,
  });
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  });
}

/// Talks to the API. The only layer that knows the API's URL shapes. Note
/// what is absent: no owner or user id anywhere. The server derives it from
/// the access token, and sending one from here would be both redundant and a
/// lie the server ignores.
class ApiBudgetRepository implements BudgetRepository {
  ApiBudgetRepository(this._api);

  final ApiClient _api;

  /// The plan for the current month, or null when none exists yet — which is
  /// precisely the signal the router uses to send the user into onboarding.
  @override
  Future<MonthlyBudget?> currentBudget() async => guarded(() async {
    final row = await _api.get('/v1/budgets/current');
    return row == null
        ? null
        : MonthlyBudget.fromJson(row as Map<String, dynamic>);
  });

  @override
  Future<BudgetSummary?> summaryFor(Period period) async => guarded(() async {
    final row = await _api.get('/v1/summaries/${period.isoDate}');
    return row == null
        ? null
        : BudgetSummary.fromJson(row as Map<String, dynamic>);
  });

  @override
  Future<List<MonthlyBudget>> allBudgets() async => guarded(() async {
    final rows = await _api.get('/v1/budgets') as List;
    return rows
        .map((r) => MonthlyBudget.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  @override
  Future<List<BudgetSummary>> allSummaries() async => guarded(() async {
    final rows = await _api.get('/v1/summaries') as List;
    return rows
        .map((r) => BudgetSummary.fromJson(r as Map<String, dynamic>))
        .toList();
  });

  /// [id] is only passed by `SyncingBudgetRepository`, replaying a month that
  /// was already written locally while offline — see the matching note on
  /// `ApiExpenseRepository.add`.
  @override
  Future<MonthlyBudget> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
    String? id,
  }) async => guarded(() async {
    final row =
        await _api.post('/v1/budgets', {
              if (id != null) 'id': id,
              'period': period.isoDate,
              'incomeMinor': income.minor,
              'savingsMode': savingsMode.name,
              'savingsPercent': savingsPercent,
              'savingsTargetMinor': savingsTarget.minor,
              'investmentTargetMinor': investmentTarget?.minor,
              'carriedFromPeriod': carriedFrom?.isoDate,
            })
            as Map<String, dynamic>;
    return MonthlyBudget.fromJson(row);
  });

  /// Records that the user moved their savings.
  ///
  /// The server writes both the confirmation stamp and the savings entry. The
  /// stamp drives the reminder card; the entry is what the streak and the
  /// emergency-fund ratio are computed from.
  @override
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
}

/// Talks to the on-device database, used whenever no one is signed in.
///
/// A repository's job is fetching and mapping, not computing business rules —
/// the same boundary the API repository sits on. The expense aggregation
/// below (`SUM`, `COUNT DISTINCT`) is the SQL equivalent of the API's JSON
/// response shape, not budget arithmetic; the actual arithmetic —
/// [spendableIncome], safe-daily-spend — stays in `budgetwise_domain` and is
/// reached through the models exactly as it already is for API data.
class LocalBudgetRepository implements BudgetRepository {
  LocalBudgetRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  @override
  Future<MonthlyBudget?> currentBudget() => _budgetForPeriod(Period.current());

  @override
  Future<BudgetSummary?> summaryFor(Period period) async {
    final budget = await _budgetForPeriod(period);
    if (budget == null) return null;
    final db = (await _dbFuture).db;

    final expenseTotals = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(amount_minor), 0) AS total, '
      'COUNT(DISTINCT spent_on) AS days FROM expenses WHERE budget_id = ?',
      [budget.id],
    );

    final spent = Money(expenseTotals.first['total']! as int);
    final savedActual = budget.isSavingsConfirmed
        ? budget.savingsTarget
        : const Money.zero();

    return BudgetSummary(
      budgetId: budget.id,
      period: budget.period,
      income: budget.income,
      savingsTarget: budget.savingsTarget,
      savedActual: savedActual,
      spent: spent,
      spendable: budget.spendable,
      remaining: (budget.spendable - spent).orZeroIfNegative,
      // Investing is a server-verified achievement (see LocalProfileRepository)
      // — there is nothing locally to have invested yet.
      investedActual: const Money.zero(),
      investmentTarget: budget.investmentTarget,
      expenseCount: expenseTotals.first['cnt']! as int,
      daysWithExpenses: expenseTotals.first['days']! as int,
      savingsConfirmedAt: budget.savingsConfirmedAt,
    );
  }

  @override
  Future<List<MonthlyBudget>> allBudgets() async {
    final db = (await _dbFuture).db;
    final rows = await db.query('budgets', orderBy: 'period DESC');
    return rows.map(_budgetFromRow).toList();
  }

  @override
  Future<List<BudgetSummary>> allSummaries() async {
    final budgets = await allBudgets();
    final summaries = <BudgetSummary>[];
    for (final budget in budgets) {
      final summary = await summaryFor(budget.period);
      if (summary != null) summaries.add(summary);
    }
    return summaries;
  }

  @override
  Future<MonthlyBudget> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
    String? id,
  }) async {
    final db = (await _dbFuture).db;
    const uuid = Uuid();
    final budget = MonthlyBudget(
      id: id ?? uuid.v4(),
      period: period,
      income: income,
      savingsTarget: savingsTarget,
      savingsMode: savingsMode,
      savingsPercent: savingsPercent,
      investmentTarget: investmentTarget,
      carriedFromPeriod: carriedFrom,
    );

    await db.insert('budgets', _budgetToRow(budget));
    return budget;
  }

  @override
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  }) async {
    final db = (await _dbFuture).db;
    await db.update(
      'budgets',
      {'savings_confirmed_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [budgetId],
    );
  }

  Future<MonthlyBudget?> _budgetForPeriod(Period period) async {
    final db = (await _dbFuture).db;
    final rows = await db.query(
      'budgets',
      where: 'period = ?',
      whereArgs: [period.isoDate],
      limit: 1,
    );
    return rows.isEmpty ? null : _budgetFromRow(rows.first);
  }

  static MonthlyBudget _budgetFromRow(Map<String, Object?> row) =>
      MonthlyBudget(
        id: row['id']! as String,
        period: Period.parse(row['period']! as String),
        income: Money(row['income_minor']! as int),
        savingsTarget: Money(row['savings_target_minor']! as int),
        savingsMode: SavingsMode.fromDb(row['savings_mode']! as String),
        savingsPercent: (row['savings_percent'] as num?)?.toDouble(),
        investmentTarget: row['investment_target_minor'] == null
            ? null
            : Money(row['investment_target_minor']! as int),
        savingsConfirmedAt: row['savings_confirmed_at'] == null
            ? null
            : DateTime.parse(row['savings_confirmed_at']! as String),
        status: row['status']! as String,
        carriedFromPeriod: row['carried_from_period'] == null
            ? null
            : Period.parse(row['carried_from_period']! as String),
      );

  static Map<String, Object?> _budgetToRow(MonthlyBudget budget) => {
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
  };
}
