import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
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

  test('starts with the default categories summing to 100%', () {
    final state = container.read(onboardingControllerProvider);

    expect(state.totalCategoryPercent, closeTo(100, 0.01));
    expect(state.isBalanced, isTrue);
    expect(state.displayName, isEmpty);
  });

  test('setCategoryPercent changes only the category it is given', () {
    final before = container.read(onboardingControllerProvider);
    final transportBefore = before.categoryPercents['transport'];

    controller().setCategoryPercent('food', 50);

    final after = container.read(onboardingControllerProvider);
    expect(after.categoryPercents['food'], 50);
    expect(after.categoryPercents['transport'], transportBefore);
  });

  test('setCategoryAmount converts a rupee figure to the matching percent', () {
    controller()
      ..setIncome(const Money(1000000)) // ₹10,000
      ..setSavingsPercent(0); // spendable == income

    controller().setCategoryAmount('food', const Money(250000)); // ₹2,500

    final state = container.read(onboardingControllerProvider);
    expect(state.categoryPercents['food'], closeTo(25, 0.01));
  });

  test('setCategoryAmount is a no-op while spendable is zero', () {
    final before =
        container.read(onboardingControllerProvider).categoryPercents['food'];

    controller().setCategoryAmount('food', const Money(1000));

    final after =
        container.read(onboardingControllerProvider).categoryPercents['food'];
    expect(after, before);
  });

  test('resetToDefaults restores the starting split after edits', () {
    controller().setCategoryPercent('food', 0);

    controller().resetToDefaults();

    final state = container.read(onboardingControllerProvider);
    final defaultFood =
        kDefaultCategories.firstWhere((t) => t.key == 'food').defaultPercent;
    expect(state.categoryPercents['food'], defaultFood);
  });

  test('setDisplayName is what canSubmit requires along with a balanced, positive plan', () {
    controller()
      ..setIncome(const Money(1000000))
      ..setSavingsPercent(0);

    expect(container.read(onboardingControllerProvider).canSubmit, isFalse);

    controller().setDisplayName('Asha');

    expect(container.read(onboardingControllerProvider).canSubmit, isTrue);
  });
}
