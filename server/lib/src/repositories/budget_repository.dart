import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/db/owned_collection.dart';
import 'package:budgetwise_server/src/domain_errors.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// Budgets, categories and the derived views the dashboard reads.
///
/// A relational schema would do this work in views inside the database. Mongo has no views over aggregates that stay in step, so the
/// same arithmetic lives here — computed in one place and one place only, for
/// the same reason the views existed: two implementations of "how much is left"
/// eventually disagree, and nobody can say which is right.
class BudgetRepository {
  BudgetRepository(this._mongo, this.ownerId);

  final Mongo _mongo;
  final ObjectId ownerId;

  OwnedCollection get _budgets =>
      OwnedCollection(_mongo.collection(Col.budgets), ownerId);
  OwnedCollection get _categories =>
      OwnedCollection(_mongo.collection(Col.categories), ownerId);
  OwnedCollection get _expenses =>
      OwnedCollection(_mongo.collection(Col.expenses), ownerId);
  OwnedCollection get _savings =>
      OwnedCollection(_mongo.collection(Col.savings), ownerId);
  OwnedCollection get _investments =>
      OwnedCollection(_mongo.collection(Col.investments), ownerId);

  Future<Map<String, dynamic>?> budgetForPeriod(Period period) =>
      _budgets.findOne({'period': period.isoDate});

  Future<List<Map<String, dynamic>>> allBudgets() =>
      _budgets.find(sort: {'period': -1});

  /// Creates a month's plan and its categories together.
  ///
  /// A single database function would make this atomic by construction. Here the two writes are separate, and a standalone
  /// mongod cannot run a transaction — so the budget is inserted first and the
  /// categories second, with the budget removed again if the categories fail.
  /// That is a compensating action rather than a real rollback: it closes the
  /// window that would otherwise leave a plan with no categories, which is the
  /// state the dashboard cannot render honestly.
  ///
  /// The allocation total is validated here, against the *same* largest-
  /// remainder arithmetic the client used, because both sides import
  /// `budgetwise_domain`. That is the point of the shared package.
  Future<Map<String, dynamic>> createMonth({
    required Period period,
    required Money income,
    required SavingsMode savingsMode,
    required Money savingsTarget,
    required List<Map<String, dynamic>> categories,
    double? savingsPercent,
    Money? investmentTarget,
    Period? carriedFrom,
  }) async {
    if (savingsTarget > income) {
      throw const ValidationException('Savings cannot be more than income');
    }

    final spendable = spendableIncome(
      income: income,
      savingsTarget: savingsTarget,
      investmentTarget: investmentTarget ?? const Money.zero(),
    );

    final allocated = categories.fold<int>(
      0,
      (sum, c) => sum + ((c['allocatedMinor'] as num?)?.toInt() ?? 0),
    );
    if (allocated != spendable.minor) {
      throw ValidationException(
        'Category allocations ($allocated) do not sum to spendable income '
        '(${spendable.minor})',
      );
    }

    if (await budgetForPeriod(period) != null) {
      throw ConflictException('A plan already exists for ${period.label}');
    }

    final budget = await _budgets.insert({
      'period': period.isoDate,
      'incomeMinor': income.minor,
      'savingsMode': savingsMode.name,
      'savingsPercent': savingsPercent,
      'savingsTargetMinor': savingsTarget.minor,
      'investmentTargetMinor': investmentTarget?.minor,
      'savingsConfirmedAt': null,
      'status': 'active',
      'carriedFromPeriod': carriedFrom?.isoDate,
    });

    try {
      await _categories.insertMany([
        for (var i = 0; i < categories.length; i++)
          {
            'budgetId': budget['_id'],
            'categoryKey': categories[i]['categoryKey'],
            'displayName': categories[i]['displayName'],
            'icon': categories[i]['icon'],
            'allocatedMinor': categories[i]['allocatedMinor'],
            'allocatedPercent': categories[i]['allocatedPercent'],
            'sortOrder': categories[i]['sortOrder'] ?? i,
          },
      ]);
    } on Object catch (_) {
      await _budgets.deleteById(budget['_id'] as ObjectId);
      rethrow;
    }

    return budget;
  }

  /// `v_category_spend`, recomputed.
  Future<List<Map<String, dynamic>>> categorySpend(ObjectId budgetId) async {
    if (!await _budgets.owns(budgetId)) {
      throw const NotOwnedException('budget');
    }

    final categories = await _categories.find(
      where: {'budgetId': budgetId},
      sort: {'sortOrder': 1},
    );

    final spendByCategory = await _spentByCategory(budgetId);

    return [
      for (final category in categories)
        _withSpend(
          category,
          spendByCategory[(category['_id'] as ObjectId).oid] ?? 0,
        ),
    ];
  }

