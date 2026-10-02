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
    this.carriedFrom,
    this.isSubmitting = false,
  });

  final Period period;
  final String displayName;
  final Money income;
  final SavingsMode savingsMode;
  final double savingsPercent;
  final Money savingsFixed;

  final Period? carriedFrom;
  final bool isSubmitting;

  Money get savingsTarget => resolveSavingsTarget(
    income: income,
    mode: savingsMode,
    fixedAmount: savingsFixed,
    percent: savingsPercent,
  );

  /// What is left once savings are set aside — the PRD's "the interface
  /// instantly demonstrates how savings affect available spending money".
  /// There is no further split below this: everything left is simply
  /// spendable, tracked as a running debit/credit history rather than
  /// pre-allocated into categories.
  Money get spendable =>
      spendableIncome(income: income, savingsTarget: savingsTarget);

  bool get canSubmit =>
      displayName.trim().isNotEmpty && income.isPositive && !isSubmitting;

  OnboardingState copyWith({
    String? displayName,
    Money? income,
    SavingsMode? savingsMode,
    double? savingsPercent,
    Money? savingsFixed,
    Period? carriedFrom,
    bool? isSubmitting,
  }) => OnboardingState(
    period: period,
    displayName: displayName ?? this.displayName,
    income: income ?? this.income,
    savingsMode: savingsMode ?? this.savingsMode,
    savingsPercent: savingsPercent ?? this.savingsPercent,
    savingsFixed: savingsFixed ?? this.savingsFixed,
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
  );

  void setDisplayName(String value) =>
      state = state.copyWith(displayName: value);

  void setIncome(Money value) => state = state.copyWith(income: value);

  void setSavingsMode(SavingsMode mode) =>
      state = state.copyWith(savingsMode: mode);

  void setSavingsPercent(double percent) =>
      state = state.copyWith(savingsPercent: percent.clamp(0, 100));

  void setSavingsFixed(Money amount) =>
      state = state.copyWith(savingsFixed: amount);

  /// Reuses last month's savings split. There is nothing else to adopt —
  /// without categories, the only thing one month hands the next is how
  /// much to save first.
  void adoptPrevious(MonthlyBudget previous) {
    state = state.copyWith(
      savingsMode: previous.savingsMode,
      savingsPercent: previous.savingsPercent ?? state.savingsPercent,
      savingsFixed: previous.savingsTarget,
      carriedFrom: previous.period,
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
