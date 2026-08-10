import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/onboarding/application/onboarding_controller.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Four steps: who you are, income, savings, then the split.
///
/// The order is the product's argument, twice over. The profile step comes
/// first because everything after it addresses the user by name — a greeting
/// that says "there" because the app asked for a budget before a name would
/// undercut the very first impression. Savings is decided before any spending
/// category is even shown, so the money is committed before it can be claimed
/// — which is the reversal the PRD is built around.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;

  final _controller = PageController();
  int _step = 0;

  void _next() {
    if (_step < _stepCount - 1) {
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
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: (_step + 1) / _stepCount),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
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
                  _ProfileStep(),
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
                  onPressed: state.displayName.trim().isNotEmpty ? _next : null,
                  child: const Text('Continue'),
                ),
                1 => FilledButton(
                  onPressed: state.income.isPositive ? _next : null,
                  child: const Text('Continue'),
                ),
                2 => FilledButton(
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
// Step 0 — who's budgeting
// ---------------------------------------------------------------------------

class _ProfileStep extends ConsumerStatefulWidget {
  const _ProfileStep();

  @override
  ConsumerState<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends ConsumerState<_ProfileStep> {
  late final TextEditingController _field;

  @override
  void initState() {
    super.initState();
    _field = TextEditingController(
      text: ref.read(onboardingControllerProvider).displayName,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Who is this for?', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Just a first name — everything after this addresses you by it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _field,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            onChanged: (value) => ref
                .read(onboardingControllerProvider.notifier)
                .setDisplayName(value),
          ),
        ],
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
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: '0',
              hintStyle: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
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
          const Divider(height: 1),

          // The live consequence. This is the screen's actual argument: the
          // number the user is about to live with, updating as they decide.
          MoneyRow(label: 'Income', value: state.income.format()),
          MoneyRow(
            label: 'Savings',
            value: '− ${state.savingsTarget.format()}',
            valueColor: theme.colorScheme.primary,
          ),
          const Divider(height: 26),
          MoneyRow(
            label: 'Left to spend',
            value: state.spendable.format(),
            emphasise: true,
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
    final theme = Theme.of(context);
    return TextFormField(
      initialValue: state.savingsFixed.isZero
          ? ''
          : state.savingsFixed.asRupees.toStringAsFixed(0),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.]'))],
      style: theme.textTheme.headlineMedium,
      decoration: InputDecoration(
        prefixText: '₹ ',
        hintText: '0',
        hintStyle: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
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
    final essentials = kDefaultCategories.where((t) => t.isEssential).toList();
    final addOns = kDefaultCategories.where((t) => !t.isEssential).toList();

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
                'Dividing ${state.spendable.format()}. Tap an amount to set it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _RemainingBanner(state: state),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              Text(
                'ESSENTIALS',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              ListSection(
                children: [
                  for (final template in essentials)
                    _EssentialRow(
                      name: template.name,
                      amount: state.amountFor(template.key),
                      percent: state.categoryPercents[template.key] ?? 0,
                      onTap: () => _showAmountSheet(
                        context: context,
                        controller: controller,
                        template: template,
                        current: state.amountFor(template.key),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'ADD ONS',
                style: theme.textTheme.labelMedium?.copyWith(
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Optional — tap to give one a budget.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final template in addOns)
                    _AddOnChip(
                      name: template.name,
                      amount: state.amountFor(template.key),
                      isActive: (state.categoryPercents[template.key] ?? 0) > 0,
                      onTap: () => _showAmountSheet(
                        context: context,
                        controller: controller,
                        template: template,
                        current: state.amountFor(template.key),
                      ),
                    ),
                ],
              ),
            ],
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
    final scheme = theme.colorScheme;
    final remaining = state.remainingPercent;

    final (message, tone) = state.isBalanced
        ? ('Every rupee is assigned', scheme.healthy)
        : remaining > 0
        ? (
            '${remaining.toStringAsFixed(1)}% unassigned '
                '(${state.spendable.percent(remaining).format()})',
            scheme.warning,
          )
        : ('${remaining.abs().toStringAsFixed(1)}% over', scheme.exceeded);

    return Row(
      children: [
        Icon(
          state.isBalanced ? Icons.check_circle_outline : Icons.info_outline,
          size: 16,
          color: tone,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: tone),
          ),
        ),
      ],
    );
  }
}

/// One of the four categories everyone has, whatever they call it. Always
/// present, never a chip to tap into existence — the compulsory half of the
/// split. Plain typography, no icon: the name and the amount are the whole
/// row.
class _EssentialRow extends StatelessWidget {
  const _EssentialRow({
    required this.name,
    required this.amount,
    required this.percent,
    required this.onTap,
  });

  final String name;
  final Money amount;
  final double percent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name, style: theme.textTheme.bodyLarge),
            Row(
              children: [
                Text(
                  amount.formatCompact(),
                  style: theme.textTheme.titleSmall?.money,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 34,
                  child: Text(
                    '${percent.toStringAsFixed(0)}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything else: not shown as a row at all until tapped in. Inactive, it
/// is a name with a border around it, exactly the shape of a tag waiting to
/// be picked — active, the border fills in and the amount replaces the name.
/// This is the entire "optional" argument made visible: nothing here demands
/// attention until the user gives it some.
class _AddOnChip extends StatelessWidget {
  const _AddOnChip({
    required this.name,
    required this.amount,
    required this.isActive,
    required this.onTap,
  });

  final String name;
  final Money amount;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: isActive ? scheme.surfaceContainer : null,
          border: Border.all(
            color: isActive ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        child: Text(
          isActive ? '$name · ${amount.formatCompact()}' : '+ $name',
          style: theme.textTheme.labelLarge?.copyWith(
            color: isActive ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A focused amount entry, for the one category the sheet is about — the same
/// pattern as the expense sheet's amount field, so typing a rupee figure
/// feels the same everywhere in the app.
void _showAmountSheet({
  required BuildContext context,
  required OnboardingController controller,
  required CategoryTemplate template,
  required Money current,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) =>
        _AmountSheet(controller: controller, template: template, current: current),
  );
}

/// A real `StatefulWidget` rather than a bare builder closure — its text
/// controller is created in `initState` and disposed in `dispose`, so
/// Flutter tears it down only once the sheet's Element is actually
/// unmounted. The earlier version created the controller outside
/// the builder and disposed it with `.whenComplete()` on the sheet's Future,
/// which resolves the moment the route starts closing, not once its exit
/// animation finishes — disposing a controller a still-animating TextField
/// depends on is what was tripping Flutter's `_dependents.isEmpty`
/// assertion. Not autofocusing removes the other half of the risk: opening
/// or closing the sheet no longer has to race a keyboard transition at all.
class _AmountSheet extends StatefulWidget {
  const _AmountSheet({
    required this.controller,
    required this.template,
    required this.current,
  });

  final OnboardingController controller;
  final CategoryTemplate template;
  final Money current;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final _field = TextEditingController(
    text: widget.current.isZero
        ? ''
        : widget.current.asRupees.toStringAsFixed(0),
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = Money.tryParse(_field.text) ?? const Money.zero();
    widget.controller.setCategoryAmount(widget.template.key, amount);
    Navigator.of(context).pop();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.template.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _submit, child: const Text('Save')),
        ],
      ),
    );
  }
}
