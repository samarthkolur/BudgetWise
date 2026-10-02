import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/sync/sync_queue_repository.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Local-first [BudgetRepository], used in place of a bare
/// [ApiBudgetRepository] whenever a session exists. See
/// `SyncingExpenseRepository` for the full write/read design this mirrors.
class SyncingBudgetRepository implements BudgetRepository {
  SyncingBudgetRepository({
    required BudgetRepository local,
    required BudgetRepository remote,
    required SyncQueueRepository queue,
  }) : _local = local,
       _remote = remote,
       _queue = queue;

  final BudgetRepository _local;
  final BudgetRepository _remote;
  final SyncQueueRepository _queue;

  @override
  Future<MonthlyBudget?> currentBudget() async {
    try {
      return await _remote.currentBudget();
    } on NetworkFailure {
      return _local.currentBudget();
    }
  }

  @override
  Future<BudgetSummary?> summaryFor(Period period) async {
    try {
      return await _remote.summaryFor(period);
    } on NetworkFailure {
      return _local.summaryFor(period);
    }
  }

  @override
  Future<List<MonthlyBudget>> allBudgets() async {
    try {
      return await _remote.allBudgets();
    } on NetworkFailure {
      return _local.allBudgets();
    }
  }

  @override
  Future<List<BudgetSummary>> allSummaries() async {
    try {
      return await _remote.allSummaries();
    } on NetworkFailure {
      return _local.allSummaries();
    }
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
    final resolvedId = id ?? const Uuid().v4();
    final budget = await _local.createMonth(
      period: period,
      income: income,
      savingsMode: savingsMode,
      savingsTarget: savingsTarget,
      savingsPercent: savingsPercent,
      investmentTarget: investmentTarget,
      carriedFrom: carriedFrom,
      id: resolvedId,
    );
    try {
      await _remote.createMonth(
        period: period,
        income: income,
        savingsMode: savingsMode,
        savingsTarget: savingsTarget,
        savingsPercent: savingsPercent,
        investmentTarget: investmentTarget,
        carriedFrom: carriedFrom,
        id: resolvedId,
      );
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'budget',
        entityId: resolvedId,
        operation: 'create',
        payload: {
          'id': resolvedId,
          'period': period.isoDate,
          'incomeMinor': income.minor,
          'savingsMode': savingsMode.name,
          'savingsPercent': savingsPercent,
          'savingsTargetMinor': savingsTarget.minor,
          'investmentTargetMinor': investmentTarget?.minor,
          'carriedFromPeriod': carriedFrom?.isoDate,
        },
      );
    }
    return budget;
  }

  @override
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  }) async {
    await _local.confirmSavings(
      budgetId: budgetId,
      amount: amount,
      destination: destination,
    );
    try {
      await _remote.confirmSavings(
        budgetId: budgetId,
        amount: amount,
        destination: destination,
      );
    } on NetworkFailure {
      await _queue.enqueue(
        entityType: 'budget',
        entityId: budgetId,
        operation: 'confirmSavings',
        payload: {'amountMinor': amount.minor, 'destination': destination},
      );
    }
  }
}
