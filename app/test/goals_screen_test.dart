import 'package:budgetwise/features/goals/presentation/goals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() {
    // A focused TextField's blinking cursor is itself an AnimationController
    // that never finishes on its own — without this, any pumpAndSettle after
    // typing into a field hangs waiting for a "settled" state that never
    // arrives, which looks exactly like a bug even though nothing is wrong.
    EditableText.debugDeterministicCursor = true;
  });

  testWidgets('creating a goal from the empty state renders it in the list', (
    tester,
  ) async {
    await tester.pumpWidget(pumpableApp(child: const GoalsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No goals yet'), findsOneWidget);

    await tester.tap(find.text('Create a goal'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'What are you saving for?'),
      'New Laptop',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Target amount'),
      '60000',
    );

    await tester.tap(find.text('Create goal'));
    await tester.pumpAndSettle();

    expect(find.text('New Laptop'), findsOneWidget);
    expect(find.text('No goals yet'), findsNothing);
  });

  testWidgets('creating a goal from the app bar "+ New" button works too', (
    tester,
  ) async {
    await tester.pumpWidget(pumpableApp(child: const GoalsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'What are you saving for?'),
      'Goa Trip',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Target amount'),
      '25000',
    );

    await tester.tap(find.text('Create goal'));
    await tester.pumpAndSettle();

    expect(find.text('Goa Trip'), findsOneWidget);
  });

  testWidgets('the "Create goal" button is a no-op without a title or amount', (
    tester,
  ) async {
    await tester.pumpWidget(pumpableApp(child: const GoalsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ New'));
    await tester.pumpAndSettle();

    // Nothing entered — tapping create should neither crash nor close the
    // sheet, since there is nothing valid to submit.
    await tester.tap(find.text('Create goal'));
    await tester.pumpAndSettle();

    expect(find.text('New goal'), findsOneWidget);
  });

  testWidgets(
    'contributing to a goal from its card updates the saved amount',
    (tester) async {
      await tester.pumpWidget(pumpableApp(child: const GoalsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ New'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'What are you saving for?'),
        'Emergency fund',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Target amount'),
        '10000',
      );
      await tester.tap(find.text('Create goal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add money'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '2000');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.textContaining('₹2,000'), findsWidgets);
    },
  );
}
