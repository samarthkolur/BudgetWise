import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/db/owned_collection.dart';
import 'package:budgetwise_server/src/domain_errors.dart';
import 'package:mongo_dart/mongo_dart.dart';

class ExpenseRepository {
  ExpenseRepository(this._mongo, this.ownerId);

  final Mongo _mongo;
  final ObjectId ownerId;

  OwnedCollection get _expenses =>
      OwnedCollection(_mongo.collection(Col.expenses), ownerId);
  OwnedCollection get _categories =>
      OwnedCollection(_mongo.collection(Col.categories), ownerId);
  OwnedCollection get _budgets =>
      OwnedCollection(_mongo.collection(Col.budgets), ownerId);

  Future<List<Map<String, dynamic>>> forBudget(ObjectId budgetId) async {
    if (!await _budgets.owns(budgetId)) {
      throw const NotOwnedException('budget');
    }
    final rows = await _expenses.find(
      where: {'budgetId': budgetId},
      sort: {'spentOn': -1, 'createdAt': -1},
    );

    // The SQL version got category name and icon through a join. Mongo has no
    // joins worth using here, so one extra query fetches the whole category set
    // for the month and the rows are decorated in memory — cheaper than
    // $lookup per document, and there are at most a dozen categories.
    final categories = await _categories.find(where: {'budgetId': budgetId});
    final byId = {
      for (final c in categories) (c['_id'] as ObjectId).oid: c,
    };

    return [
      for (final row in rows)
        {...row, 'category': byId[(row['categoryId'] as ObjectId).oid]},
    ];
  }

  /// Adds an expense.
  ///
  /// Both parents are checked before the write. Postgres enforced this with
  /// composite foreign keys — `(budget_id, user_id)` and `(category_id,
  /// user_id)` — which made it impossible to attach a row you own to a budget
  /// you do not. Mongo has no foreign keys at all, so these two checks are the
  /// entire defence, and the cross-user test asserts them directly.
  Future<Map<String, dynamic>> add({
    required ObjectId budgetId,
    required ObjectId categoryId,
    required Money amount,
    required DateTime spentOn,
    required String paymentMethod,
    String? note,
  }) async {
    if (!amount.isPositive) {
      throw const ValidationException('Enter an amount greater than zero');
    }
    if (!await _budgets.owns(budgetId)) {
      throw const NotOwnedException('budget');
    }
    if (!await _categories.owns(categoryId)) {
      throw const NotOwnedException('category');
    }

    return _expenses.insert({
      'budgetId': budgetId,
      'categoryId': categoryId,
      'amountMinor': amount.minor,
      // Date only, at UTC midnight. The time an expense was entered is not the
      // day it belongs to; storing the instant would put a purchase logged at
      // 00:30 on the wrong day in some timezones.
      'spentOn': DateTime.utc(spentOn.year, spentOn.month, spentOn.day),
      'paymentMethod': paymentMethod,
      'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    });
  }

  Future<Map<String, dynamic>?> update({
    required ObjectId id,
    required ObjectId categoryId,
    required Money amount,
    required DateTime spentOn,
    required String paymentMethod,
    String? note,
  }) async {
    if (!amount.isPositive) {
      throw const ValidationException('Enter an amount greater than zero');
    }
    if (!await _categories.owns(categoryId)) {
      throw const NotOwnedException('category');
    }
    return _expenses.updateById(id, {
      'categoryId': categoryId,
      'amountMinor': amount.minor,
      'spentOn': DateTime.utc(spentOn.year, spentOn.month, spentOn.day),
      'paymentMethod': paymentMethod,
      'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    });
  }

  Future<bool> delete(ObjectId id) => _expenses.deleteById(id);

  /// Average monthly spend on essentials, across completed months only.
  ///
  /// The denominator of the emergency-fund ratio. The current month is excluded
  /// because it is partial, and including it would understate the average and
  /// make the cushion look larger than it is.
  Future<Money> averageMonthlyEssentials() async {
    final categories = await _categories.find();
    final essentialIds = <ObjectId>[
      for (final c in categories)
        if (kEssentialCategoryKeys.contains(c['categoryKey']))
          c['_id'] as ObjectId,
    ];
    if (essentialIds.isEmpty) return const Money.zero();

    final budgets = await OwnedCollection(
      _mongo.collection(Col.budgets),
      ownerId,
    ).find();
    final current = Period.current();
    final completed = <ObjectId, String>{
      for (final b in budgets)
        if (Period.parse(b['period'] as String).isBefore(current))
          b['_id'] as ObjectId: b['period'] as String,
    };
    if (completed.isEmpty) return const Money.zero();

    final pipeline = <Map<String, Object>>[
      {
        r'$match': {
          'ownerId': ownerId,
          'categoryId': {r'$in': essentialIds},
          'budgetId': {r'$in': completed.keys.toList()},
        },
      },
      {
        r'$group': {
          '_id': r'$budgetId',
          'total': {r'$sum': r'$amountMinor'},
        },
      },
    ];

    final rows = await _mongo
        .collection(Col.expenses)
        .aggregateToStream(pipeline)
        .toList();
    if (rows.isEmpty) return const Money.zero();

    final total = rows.fold<int>(0, (a, r) => a + (r['total'] as num).toInt());
    return Money(total ~/ rows.length);
  }
}

/// Categories a person cannot simply stop paying, which is what makes three
/// months of them a meaningful emergency fund.
const kEssentialCategoryKeys = {'food', 'transport', 'bills', 'healthcare'};
