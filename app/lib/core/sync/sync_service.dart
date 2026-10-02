import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/sync/sync_queue_repository.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';

/// What happened when the outbox was replayed — shown in the sync-now prompt.
class SyncResult {
  const SyncResult({
    required this.succeeded,
    required this.failed,
    required this.remaining,
  });

  final int succeeded;
  final int failed;

  /// Still queued afterward — either [failed] items left in place for the
  /// user to deal with, or everything, if a network failure meant the attempt
  /// stopped partway through.
  final int remaining;

  bool get isComplete => remaining == 0;
}

/// Replays the offline-write outbox against the real API repositories.
///
/// Takes the plain `Api*Repository` instances, not the `Syncing*` wrappers —
/// replaying through a wrapper would re-queue a still-offline failure back
/// onto the same outbox it was just read from.
class SyncService {
  SyncService({
    required SyncQueueRepository queue,
    required BudgetRepository apiBudgets,
    required ExpenseRepository apiExpenses,
    required GoalRepository apiGoals,
  }) : _queue = queue,
       _apiBudgets = apiBudgets,
       _apiExpenses = apiExpenses,
       _apiGoals = apiGoals;

  final SyncQueueRepository _queue;
  final BudgetRepository _apiBudgets;
  final ExpenseRepository _apiExpenses;
  final GoalRepository _apiGoals;

  /// Replays queued writes oldest-first, stopping at the first sign
  /// connectivity still isn't there (everything after it stays queued for the
  /// next attempt, in order) rather than burning through the whole queue
  /// against a server it has already failed to reach once.
  Future<SyncResult> syncPending() async {
    final items = await _queue.all();
    var succeeded = 0;
    var failed = 0;

    for (final item in items) {
      try {
        await _replay(item);
        await _queue.remove(item.id);
        succeeded++;
      } on NetworkFailure {
        break;
      } on Object {
        // The server has already refused this input once; leave it queued
        // for the user to resolve rather than retrying it forever.
        failed++;
      }
    }

    return SyncResult(
      succeeded: succeeded,
      failed: failed,
      remaining: await _queue.count(),
    );
  }

  Future<void> _replay(PendingSyncItem item) async {
    final payload = item.payload;
    switch ((item.entityType, item.operation)) {
      case ('expense', 'create'):
        await _apiExpenses.add(
          id: payload['id'] as String,
          budgetId: payload['budgetId'] as String,
          amount: Money(payload['amountMinor'] as int),
          spentOn: DateTime.parse(payload['spentOn'] as String),
          paymentMethod: PaymentMethod.fromDb(
            payload['paymentMethod'] as String,
          ),
          note: payload['note'] as String?,
        );
      case ('expense', 'update'):
        await _apiExpenses.update(
          id: item.entityId,
          amount: Money(payload['amountMinor'] as int),
          spentOn: DateTime.parse(payload['spentOn'] as String),
          paymentMethod: PaymentMethod.fromDb(
            payload['paymentMethod'] as String,
          ),
          note: payload['note'] as String?,
        );
      case ('expense', 'delete'):
        await _apiExpenses.delete(item.entityId);
      case ('goal', 'create'):
        await _apiGoals.create(
          id: payload['id'] as String,
          title: payload['title'] as String,
          target: Money(payload['targetMinor'] as int),
          targetDate: payload['targetDate'] == null
              ? null
              : DateTime.parse(payload['targetDate'] as String),
          monthlyContribution: payload['monthlyContributionMinor'] == null
              ? null
              : Money(payload['monthlyContributionMinor'] as int),
          icon: payload['icon'] as String?,
        );
      case ('goal', 'contribute'):
        await _apiGoals.contribute(
          goalId: item.entityId,
          amount: Money(payload['amountMinor'] as int),
          budgetId: payload['budgetId'] as String?,
        );
      case ('goal', 'delete'):
        await _apiGoals.delete(item.entityId);
      case ('budget', 'create'):
        await _apiBudgets.createMonth(
          id: payload['id'] as String,
          period: Period.parse(payload['period'] as String),
          income: Money(payload['incomeMinor'] as int),
          savingsMode: SavingsMode.fromDb(payload['savingsMode'] as String),
          savingsTarget: Money(payload['savingsTargetMinor'] as int),
          savingsPercent: (payload['savingsPercent'] as num?)?.toDouble(),
          investmentTarget: payload['investmentTargetMinor'] == null
              ? null
              : Money(payload['investmentTargetMinor'] as int),
          carriedFrom: payload['carriedFromPeriod'] == null
              ? null
              : Period.parse(payload['carriedFromPeriod'] as String),
        );
      case ('budget', 'confirmSavings'):
        await _apiBudgets.confirmSavings(
          budgetId: item.entityId,
          amount: Money(payload['amountMinor'] as int),
          destination: payload['destination'] as String? ?? 'bank',
        );
      case (final type, final op):
        throw StateError('Unknown sync item $type/$op');
    }
  }
}
