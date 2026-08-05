import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/db/owned_collection.dart';
import 'package:budgetwise_server/src/domain_errors.dart';
import 'package:mongo_dart/mongo_dart.dart';

class GoalRepository {
  GoalRepository(this._mongo, this.ownerId);

  final Mongo _mongo;
  final ObjectId ownerId;

  OwnedCollection get _goals =>
      OwnedCollection(_mongo.collection(Col.goals), ownerId);
  OwnedCollection get _contributions =>
      OwnedCollection(_mongo.collection(Col.goalContributions), ownerId);

  Future<List<Map<String, dynamic>>> all() =>
      _goals.find(sort: {'createdAt': 1});

  Future<Map<String, dynamic>> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
  }) async {
    if (!target.isPositive) {
      throw const ValidationException('A goal needs a target above zero');
    }
    return _goals.insert({
      'title': title.trim(),
      'targetMinor': target.minor,
      'savedMinor': 0,
      'targetDate': targetDate == null
          ? null
          : DateTime.utc(targetDate.year, targetDate.month, targetDate.day),
      'monthlyContributionMinor': monthlyContribution?.minor,
      'icon': icon,
      'status': 'active',
    });
  }

  /// Adds money to a goal and recomputes its total.
  ///
  /// A relational schema kept the saved total in step with a trigger that summed the
  /// contributions rather than incrementing — so an edit or a delete could not
  /// drift the total. Mongo has no triggers, so [_recomputeSaved] does the same
  /// job and is called from every path that changes a contribution. Incrementing
  /// with `$inc` would be one query cheaper and would drift the first time a
  /// contribution was removed.
  Future<void> contribute({
    required ObjectId goalId,
    required Money amount,
    ObjectId? budgetId,
  }) async {
    if (!amount.isPositive) {
      throw const ValidationException('Enter an amount greater than zero');
    }
    if (!await _goals.owns(goalId)) {
      throw const NotOwnedException('goal');
    }
    await _contributions.insert({
      'goalId': goalId,
      'budgetId': budgetId,
      'amountMinor': amount.minor,
      'contributedOn': DateTime.now().toUtc(),
    });
    await _recomputeSaved(goalId);
  }

  Future<void> removeContribution(ObjectId contributionId) async {
    final contribution = await _contributions.findById(contributionId);
    if (contribution == null) return;
    await _contributions.deleteById(contributionId);
    await _recomputeSaved(contribution['goalId'] as ObjectId);
  }

  Future<void> _recomputeSaved(ObjectId goalId) async {
    final total = await _contributions.sum('amountMinor', {'goalId': goalId});
    final goal = await _goals.findById(goalId);
    if (goal == null) return;

    final target = (goal['targetMinor'] as num).toInt();
    final status = goal['status'] == 'abandoned'
        ? 'abandoned'
        : total >= target
        ? 'achieved'
        : 'active';

    await _goals.updateById(goalId, {'savedMinor': total, 'status': status});
  }

  Future<bool> delete(ObjectId goalId) async {
    await _contributions.deleteWhere({'goalId': goalId});
    return _goals.deleteById(goalId);
  }

  Future<Map<String, dynamic>?> abandon(ObjectId goalId) =>
      _goals.updateById(goalId, {'status': 'abandoned'});
}
