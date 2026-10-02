import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/features/sms_detection/data/detected_expense_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Opens the "here's what we found" review — one card per pending
/// SMS-detected transaction.
///
/// A bottom sheet, matching `expense_sheet.dart`: reviewing a handful of
/// detected transactions is the same kind of short interruption manual entry
/// already is, not a screen of its own.
Future<void> showDetectedExpensesSheet(
  BuildContext context,
  WidgetRef ref,
  String budgetId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _DetectedExpensesSheet(budgetId: budgetId),
  );
}

class _DetectedExpensesSheet extends ConsumerWidget {
  const _DetectedExpensesSheet({required this.budgetId});

  final String budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingDetectedExpensesProvider(budgetId));

    // Confirming or skipping the last card empties the list; that's the
    // sheet's own close signal, not something the cards decide for
    // themselves.
    ref.listen(pendingDetectedExpensesProvider(budgetId), (previous, next) {
      final had = previous?.value?.isNotEmpty ?? false;
      final has = next.value?.isNotEmpty ?? false;
      if (had && !has) Navigator.of(context).maybePop();
    });

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AsyncView(
              value: pending,
              loading: const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
              // Empty here means the list is about to auto-pop the sheet
              // (see the ref.listen above) — nothing worth rendering for the
              // one frame in between.
              builder: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : _PendingList(budgetId: budgetId, items: list),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingList extends ConsumerWidget {
  const _PendingList({required this.budgetId, required this.items});

  final String budgetId;
  final List<DetectedExpense> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                items.length == 1
                    ? 'Found 1 transaction'
                    : 'Found ${items.length} transactions',
                style: theme.textTheme.titleMedium,
              ),
            ),
            TextButton(
              onPressed: () => _skipAll(ref),
              child: const Text('Skip all'),
            ),
          ],
        ),
        Text(
          'Add them to your history, or skip.',
          style: theme.textTheme.bodySmall,
        ),
        Gap.h16,
        for (final item in items) ...[
          _DetectedCard(budgetId: budgetId, item: item),
          Gap.h12,
        ],
      ],
    );
  }

  Future<void> _skipAll(WidgetRef ref) async {
    AppHaptics.tap();
    await ref
        .read(detectedExpenseRepositoryProvider)
        .dismissAllPending(budgetId);
    ref.invalidate(pendingDetectedExpensesProvider(budgetId));
  }
}

class _DetectedCard extends ConsumerStatefulWidget {
  const _DetectedCard({required this.budgetId, required this.item});

  final String budgetId;
  final DetectedExpense item;

  @override
  ConsumerState<_DetectedCard> createState() => _DetectedCardState();
}

class _DetectedCardState extends ConsumerState<_DetectedCard> {
  bool _busy = false;

  Future<void> _confirm() async {
    AppHaptics.tap();
    setState(() => _busy = true);
    try {
      await ref
          .read(detectedExpenseRepositoryProvider)
          .confirm(
            detected: widget.item,
            expenses: ref.read(expenseRepositoryProvider),
          );
      ref
        ..refreshBudgetData()
        ..invalidate(pendingDetectedExpensesProvider(widget.budgetId));
      AppHaptics.success();
    } on Object catch (error) {
      if (mounted) {
        showFailure(context, error);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _skip() async {
    AppHaptics.tap();
    setState(() => _busy = true);
    await ref.read(detectedExpenseRepositoryProvider).dismiss(widget.item.id);
    ref.invalidate(pendingDetectedExpensesProvider(widget.budgetId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: _busy ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: _busy,
        child: Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: AppTheme.card(theme.colorScheme),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.amount.format(),
                      style: theme.textTheme.titleLarge?.money,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.item.merchant ?? widget.item.rawSender,
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      DateFormat('d MMM').format(widget.item.occurredOn),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text('Skip'),
              ),
              Gap.w8,
              FilledButton(
                onPressed: _busy ? null : _confirm,
                // The theme's default FilledButton is full-width (a single
                // screen-wide CTA), which forces infinite width when placed
                // as a bare Row child instead of the Row's own Expanded
                // slot. This button sits beside Skip, not alone, so it needs
                // its own compact size.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 40),
                ),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
