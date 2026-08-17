import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/data/budget_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/data/expense_repository.dart';
import 'package:budgetwise/features/goals/data/goal_repository.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory fakes for the four repository interfaces, used instead of the
/// real `Local*Repository` classes in widget tests.
///
/// This is deliberate, not a shortcut: routing a widget test through the real
/// on-device database means going through `sqflite_common_ffi`, which spins
/// up its own isolate for actual I/O. That combination — a real cross-isolate
/// Future resolving inside a Riverpod `FutureProvider`, itself inside
/// `flutter_test`'s zone-wrapped `ProviderContainer` — deadlocks `pumpWidget`
/// silently (confirmed by isolating each layer: the repository alone works
/// fine directly awaited with no Riverpod involved, a trivial Riverpod
/// `FutureProvider` works fine with no sqflite involved, but the two combined
/// under `flutter_test` never resolve). The repository layer already has its
/// own direct tests (`local_*_repository_test.dart`) that don't go through
/// Riverpod at all, so re-proving SQL correctness here would be redundant
/// anyway — these fakes exist to test what a widget test should test: does
/// the screen call the repository correctly and render what comes back.
class FakeGoalRepository implements GoalRepository {
  FakeGoalRepository({List<Goal>? seed}) : _goals = [...?seed];

  final List<Goal> _goals;
  var _nextId = 0;

  @override
  Future<List<Goal>> all() async => List.unmodifiable(_goals);

  @override
  Future<Goal> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
  }) async {
    final goal = Goal(
      id: 'goal-${_nextId++}',
      title: title,
      target: target,
      saved: const Money.zero(),
      status: 'active',
      icon: icon,
      targetDate: targetDate,
      monthlyContribution: monthlyContribution,
    );
    _goals.add(goal);
    return goal;
  }

  @override
  Future<void> contribute({
    required String goalId,
    required Money amount,
    String? budgetId,
  }) async {
    final index = _goals.indexWhere((g) => g.id == goalId);
    if (index == -1) return;
    final goal = _goals[index];
    final saved = goal.saved + amount;
    _goals[index] = Goal(
      id: goal.id,
      title: goal.title,
      target: goal.target,
      saved: saved,
      status: saved >= goal.target ? 'achieved' : goal.status,
      icon: goal.icon,
      targetDate: goal.targetDate,
      monthlyContribution: goal.monthlyContribution,
    );
  }

  @override
  Future<void> delete(String goalId) async =>
      _goals.removeWhere((g) => g.id == goalId);
}

class FakeBudgetRepository implements BudgetRepository {
  FakeBudgetRepository({
    MonthlyBudget? budget,
    BudgetSummary? summary,
    List<CategorySpend>? categories,
  }) : _budget = budget,
       _summary = summary,
       _categories = [...?categories];

  MonthlyBudget? _budget;
  BudgetSummary? _summary;
  final List<CategorySpend> _categories;

  @override
  Future<MonthlyBudget?> currentBudget() async => _budget;

  @override
  Future<BudgetSummary?> summaryFor(Period period) async =>
      _summary?.period == period ? _summary : null;

  @override
  Future<List<CategorySpend>> categoriesFor(String budgetId) async =>
      List.unmodifiable(_categories);

  @override
  Future<List<MonthlyBudget>> allBudgets() async =>
      _budget == null ? const [] : [_budget!];

  @override
  Future<List<BudgetSummary>> allSummaries() async =>
      _summary == null ? const [] : [_summary!];

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
    final budget = MonthlyBudget(
      id: 'budget-1',
      period: period,
      income: income,
      savingsTarget: savingsTarget,
      savingsMode: savingsMode,
      savingsPercent: savingsPercent,
      investmentTarget: investmentTarget,
      carriedFromPeriod: carriedFrom,
    );
    _budget = budget;
    return budget;
  }

  @override
  Future<void> confirmSavings({
    required String budgetId,
    required Money amount,
    String destination = 'bank',
  }) async {
    if (_summary != null) {
      _summary = BudgetSummary(
        budgetId: _summary!.budgetId,
        period: _summary!.period,
        income: _summary!.income,
        savingsTarget: _summary!.savingsTarget,
        savedActual: _summary!.savingsTarget,
        allocated: _summary!.allocated,
        spent: _summary!.spent,
        spendable: _summary!.spendable,
        remaining: _summary!.remaining,
        investedActual: _summary!.investedActual,
        investmentTarget: _summary!.investmentTarget,
        categoryCount: _summary!.categoryCount,
        expenseCount: _summary!.expenseCount,
        daysWithExpenses: _summary!.daysWithExpenses,
        savingsConfirmedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<void> updateCategoryAllocation({
    required String categoryId,
    required Money allocated,
    required double percent,
  }) async {}
}

class FakeExpenseRepository implements ExpenseRepository {
  FakeExpenseRepository({List<Expense>? seed}) : _expenses = [...?seed];

  final List<Expense> _expenses;
  var _nextId = 0;

  @override
  Future<List<Expense>> forBudget(String budgetId) async => List.unmodifiable(
    _expenses.where((e) => e.budgetId == budgetId),
  );

  @override
  Future<Expense> add({
    required String budgetId,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    final expense = Expense(
      id: 'expense-${_nextId++}',
      budgetId: budgetId,
      categoryId: categoryId,
      amount: amount,
      spentOn: spentOn,
      paymentMethod: paymentMethod,
      note: note,
    );
    _expenses.add(expense);
    return expense;
  }

  @override
  Future<Expense> update({
    required String id,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    final index = _expenses.indexWhere((e) => e.id == id);
    final updated = Expense(
      id: id,
      budgetId: _expenses[index].budgetId,
      categoryId: categoryId,
      amount: amount,
      spentOn: spentOn,
      paymentMethod: paymentMethod,
      note: note,
    );
    _expenses[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async =>
      _expenses.removeWhere((e) => e.id == id);
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({Profile? profile, UnlockClaim? unlock})
    : _profile = profile ?? const Profile(id: 'profile-1'),
      _unlock = unlock ?? const UnlockClaim(isUnlocked: false);

  Profile _profile;
  final UnlockClaim _unlock;

  @override
  Future<Profile> current() async => _profile;

  @override
  Future<Profile> updateProfile({required String displayName}) async =>
      _profile = _profile.copyWith(displayName: displayName);

  @override
  Future<Profile> completeOnboarding() async =>
      _profile = _profile.copyWith(onboardingCompletedAt: DateTime.now());

  @override
  Future<UnlockClaim> investingStatus() async => _unlock;

  @override
  Future<void> deleteAccount() async {}
}

/// Wraps a screen the same way the real app does — themed, with the four
/// repository providers replaced by fakes — without touching go_router
/// (screens under test are pushed directly as `home`, not routed to).
Widget pumpableApp({
  required Widget child,
  GoalRepository? goalRepository,
  BudgetRepository? budgetRepository,
  ExpenseRepository? expenseRepository,
  ProfileRepository? profileRepository,
}) {
  return ProviderScope(
    overrides: [
      goalRepositoryProvider.overrideWithValue(
        goalRepository ?? FakeGoalRepository(),
      ),
      budgetRepositoryProvider.overrideWithValue(
        budgetRepository ?? FakeBudgetRepository(),
      ),
      expenseRepositoryProvider.overrideWithValue(
        expenseRepository ?? FakeExpenseRepository(),
      ),
      profileRepositoryProvider.overrideWithValue(
        profileRepository ?? FakeProfileRepository(),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: child),
  );
}
