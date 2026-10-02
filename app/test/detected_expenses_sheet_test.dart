import 'package:budgetwise/features/sms_detection/data/detected_expense_repository.dart';
import 'package:budgetwise/features/sms_detection/presentation/detected_expenses_sheet.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _budgetId = 'budget-1';

DetectedExpense _detected(String id, {String merchant = 'AMAZON PAY'}) =>
    DetectedExpense(
      id: id,
      budgetId: _budgetId,
      amount: const Money(49900),
      occurredOn: DateTime(2026, 1, 12),
      merchant: merchant,
      rawSender: 'HDFCBK',
      rawBody: 'Rs.499.00 debited ... at $merchant.',
    );

class _OpenSheetButton extends ConsumerWidget {
  const _OpenSheetButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showDetectedExpensesSheet(context, ref, _budgetId),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('renders one card per pending detected transaction', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpableApp(
        child: const _OpenSheetButton(),
        detectedExpenseRepository: FakeDetectedExpenseRepository(
          seed: [
            _detected('d1', merchant: 'SWIGGY'),
            _detected('d2', merchant: 'UBER'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Found 2 transactions'), findsOneWidget);
    expect(find.text('SWIGGY'), findsOneWidget);
    expect(find.text('UBER'), findsOneWidget);
  });

  testWidgets('adding a transaction files the expense and removes that card', (
    tester,
  ) async {
    final expenses = FakeExpenseRepository();

    await tester.pumpWidget(
      pumpableApp(
        child: const _OpenSheetButton(),
        expenseRepository: expenses,
        detectedExpenseRepository: FakeDetectedExpenseRepository(
          seed: [_detected('d1', merchant: 'SWIGGY')],
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // The sheet auto-closes once its list empties.
    expect(find.text('SWIGGY'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);

    final filed = await expenses.forBudget(_budgetId);
    expect(filed, hasLength(1));
    expect(filed.single.amount, const Money(49900));
  });

  testWidgets('skip all clears every card and closes the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      pumpableApp(
        child: const _OpenSheetButton(),
        detectedExpenseRepository: FakeDetectedExpenseRepository(
          seed: [
            _detected('d1', merchant: 'SWIGGY'),
            _detected('d2', merchant: 'UBER'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip all'));
    await tester.pumpAndSettle();

    expect(find.text('SWIGGY'), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
