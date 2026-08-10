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
  Future<List<CategorySpend>> categoriesFor(String budgetId);
  Future<List<MonthlyBudget>> allBudgets();
  Future<List<BudgetSummary>> allSummaries();
  Future<MonthlyBudget> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    required List<Allocation<CategoryTemplate>> allocations,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
  });
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  });
  Future<void> updateCategoryAllocation({
    required String categoryId,
    required Money allocated,
    required double percent,
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
  Future<List<CategorySpend>> categoriesFor(String budgetId) async =>
      guarded(() async {
        final rows = await _api.get('/v1/budgets/$budgetId/categories') as List;
        return rows
            .map((r) => CategorySpend.fromJson(r as Map<String, dynamic>))
            .toList();
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

  /// Creates a month's plan and all its categories in one request.
  ///
  /// One call, not two: the server writes the budget and its categories
  /// together, and refuses an allocation that does not sum to spendable income
  /// using the same largest-remainder arithmetic this app used to build it —
  /// both sides import budgetwise_domain, so they cannot drift.
  @override
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

  @override
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

/// Talks to the on-device database, used whenever no one is signed in.
///
/// A repository's job is fetching and mapping, not computing business rules —
/// the same boundary the API repository sits on. The category/expense
/// aggregation below (`SUM`, `GROUP BY`, `COUNT DISTINCT`) is the SQL
/// equivalent of the API's JSON response shape, not budget arithmetic; the
/// actual arithmetic — [CategoryProgress], [spendableIncome], safe-daily-spend
/// — stays in `budgetwise_domain` and is reached through the models exactly as
/// it already is for API data.
class LocalBudgetRepository implements BudgetRepository {
  LocalBudgetRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  @override
  Future<MonthlyBudget?> currentBudget() =>
      _budgetForPeriod(Period.current());

  @override
  Future<BudgetSummary?> summaryFor(Period period) async {
    final budget = await _budgetForPeriod(period);
    if (budget == null) return null;
    final db = (await _dbFuture).db;

    final categoryTotals = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(allocated_minor), 0) AS total '
      'FROM categories WHERE budget_id = ?',
      [budget.id],
    );
    final expenseTotals = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(amount_minor), 0) AS total, '
      'COUNT(DISTINCT spent_on) AS days FROM expenses WHERE budget_id = ?',
      [budget.id],
    );

    final allocated = Money(categoryTotals.first['total']! as int);
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
      allocated: allocated,
      spent: spent,
      spendable: budget.spendable,
      remaining: (budget.spendable - spent).orZeroIfNegative,
      // Investing is a server-verified achievement (see LocalProfileRepository)
      // — there is nothing locally to have invested yet.
      investedActual: const Money.zero(),
      investmentTarget: budget.investmentTarget,
      categoryCount: categoryTotals.first['cnt']! as int,
      expenseCount: expenseTotals.first['cnt']! as int,
      daysWithExpenses: expenseTotals.first['days']! as int,
      savingsConfirmedAt: budget.savingsConfirmedAt,
    );
  }

  @override
  Future<List<CategorySpend>> categoriesFor(String budgetId) async {
    final db = (await _dbFuture).db;
    final rows = await db.query(
      'categories',
      where: 'budget_id = ?',
      whereArgs: [budgetId],
      orderBy: 'sort_order',
    );
    final spentRows = await db.rawQuery(
      'SELECT category_id, COALESCE(SUM(amount_minor), 0) AS total, '
      'COUNT(*) AS cnt FROM expenses WHERE budget_id = ? GROUP BY category_id',
      [budgetId],
    );
    final spentByCategory = {
      for (final r in spentRows) r['category_id']! as String: r['total']! as int,
    };
    final countByCategory = {
      for (final r in spentRows) r['category_id']! as String: r['cnt']! as int,
    };

    return [
      for (final row in rows)
        CategorySpend(
          id: row['id']! as String,
          budgetId: row['budget_id']! as String,
          key: row['key']! as String,
          name: row['name']! as String,
          icon: row['icon']! as String,
          allocated: Money(row['allocated_minor']! as int),
          spent: Money(spentByCategory[row['id']] ?? 0),
          allocatedPercent: (row['allocated_percent']! as num).toDouble(),
          expenseCount: countByCategory[row['id']] ?? 0,
          sortOrder: row['sort_order']! as int,
        ),
    ];
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
    required List<Allocation<CategoryTemplate>> allocations,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
  }) async {
    final db = (await _dbFuture).db;
    const uuid = Uuid();
    final budget = MonthlyBudget(
      id: uuid.v4(),
      period: period,
      income: income,
      savingsTarget: savingsTarget,
      savingsMode: savingsMode,
      savingsPercent: savingsPercent,
      investmentTarget: investmentTarget,
      carriedFromPeriod: carriedFrom,
    );

    await db.insert('budgets', _budgetToRow(budget));
    for (var i = 0; i < allocations.length; i++) {
      final allocation = allocations[i];
      await db.insert('categories', {
        'id': uuid.v4(),
        'budget_id': budget.id,
        'key': allocation.key.key,
        'name': allocation.key.name,
        'icon': allocation.key.icon,
        'allocated_minor': allocation.amount.minor,
        'allocated_percent': allocation.percent,
        'sort_order': i,
      });
    }
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

  @override
  Future<void> updateCategoryAllocation({
    required String categoryId,
    required Money allocated,
    required double percent,
  }) async {
    final db = (await _dbFuture).db;
    await db.update(
      'categories',
      {'allocated_minor': allocated.minor, 'allocated_percent': percent},
      where: 'id = ?',
      whereArgs: [categoryId],
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
