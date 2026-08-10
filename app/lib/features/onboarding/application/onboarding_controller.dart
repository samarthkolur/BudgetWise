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
    this.displayName = '',
    this.income = const Money.zero(),
    this.savingsMode = SavingsMode.percent,
    this.savingsPercent = 20,
    this.savingsFixed = const Money.zero(),
    this.categoryPercents = const {},
    this.carriedFrom,
    this.isSubmitting = false,
  });

  final Period period;
  final String displayName;
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

  bool get canSubmit =>
      displayName.trim().isNotEmpty &&
      income.isPositive &&
      isBalanced &&
      !isSubmitting;

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
    String? displayName,
    Money? income,
    SavingsMode? savingsMode,
    double? savingsPercent,
    Money? savingsFixed,
    Map<String, double>? categoryPercents,
    Period? carriedFrom,
    bool? isSubmitting,
  }) => OnboardingState(
    period: period,
    displayName: displayName ?? this.displayName,
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
    // Pre-filled when a name already exists (a signed-in Google account) so
    // the step only asks for what it doesn't already know.
    displayName: ref.read(profileProvider).value?.displayName ?? '',
    categoryPercents: {
      for (final template in kDefaultCategories)
        template.key: template.defaultPercent,
    },
  );

  void setDisplayName(String value) =>
      state = state.copyWith(displayName: value);

  void setIncome(Money value) => state = state.copyWith(income: value);

  void setSavingsMode(SavingsMode mode) =>
      state = state.copyWith(savingsMode: mode);

  void setSavingsPercent(double percent) =>
      state = state.copyWith(savingsPercent: percent.clamp(0, 90));

  void setSavingsFixed(Money amount) =>
      state = state.copyWith(savingsFixed: amount);

  /// Moves one category and nothing else.
  ///
  /// Earlier versions of this screen absorbed the change proportionally
  /// across every other category, so dragging one slider visibly moved eight
  /// others at once — precise entry was impossible and the result felt
  /// unpredictable. A category is a tag you turn on and set an amount for,
  /// not a cell in a spreadsheet that recalculates its neighbours. The
  /// remaining-to-assign banner is what tells the user where they stand, the
  /// same way it always has; getting to zero is now something they do on
  /// purpose rather than something that happens as a side effect of touching
  /// something else.
  void setCategoryPercent(String key, double percent) {
    final next = Map<String, double>.from(state.categoryPercents);
    next[key] = double.parse(percent.clamp(0.0, 100.0).toStringAsFixed(2));
    state = state.copyWith(categoryPercents: next);
  }

  /// Sets a category directly from a typed rupee amount rather than a
  /// percentage — the two are the same number, expressed the way the user
  /// happened to think of it.
  void setCategoryAmount(String key, Money amount) {
    if (state.spendable.isZero) return;
    setCategoryPercent(key, amount.ratioOf(state.spendable) * 100);
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
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(displayName: state.displayName.trim());
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
