import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/onboarding/application/onboarding_controller.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Three steps: income, savings, then the split.
///
/// The order is the product's argument. Savings is decided before any spending
/// category is even shown, so the money is committed before it can be claimed —
/// which is the reversal the PRD is built around.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _step = 0;

  void _next() {
    if (_step < 2) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _back() {
    if (_step > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish() async {
    try {
      await ref.read(onboardingControllerProvider.notifier).submit();
      // No navigation: the router's redirect sees the new budget and moves.
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: _step > 0 ? BackButton(onPressed: _back) : null,
        title: Text(state.period.label),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            minHeight: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _step = index),
                children: const [
                  _IncomeStep(),
                  _SavingsStep(),
                  _AllocationStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: switch (_step) {
                0 => FilledButton(
                  onPressed: state.income.isPositive ? _next : null,
                  child: const Text('Continue'),
                ),
                1 => FilledButton(
                  onPressed: _next,
                  child: const Text('Continue'),
                ),
                _ => FilledButton(
                  onPressed: state.canSubmit ? _finish : null,
                  child: state.isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(
                          state.isBalanced
                              ? 'Start the month'
                              : '${state.remainingPercent > 0 ? "Assign" : "Remove"} '
                                    '${state.remainingPercent.abs().toStringAsFixed(0)}% more',
                        ),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — income
// ---------------------------------------------------------------------------

class _IncomeStep extends ConsumerStatefulWidget {
  const _IncomeStep();

  @override
  ConsumerState<_IncomeStep> createState() => _IncomeStepState();
}

class _IncomeStepState extends ConsumerState<_IncomeStep> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    final income = ref.read(onboardingControllerProvider).income;
    _field = TextEditingController(
      text: income.isZero ? '' : income.asRupees.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previous = ref.watch(allBudgetsProvider).value;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What are you working with?',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Salary, allowance, freelance income, a scholarship — whatever '
            'arrives this month.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
            ],
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'),
            onChanged: (value) => ref
                .read(onboardingControllerProvider.notifier)
                .setIncome(Money.tryParse(value) ?? const Money.zero()),
          ),
          const SizedBox(height: 24),
          if (previous != null && previous.isNotEmpty) ...[
            Text(
              'Last month you started with',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            ActionChip(
              label: Text(previous.first.income.formatCompact()),
              avatar: const Icon(Icons.history, size: 18),
              onPressed: () {
                _field.text = previous.first.income.asRupees.toStringAsFixed(0);
                ref
                    .read(onboardingControllerProvider.notifier)
                    .setIncome(previous.first.income);
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — savings, before any spending is considered
// ---------------------------------------------------------------------------

class _SavingsStep extends ConsumerWidget {
  const _SavingsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pay yourself first', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Decide this before you plan any spending. Whatever is left is what '
            'you have to work with.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          SegmentedButton<SavingsMode>(
            segments: const [
              ButtonSegment(
                value: SavingsMode.percent,
                label: Text('Percentage'),
              ),
              ButtonSegment(
                value: SavingsMode.fixed,
                label: Text('Fixed amount'),
              ),
            ],
            selected: {state.savingsMode},
            onSelectionChanged: (selection) =>
                controller.setSavingsMode(selection.first),
          ),
          const SizedBox(height: 28),
          if (state.savingsMode == SavingsMode.percent)
            _PercentSlider(state: state, controller: controller)
          else
            _FixedAmountField(state: state, controller: controller),
          const SizedBox(height: 28),

          // The live consequence. This is the screen's actual argument: the
          // number the user is about to live with, updating as they decide.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _SummaryRow(label: 'Income', value: state.income.format()),
                  const SizedBox(height: 10),
                  _SummaryRow(
                    label: 'Savings',
                    value: '− ${state.savingsTarget.format()}',
                    valueColor: theme.colorScheme.primary,
                  ),
                  const Divider(height: 26),
                  _SummaryRow(
                    label: 'Left to spend',
                    value: state.spendable.format(),
                    emphasise: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PercentSlider extends StatelessWidget {
  const _PercentSlider({required this.state, required this.controller});

  final OnboardingState state;
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          '${state.savingsPercent.toStringAsFixed(0)}%',
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        Text(
          state.savingsTarget.format(),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Slider(
          value: state.savingsPercent,
          max: 60,
          divisions: 60,
          label: '${state.savingsPercent.toStringAsFixed(0)}%',
          onChanged: controller.setSavingsPercent,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final preset in [10.0, 20.0, 30.0, 50.0])
              ChoiceChip(
                label: Text('${preset.toStringAsFixed(0)}%'),
                selected: (state.savingsPercent - preset).abs() < 0.5,
                onSelected: (_) => controller.setSavingsPercent(preset),
              ),
          ],
        ),
      ],
    );
  }
}

class _FixedAmountField extends StatelessWidget {
  const _FixedAmountField({required this.state, required this.controller});

  final OnboardingState state;
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: state.savingsFixed.isZero
          ? ''
          : state.savingsFixed.asRupees.toStringAsFixed(0),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.]'))],
      style: Theme.of(context).textTheme.headlineMedium,
      decoration: const InputDecoration(prefixText: '₹ ', hintText: '0'),
      onChanged: (value) => controller.setSavingsFixed(
        Money.tryParse(value) ?? const Money.zero(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — the split
// ---------------------------------------------------------------------------

class _AllocationStep extends ConsumerWidget {
  const _AllocationStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Give every rupee a job',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Dividing ${state.spendable.format()}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _RemainingBanner(state: state),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            itemCount: kDefaultCategories.length,
            itemBuilder: (context, index) {
              final template = kDefaultCategories[index];
              final percent = state.categoryPercents[template.key] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _CategorySlider(
                  template: template,
                  percent: percent,
                  amount: state.amountFor(template.key),
                  onChanged: (value) =>
                      controller.setCategoryPercent(template.key, value),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RemainingBanner extends StatelessWidget {
  const _RemainingBanner({required this.state});

  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = state.remainingPercent;

    final (message, background, foreground) = state.isBalanced
        ? (
            'Every rupee is assigned',
            theme.colorScheme.primaryContainer,
            theme.colorScheme.onPrimaryContainer,
          )
        : remaining > 0
        ? (
            '${remaining.toStringAsFixed(1)}% unassigned '
                '(${state.spendable.percent(remaining).format()})',
            theme.colorScheme.tertiaryContainer,
            theme.colorScheme.onTertiaryContainer,
          )
        : (
            '${remaining.abs().toStringAsFixed(1)}% over',
            theme.colorScheme.errorContainer,
            theme.colorScheme.onErrorContainer,
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            state.isBalanced ? Icons.check_circle_outline : Icons.info_outline,
            size: 18,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySlider extends StatelessWidget {
  const _CategorySlider({
    required this.template,
    required this.percent,
    required this.amount,
    required this.onChanged,
  });

  final CategoryTemplate template;
  final double percent;
  final Money amount;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(template.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(template.name, style: theme.textTheme.titleSmall),
            ),
            Text(
              amount.formatCompact(),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 44,
              child: Text(
                '${percent.toStringAsFixed(0)}%',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: percent.clamp(0, 100),
          max: 100,
          divisions: 100,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasise
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: emphasise
              ? theme.textTheme.titleMedium
              : theme.textTheme.bodyLarge,
        ),
        Text(value, style: style?.copyWith(color: valueColor)),
      ],
    );
  }
}
