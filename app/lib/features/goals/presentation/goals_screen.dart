import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Gap.lg),
            child: PressableScale.onTap(
              onTap: () {
                AppHaptics.tap();
                _showGoalSheet(context, ref);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '+ New',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: AppType.display,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
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
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
            children: [
              for (final goal in active) ...[
                _GoalCard(goal: goal),
                Gap.h12,
              ],
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

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: AppTheme.card(scheme),
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
              child: PressableScale(
                child: OutlinedButton(
                  onPressed: () => _showContributeSheet(context, ref, goal),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 38),
                  ),
                  child: const Text('Add money'),
                ),
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

void _showGoalSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => const _NewGoalSheet(),
  );
}

/// A real `ConsumerStatefulWidget` rather than a bare builder closure with
/// controllers created outside it and disposed after the sheet's `Future`
/// resolves — that resolves the moment the route *starts* closing, not once
/// its exit animation finishes, so a still-animating `TextField` ends up
/// depending on a controller that is already disposed. This is the same
/// `_dependents.isEmpty` assertion the onboarding amount sheet
/// (`onboarding_screen.dart`'s `_AmountSheet`) already documents and fixes
/// the same way — this sheet just hadn't been moved onto that pattern yet.
class _NewGoalSheet extends ConsumerStatefulWidget {
  const _NewGoalSheet();

  @override
  ConsumerState<_NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends ConsumerState<_NewGoalSheet> {
  final _titleController = TextEditingController();
  final _targetController = TextEditingController();
  final _monthlyController = TextEditingController();
  DateTime? _targetDate;

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    _monthlyController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month + 6),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _submit() async {
    final target = Money.tryParse(_targetController.text);
    if (_titleController.text.trim().isEmpty ||
        target == null ||
        !target.isPositive) {
      return;
    }
    try {
      await ref
          .read(goalRepositoryProvider)
          .create(
            title: _titleController.text,
            target: target,
            targetDate: _targetDate,
            monthlyContribution: Money.tryParse(_monthlyController.text),
          );
      ref.invalidate(goalsProvider);
      AppHaptics.success();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      // Scrollable so three text fields plus a date button don't overflow
      // once the keyboard has eaten into the available height.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New goal', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What are you saving for?',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetController,
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
              controller: _monthlyController,
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
              onPressed: _pickDate,
              icon: const Icon(Icons.event, size: 18),
              label: Text(
                _targetDate == null
                    ? 'Target date (optional)'
                    : DateFormat('d MMM yyyy').format(_targetDate!),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: const Text('Create goal')),
          ],
        ),
      ),
    );
  }
}

void _showContributeSheet(BuildContext context, WidgetRef ref, Goal goal) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _ContributeSheet(goal: goal),
  );
}

/// Same fix as [_NewGoalSheet]: a real `ConsumerStatefulWidget` so the amount
/// controller is torn down exactly once, when this element actually
/// unmounts — not the moment the sheet's route starts closing.
class _ContributeSheet extends ConsumerStatefulWidget {
  const _ContributeSheet({required this.goal});

  final Goal goal;

  @override
  ConsumerState<_ContributeSheet> createState() => _ContributeSheetState();
}

class _ContributeSheetState extends ConsumerState<_ContributeSheet> {
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = Money.tryParse(_amountController.text);
    if (amount == null || !amount.isPositive) return;
    try {
      final budget = ref.read(currentBudgetProvider).value;
      await ref
          .read(goalRepositoryProvider)
          .contribute(
            goalId: widget.goal.id,
            amount: amount,
            budgetId: budget?.id,
          );
      ref.invalidate(goalsProvider);
      AppHaptics.success();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add to ${widget.goal.title}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.goal.remaining.formatCompact()} still to go',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
              ],
              style: theme.textTheme.headlineMedium,
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '0',
                hintStyle: theme.textTheme.headlineMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _submit, child: const Text('Add')),
          ],
        ),
      ),
    );
  }
}
