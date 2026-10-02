import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/sync/sync_queue_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Local-first [GoalRepository], used in place of a bare [ApiGoalRepository]
/// whenever a session exists. See `SyncingExpenseRepository` for the full
/// write/read design this mirrors.
class SyncingGoalRepository implements GoalRepository {
  SyncingGoalRepository({
    required GoalRepository local,
    required GoalRepository remote,
    required SyncQueueRepository queue,
  }) : _local = local,
       _remote = remote,
       _queue = queue;

  final GoalRepository _local;
  final GoalRepository _remote;
  final SyncQueueRepository _queue;

  @override
  Future<List<Goal>> all() async {
    try {
      return await _remote.all();
    } on NetworkFailure {
      return _local.all();
    }
  }

  @override
  Future<Goal> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
    String? id,
  }) async {
    final resolvedId = id ?? const Uuid().v4();
    final goal = await _local.create(
      title: title,
      target: target,
      targetDate: targetDate,
      monthlyContribution: monthlyContribution,
      icon: icon,
      id: resolvedId,
    );
    try {
      await _remote.create(
        title: title,
        target: target,
        targetDate: targetDate,
        monthlyContribution: monthlyContribution,
        icon: icon,
        id: resolvedId,
      );
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'goal',
        entityId: resolvedId,
        operation: 'create',
        payload: {
          'id': resolvedId,
          'title': title,
          'targetMinor': target.minor,
          'targetDate': targetDate?.toUtc().toIso8601String(),
          'monthlyContributionMinor': monthlyContribution?.minor,
          'icon': icon,
        },
      );
    }
    return goal;
  }

  @override
  Future<void> contribute({
    required String goalId,
    required Money amount,
    String? budgetId,
  }) async {
    await _local.contribute(goalId: goalId, amount: amount, budgetId: budgetId);
    try {
      await _remote.contribute(
        goalId: goalId,
        amount: amount,
        budgetId: budgetId,
      );
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'goal',
        entityId: goalId,
        operation: 'contribute',
        payload: {'amountMinor': amount.minor, 'budgetId': budgetId},
      );
    }
  }

  @override
  Future<void> delete(String goalId) async {
    await _local.delete(goalId);
    try {
      await _remote.delete(goalId);
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'goal',
        entityId: goalId,
        operation: 'delete',
        payload: const {},
      );
    }
  }
}
