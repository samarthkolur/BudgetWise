import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The savings-transfer reminder, and its success state.
///
/// The PRD is explicit that this requires no bank integration: confirming is a
/// statement by the user that they moved the money. The value is the habit of
/// consciously moving it before spending starts, so the card stays visible for
/// the whole month until confirmed, then becomes an acknowledgement rather than
/// disappearing — the confirmation is worth seeing.
class SavingsReminderCard extends ConsumerStatefulWidget {
  const SavingsReminderCard({required this.summary, super.key});

  final BudgetSummary summary;

  @override
  ConsumerState<SavingsReminderCard> createState() =>
      _SavingsReminderCardState();
}

class _SavingsReminderCardState extends ConsumerState<SavingsReminderCard> {
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(budgetRepositoryProvider)
          .confirmSavings(
            budgetId: widget.summary.budgetId,
            amount: widget.summary.savingsOutstanding,
          );
      ref.refreshBudgetData();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Saved. That is the hard part done.')),
          );
      }
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = widget.summary;

    if (summary.savingsTarget.isZero) return const SizedBox.shrink();

    final isDone =
        summary.isSavingsConfirmed || summary.savingsOutstanding.isZero;
    final tone = isDone ? scheme.healthy : scheme.warning;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: isDone
                ? Icons.check_circle_outline_rounded
                : Icons.account_balance_outlined,
            tone: tone,
          ),
          Gap.w12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDone ? 'Savings moved' : 'Savings',
                  style: theme.textTheme.titleSmall,
                ),
                Gap.h4,
                Text(
                  isDone
                      ? '${summary.savedActual.formatCompact()} set aside this month.'
                      : '${summary.savingsOutstanding.formatCompact()} to transfer.',
                  style: theme.textTheme.bodyMedium,
                ),
                if (!isDone) ...[
                  Gap.h4,
                  Text(
                    'Move your savings to stay on track.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          if (!isDone)
            OutlinedButton(
              onPressed: _busy ? null : _confirm,
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                minimumSize: const Size(72, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: _busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Done'),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 15),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