  Map<String, dynamic> _withSpend(Map<String, dynamic> category, int spent) {
    final allocated = (category['allocatedMinor'] as num?)?.toInt() ?? 0;
    return {
      'categoryId': (category['_id'] as ObjectId).oid,
      'budgetId': (category['budgetId'] as ObjectId).oid,
      'categoryKey': category['categoryKey'],
      'displayName': category['displayName'],
      'icon': category['icon'],
      'sortOrder': category['sortOrder'] ?? 0,
      'allocatedMinor': allocated,
      'allocatedPercent': category['allocatedPercent'] ?? 0,
      'spentMinor': spent,
      'remainingMinor': allocated - spent > 0 ? allocated - spent : 0,
      'overspendMinor': spent - allocated > 0 ? spent - allocated : 0,
      // Guarded: a zero allocation must read as 0% used, not as a division by
      // zero rendering a full red bar on a category nobody budgeted for.
      'pctUsed': allocated == 0 ? 0.0 : spent / allocated,
      'expenseCount': category['expenseCount'] ?? 0,
    };
  }

  Future<Map<String, int>> _spentByCategory(ObjectId budgetId) async {
    final pipeline = <Map<String, Object>>[
      {
        r'$match': {'ownerId': ownerId, 'budgetId': budgetId},
      },
      {
        r'$group': {
          '_id': r'$categoryId',
          'total': {r'$sum': r'$amountMinor'},
        },
      },
    ];
    final rows = await _mongo
        .collection(Col.expenses)
        .aggregateToStream(pipeline)
        .toList();
    return {
      for (final row in rows)
        (row['_id'] as ObjectId).oid: (row['total'] as num).toInt(),
    };
  }

  /// `v_budget_summary`, recomputed.
  Future<Map<String, dynamic>?> summaryForPeriod(Period period) async {
    final budget = await budgetForPeriod(period);
    if (budget == null) return null;
    return summaryFor(budget);
  }

  Future<Map<String, dynamic>> summaryFor(Map<String, dynamic> budget) async {
    final budgetId = budget['_id'] as ObjectId;

    final spent = await _expenses.sum('amountMinor', {'budgetId': budgetId});
    final saved = await _savings.sum('amountMinor', {'budgetId': budgetId});
    final invested = await _investments.sum('amountMinor', {
      'budgetId': budgetId,
    });
    final allocated = await _categories.sum('allocatedMinor', {
      'budgetId': budgetId,
    });
    final categoryCount = await _categories.count({'budgetId': budgetId});
    final expenseCount = await _expenses.count({'budgetId': budgetId});
    final daysLogged = await _distinctExpenseDays(budgetId);

    final income = (budget['incomeMinor'] as num).toInt();
    final savingsTarget = (budget['savingsTargetMinor'] as num).toInt();
    final investmentTarget = (budget['investmentTargetMinor'] as num?)?.toInt();

    final spendable = income - savingsTarget - (investmentTarget ?? 0) > 0
        ? income - savingsTarget - (investmentTarget ?? 0)
        : 0;
    final remaining = spendable - spent > 0 ? spendable - spent : 0;

    return {
      'budgetId': budgetId.oid,
      'period': budget['period'],
      'status': budget['status'],
      'incomeMinor': income,
      'savingsMode': budget['savingsMode'],
      'savingsPercent': budget['savingsPercent'],
      'savingsTargetMinor': savingsTarget,
      'investmentTargetMinor': investmentTarget,
      'savingsConfirmedAt': (budget['savingsConfirmedAt'] as DateTime?)
          ?.toUtc()
          .toIso8601String(),
      'allocatedMinor': allocated,
      'categoryCount': categoryCount,
      'spentMinor': spent,
      'expenseCount': expenseCount,
      'savedMinor': saved,
      'investedMinor': invested,
      'daysWithExpenses': daysLogged,
      'spendableMinor': spendable,
      'remainingMinor': remaining,
    };
  }

  Future<List<Map<String, dynamic>>> allSummaries() async {
    final budgets = await allBudgets();
    return [for (final budget in budgets) await summaryFor(budget)];
  }

  Future<int> _distinctExpenseDays(ObjectId budgetId) async {
    final pipeline = <Map<String, Object>>[
      {
        r'$match': {'ownerId': ownerId, 'budgetId': budgetId},
      },
      {
        r'$group': {'_id': r'$spentOn'},
      },
      {
        r'$count': 'days',
      },
    ];
    final rows = await _mongo
        .collection(Col.expenses)
        .aggregateToStream(pipeline)
        .toList();
    return rows.isEmpty ? 0 : (rows.first['days'] as num).toInt();
  }

  /// Records that the user moved their savings.
  ///
  /// Writes the entry AND the confirmation stamp. The stamp drives the reminder
  /// card; the entry is what the streak and emergency-fund ratio are computed
  /// from. Setting only the stamp would turn the card green while the investing
  /// unlock never progressed.
  Future<void> confirmSavings({
    required ObjectId budgetId,
    required Money amount,
    String destination = 'bank',
  }) async {
    if (!await _budgets.owns(budgetId)) {
      throw const NotOwnedException('budget');
    }
    await _savings.insert({
      'budgetId': budgetId,
      'amountMinor': amount.minor,
      'savedOn': DateTime.now().toUtc(),
      'destination': destination,
    });
    await _budgets.updateById(budgetId, {
      'savingsConfirmedAt': DateTime.now().toUtc(),
    });
  }

  Future<Map<String, dynamic>?> updateCategoryAllocation({
    required ObjectId categoryId,
    required Money allocated,
    required double percent,
  }) => _categories.updateById(categoryId, {
    'allocatedMinor': allocated.minor,
    'allocatedPercent': percent,
  });
}
