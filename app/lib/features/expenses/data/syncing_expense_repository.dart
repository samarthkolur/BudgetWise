import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/sync/sync_queue_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Wraps [LocalExpenseRepository] and [ApiExpenseRepository] into one
/// local-first repository, used in place of a bare `ApiExpenseRepository`
/// whenever a session exists.
///
/// **Writes** go to the local database first — the on-device copy is the
/// user's record of what they did, and it exists whether or not the network
/// does. The same write is then attempted against the server immediately; if
/// that fails for lack of connectivity, it's queued in `pending_sync`
/// (`core/sync/sync_queue_repository.dart`) instead of failing the user's
/// action, and `SyncService` replays it once connectivity returns. A failure
/// for any other reason (the server rejecting the input) is not queued —
/// silently retrying something the server has already refused would just
/// fail again, so it surfaces to the caller as a real error instead.
///
/// **Reads** try the server first, since it's the authoritative copy, and
/// fall back to the local database on a network failure — which is populated
/// by `HydrationService` right after sign-in and kept current by every
/// successful local-first write.
class SyncingExpenseRepository implements ExpenseRepository {
  SyncingExpenseRepository({
    required ExpenseRepository local,
    required ExpenseRepository remote,
    required SyncQueueRepository queue,
  }) : _local = local,
       _remote = remote,
       _queue = queue;

  final ExpenseRepository _local;
  final ExpenseRepository _remote;
  final SyncQueueRepository _queue;

  @override
  Future<List<Expense>> forBudget(String budgetId) async {
    try {
      return await _remote.forBudget(budgetId);
    } on NetworkFailure {
      return _local.forBudget(budgetId);
    }
  }

  @override
  Future<Expense> add({
    required String budgetId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
    String? id,
  }) async {
    final resolvedId = id ?? const Uuid().v4();
    final expense = await _local.add(
      budgetId: budgetId,
      amount: amount,
      spentOn: spentOn,
      paymentMethod: paymentMethod,
      note: note,
      id: resolvedId,
    );
    try {
      await _remote.add(
        budgetId: budgetId,
        amount: amount,
        spentOn: spentOn,
        paymentMethod: paymentMethod,
        note: note,
        id: resolvedId,
      );
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'expense',
        entityId: resolvedId,
        operation: 'create',
        payload: {
          'id': resolvedId,
          'budgetId': budgetId,
          'amountMinor': amount.minor,
          'spentOn': dateOnly(spentOn),
          'paymentMethod': paymentMethod.name,
          'note': note,
        },
      );
    }
    return expense;
  }

  @override
  Future<Expense> update({
    required String id,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    final expense = await _local.update(
      id: id,
      amount: amount,
      spentOn: spentOn,
      paymentMethod: paymentMethod,
      note: note,
    );
    try {
      await _remote.update(
        id: id,
        amount: amount,
        spentOn: spentOn,
        paymentMethod: paymentMethod,
        note: note,
      );
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'expense',
        entityId: id,
        operation: 'update',
        payload: {
          'amountMinor': amount.minor,
          'spentOn': dateOnly(spentOn),
          'paymentMethod': paymentMethod.name,
          'note': note,
        },
      );
    }
    return expense;
  }

  @override
  Future<void> delete(String id) async {
    await _local.delete(id);
    try {
      await _remote.delete(id);
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'expense',
        entityId: id,
        operation: 'delete',
        payload: const {},
      );
    }
  }
}
