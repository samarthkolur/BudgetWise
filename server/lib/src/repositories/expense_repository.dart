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
  OwnedCollection get _budgets =>
      OwnedCollection(_mongo.collection(Col.budgets), ownerId);

  Future<List<Map<String, dynamic>>> forBudget(ObjectId budgetId) async {
    if (!await _budgets.owns(budgetId)) {
      throw const NotOwnedException('budget');
    }
    return _expenses.find(
      where: {'budgetId': budgetId},
      sort: {'spentOn': -1, 'createdAt': -1},
    );
  }

  /// Adds an expense.
  ///
  /// The parent budget is checked before the write. A relational schema
  /// enforced this with a composite foreign key — `(budget_id, user_id)` —
  /// which made it impossible to attach a row you own to a budget you do
  /// not. Mongo has no foreign keys at all, so this check is the entire
  /// defence, and the cross-user test asserts it directly.
  Future<Map<String, dynamic>> add({
    required ObjectId budgetId,
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

    return _expenses.insert({
      'budgetId': budgetId,
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
    required Money amount,
    required DateTime spentOn,
    required String paymentMethod,
    String? note,
  }) async {
    if (!amount.isPositive) {
      throw const ValidationException('Enter an amount greater than zero');
    }
    return _expenses.updateById(id, {
      'amountMinor': amount.minor,
      'spentOn': DateTime.utc(spentOn.year, spentOn.month, spentOn.day),
      'paymentMethod': paymentMethod,
      'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    });
  }

  Future<bool> delete(ObjectId id) => _expenses.deleteById(id);

  /// Average total monthly spend, across completed months only.
  ///
  /// The denominator of the emergency-fund ratio. Used to stand in for
  /// "essential" spend now that there are no categories to isolate
  /// essentials from the rest — a conservative substitution, since total
  /// spend is never less than essential-only spend would have been, which
  /// only makes the unlock harder to reach, never easier. The current month
  /// is excluded because it is partial, and including it would understate
  /// the average and make the cushion look larger than it is.
  Future<Money> averageMonthlySpend() async {
    final budgets = await _budgets.find();
    final current = Period.current();
    final completed = <ObjectId>[
      for (final b in budgets)
        if (Period.parse(b['period'] as String).isBefore(current))
          b['_id'] as ObjectId,
    ];
    if (completed.isEmpty) return const Money.zero();

    final pipeline = <Map<String, Object>>[
      {
        r'$match': {
          'ownerId': ownerId,
          'budgetId': {r'$in': completed},
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
