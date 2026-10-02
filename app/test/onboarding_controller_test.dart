import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/features/onboarding/application/onboarding_controller.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [profileProvider] is overridden everywhere here so the controller never
/// touches the real repository chain (which would otherwise reach
/// `flutter_secure_storage`'s platform channel — unavailable in a plain unit
/// test) — the same "override one provider, the whole tree below it talks to
/// a double" pattern `core/providers.dart` is written for.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [profileProvider.overrideWith((ref) async => null)],
    );
    addTearDown(container.dispose);
  });

  OnboardingController controller() =>
      container.read(onboardingControllerProvider.notifier);

  test('starts with no income and an empty name', () {
    final state = container.read(onboardingControllerProvider);

    expect(state.income, const Money.zero());
    expect(state.displayName, isEmpty);
    expect(state.canSubmit, isFalse);
  });

  test('spendable is income minus the resolved savings target', () {
    controller()
      ..setIncome(const Money(1000000)) // ₹10,000
      ..setSavingsPercent(20);

    final state = container.read(onboardingControllerProvider);
    expect(state.savingsTarget, const Money(200000)); // ₹2,000
    expect(state.spendable, const Money(800000)); // ₹8,000
  });

  test('a fixed savings target is used as-is in fixed mode', () {
    controller()
      ..setIncome(const Money(1000000))
      ..setSavingsMode(SavingsMode.fixed)
      ..setSavingsFixed(const Money(300000)); // ₹3,000

    final state = container.read(onboardingControllerProvider);
    expect(state.savingsTarget, const Money(300000));
    expect(state.spendable, const Money(700000));
  });

  test(
    'setDisplayName is what canSubmit requires along with a positive income',
    () {
      controller().setIncome(const Money(1000000));

      expect(container.read(onboardingControllerProvider).canSubmit, isFalse);

      controller().setDisplayName('Asha');

      expect(container.read(onboardingControllerProvider).canSubmit, isTrue);
    },
  );

  test('canSubmit is false while income is zero, even with a name', () {
    controller().setDisplayName('Asha');

    expect(container.read(onboardingControllerProvider).canSubmit, isFalse);
  });
}
