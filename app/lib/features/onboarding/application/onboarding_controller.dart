import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The answers gathered while setting up a month, and everything derived from
/// them.
///
/// Immutable, and every derived figure is computed here rather than in a widget.
/// That is what makes the onboarding arithmetic testable without pumping a
/// single frame — and the arithmetic is the part that must be right.
class OnboardingState {
  const OnboardingState({
    required this.period,
    this.income = const Money.zero(),
    this.savingsMode = SavingsMode.percent,
    this.savingsPercent = 20,
    this.savingsFixed = const Money.zero(),
    this.categoryPercents = const {},
    this.carriedFrom,
    this.isSubmitting = false,
  });

  final Period period;
  final Money income;
  final SavingsMode savingsMode;
  final double savingsPercent;
  final Money savingsFixed;

  /// category key -> percent of spendable income.
  final Map<String, double> categoryPercents;

  final Period? carriedFrom;
  final bool isSubmitting;

  Money get savingsTarget => resolveSavingsTarget(
    income: income,
    mode: savingsMode,
    fixedAmount: savingsFixed,
    percent: savingsPercent,
  );

  /// What is left to divide among categories. Recomputed on every keystroke and
  /// slider move, which is the PRD's "the interface instantly demonstrates how
  /// savings affect available spending money".
  Money get spendable =>
      spendableIncome(income: income, savingsTarget: savingsTarget);

  double get totalCategoryPercent =>
      categoryPercents.values.fold<double>(0, (a, b) => a + b);

  /// Percentage points still unassigned. Negative means over-allocated.
  double get remainingPercent =>
      double.parse((100 - totalCategoryPercent).toStringAsFixed(2));

  bool get isBalanced => remainingPercent.abs() < 0.01;

  bool get canSubmit => income.isPositive && isBalanced && !isSubmitting;

  /// The concrete split, using largest-remainder so the parts sum to exactly
  /// [spendable]. The database refuses anything else.
  List<Allocation<CategoryTemplate>> get allocations {
    final templates = {for (final t in kDefaultCategories) t.key: t};
    final percents = <CategoryTemplate, double>{
      for (final entry in categoryPercents.entries)
        if (templates[entry.key] != null) templates[entry.key]!: entry.value,
    };
    return allocateByPercent(total: spendable, percents: percents);
  }

  Money amountFor(String categoryKey) =>
      spendable.percent(categoryPercents[categoryKey] ?? 0);

  OnboardingState copyWith({
    Money? income,
    SavingsMode? savingsMode,
    double? savingsPercent,
    Money? savingsFixed,
    Map<String, double>? categoryPercents,
    Period? carriedFrom,
    bool? isSubmitting,
  }) => OnboardingState(
    period: period,
    income: income ?? this.income,
    savingsMode: savingsMode ?? this.savingsMode,
    savingsPercent: savingsPercent ?? this.savingsPercent,
    savingsFixed: savingsFixed ?? this.savingsFixed,
    categoryPercents: categoryPercents ?? this.categoryPercents,
    carriedFrom: carriedFrom ?? this.carriedFrom,
    isSubmitting: isSubmitting ?? this.isSubmitting,
  );
}

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => OnboardingState(
    period: Period.current(),
    categoryPercents: {
      for (final template in kDefaultCategories)
        template.key: template.defaultPercent,
    },
  );

  void setIncome(Money value) => state = state.copyWith(income: value);

  void setSavingsMode(SavingsMode mode) =>
      state = state.copyWith(savingsMode: mode);

  void setSavingsPercent(double percent) =>
      state = state.copyWith(savingsPercent: percent.clamp(0, 90));

  void setSavingsFixed(Money amount) =>
      state = state.copyWith(savingsFixed: amount);

  /// Moves one category and absorbs the difference across the others.
  ///
  /// Without this the user has to make the numbers reach 100 by hand, which is
  /// exactly the spreadsheet arithmetic the product exists to remove. Categories
  /// at zero are left alone — a deliberate zero is a decision, and silently
  /// refilling it would undo it.
  void setCategoryPercent(String key, double percent) {
    final next = Map<String, double>.from(state.categoryPercents);
    final previous = next[key] ?? 0;
    final clamped = percent.clamp(0.0, 100.0);
    next[key] = clamped;

    final delta = clamped - previous;
    if (delta.abs() < 0.001) {
      state = state.copyWith(categoryPercents: next);
      return;
    }

    final others = next.keys.where((k) => k != key && next[k]! > 0).toList();
    if (others.isEmpty) {
      state = state.copyWith(categoryPercents: next);
      return;
    }

    // Take proportionally from the others, so a large category absorbs more of
    // the change than a small one.
    final otherTotal = others.fold<double>(0, (a, k) => a + next[k]!);
    if (otherTotal <= 0) {
      state = state.copyWith(categoryPercents: next);
      return;
    }

    for (final other in others) {
      final share = next[other]! / otherTotal;
      next[other] = (next[other]! - delta * share).clamp(0.0, 100.0);
    }

    // Rounding leaves a fraction of a point; put it on the largest category so
    // the total lands exactly on 100.
    final total = next.values.fold<double>(0, (a, b) => a + b);
    final drift = 100 - total;
    if (drift.abs() > 0.001) {
      final largest = next.entries
          .where((e) => e.key != key)
          .reduce((a, b) => a.value >= b.value ? a : b);
      next[largest.key] = (largest.value + drift).clamp(0.0, 100.0);
    }

    for (final entry in next.entries) {
      next[entry.key] = double.parse(entry.value.toStringAsFixed(2));
    }

    state = state.copyWith(categoryPercents: next);
  }

  /// Reuses last month's split. Percentages carry; amounts do not — they are
  /// re-derived from the new income, which is the whole point of storing both.
  void adoptPrevious(MonthlyBudget previous, List<CategorySpend> categories) {
    state = state.copyWith(
      savingsMode: previous.savingsMode,
      savingsPercent: previous.savingsPercent ?? state.savingsPercent,
      savingsFixed: previous.savingsTarget,
      categoryPercents: {
        for (final category in categories)
          category.key: category.allocatedPercent,
      },
      carriedFrom: previous.period,
    );
  }

  void resetToDefaults() {
    state = state.copyWith(
      categoryPercents: {
        for (final template in kDefaultCategories)
          template.key: template.defaultPercent,
      },
    );
  }

  /// Writes the month. One RPC, one transaction.
  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(isSubmitting: true);
    try {
      await ref
          .read(budgetRepositoryProvider)
          .createMonth(
            period: state.period,
            income: state.income,
            savingsMode: state.savingsMode,
            savingsTarget: state.savingsTarget,
            savingsPercent: state.savingsMode == SavingsMode.percent
                ? state.savingsPercent
                : null,
            allocations: state.allocations,
            carriedFrom: state.carriedFrom,
          );
      await ref.read(profileRepositoryProvider).completeOnboarding();
      ref
        ..refreshBudgetData()
        ..invalidate(profileProvider);
    } finally {
      state = state.copyWith(isSubmitting: false);
    }
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
