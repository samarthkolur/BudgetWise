import 'package:budgetwise/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() {
    EditableText.debugDeterministicCursor = true;
  });

  testWidgets(
    'walking all five steps with the default allocation reaches the '
    'dashboard-bound success screen with no exceptions',
    (tester) async {
      await tester.pumpWidget(pumpableApp(child: const OnboardingScreen()));
      await tester.pumpAndSettle();

      // Step 0 — welcome: the CTA stays disabled until a name is entered.
      expect(find.text("Let's build your plan"), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Your name'),
        'Aditi',
      );
      await tester.pump();
      await tester.tap(find.text("Let's build your plan"));
      await tester.pumpAndSettle();

      // Step 1 — income.
      expect(find.text('What do you earn this month?'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '50000');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2 — savings: defaults are already valid, just continue.
      expect(find.text('How much will you save first?'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 3 — allocation: the default split already sums to 100%.
      expect(find.text('Now, divide the rest'), findsOneWidget);
      expect(find.text('Every rupee is assigned'), findsOneWidget);
      await tester.tap(find.text('Create my plan'));
      await tester.pumpAndSettle();

      // Step 4 — success.
      expect(find.textContaining('plan is ready!'), findsOneWidget);
      expect(find.text('Go to dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('skip from the welcome step submits with defaults', (
    tester,
  ) async {
    await tester.pumpWidget(pumpableApp(child: const OnboardingScreen()));
    await tester.pumpAndSettle();

    // Skip is visibly present but only meaningfully tappable once a name is
    // entered — the one field this app needs that the design doesn't.
    await tester.enterText(
      find.widgetWithText(TextField, 'Your name'),
      'Sam',
    );
    await tester.pump();

    await tester.tap(find.text('Skip to dashboard →'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
