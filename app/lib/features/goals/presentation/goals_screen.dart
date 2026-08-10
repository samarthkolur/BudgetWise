import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Long-term goals, with the number the user actually needs: what to set aside
/// each month to arrive on time.
class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showGoalSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Goal'),
      ),
      body: AsyncView(
        value: goals,
        onRetry: () => ref.invalidate(goalsProvider),
        builder: (list) {
          if (list.isEmpty) {
            return EmptyView(
              icon: Icons.flag_outlined,
              title: 'No goals yet',
              message:
                  'A laptop, an emergency fund, a trip — give your savings '
                  'somewhere to go.',
              action: FilledButton(
                onPressed: () => _showGoalSheet(context, ref),
                child: const Text('Create a goal'),
              ),
            );
          }

          final active = list.where((g) => g.status != 'abandoned').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 96),
            children: [
              ListSection(
                children: [for (final goal in active) _GoalCard(goal: goal)],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: goal.isAchieved
                    ? Icons.check_circle_outline_rounded
                    : Icons.flag_outlined,
                tone: goal.isAchieved ? scheme.healthy : null,
              ),
              Gap.w12,
              Expanded(
                child: Text(
                  goal.title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (goal.isAchieved)
                TonePill(
                  label: 'Achieved',
                  tone: scheme.healthy,
                  icon: Icons.check_rounded,
                ),
            ],
          ),
          Gap.h16,
          FlatBar(value: goal.progress, color: scheme.primary),
          Gap.h8,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${goal.saved.formatCompact()} of ${goal.target.formatCompact()}',
                style: theme.textTheme.bodyMedium?.money,
              ),
              Text(
                '${(goal.progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (!goal.isAchieved) ...[
            Gap.h12,
            _GoalProjection(goal: goal),
            Gap.h12,
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => _showContributeSheet(context, ref, goal),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                ),
                child: const Text('Add money'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Target date, required monthly contribution, projected completion.
///
/// Says "no date yet" rather than inventing one when there is no contribution
/// rate to project from — a made-up completion date is worse than none.
class _GoalProjection extends StatelessWidget {
  const _GoalProjection({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final required = goal.requiredMonthly;
    final projected = goal.projectedCompletion;

    final lines = <String>[
      '${goal.remaining.formatCompact()} to go',
      if (goal.targetDate != null && required != null)
        'Set aside ${required.formatCompact()} a month to reach it by '
            '${DateFormat('MMM yyyy').format(goal.targetDate!)}'
      else if (projected != null)
        'On track for ${projected.shortLabel}'
      else
        'Add a monthly amount to see a completion date',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

Future<void> _showGoalSheet(BuildContext context, WidgetRef ref) async {
  final titleController = TextEditingController();
  final targetController = TextEditingController();
  final monthlyController = TextEditingController();
  DateTime? targetDate;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New goal', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What are you saving for?',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
              ],
              decoration: const InputDecoration(
                prefixText: '₹ ',
                hintText: 'Target amount',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: monthlyController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
              ],
              decoration: const InputDecoration(
                prefixText: '₹ ',
                hintText: 'Monthly contribution (optional)',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime(now.year, now.month + 6),
                  firstDate: now,
                  lastDate: DateTime(now.year + 20),
                );
                if (picked != null) setSheetState(() => targetDate = picked);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text(
                targetDate == null
                    ? 'Target date (optional)'
                    : DateFormat('d MMM yyyy').format(targetDate!),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                final target = Money.tryParse(targetController.text);
                if (titleController.text.trim().isEmpty ||
                    target == null ||
                    !target.isPositive) {
                  return;
                }
                try {
                  await ref
                      .read(goalRepositoryProvider)
                      .create(
                        title: titleController.text,
                        target: target,
                        targetDate: targetDate,
                        monthlyContribution: Money.tryParse(
                          monthlyController.text,
                        ),
                      );
                  ref.invalidate(goalsProvider);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                } on Object catch (error) {
                  if (sheetContext.mounted) showFailure(sheetContext, error);
                }
              },
              child: const Text('Create goal'),
            ),
          ],
        ),
      ),
    ),
  );

  titleController.dispose();
  targetController.dispose();
  monthlyController.dispose();
}

Future<void> _showContributeSheet(
  BuildContext context,
  WidgetRef ref,
  Goal goal,
) async {
  final amountController = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add to ${goal.title}',
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${goal.remaining.formatCompact()} still to go',
            style: Theme.of(sheetContext).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
            ],
            style: Theme.of(sheetContext).textTheme.headlineMedium,
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: '0',
              hintStyle: Theme.of(sheetContext).textTheme.headlineMedium
                  ?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final amount = Money.tryParse(amountController.text);
              if (amount == null || !amount.isPositive) return;
              try {
                final budget = ref.read(currentBudgetProvider).value;
                await ref
                    .read(goalRepositoryProvider)
                    .contribute(
                      goalId: goal.id,
                      amount: amount,
                      budgetId: budget?.id,
                    );
                ref.invalidate(goalsProvider);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              } on Object catch (error) {
                if (sheetContext.mounted) showFailure(sheetContext, error);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );

  amountController.dispose();
}
