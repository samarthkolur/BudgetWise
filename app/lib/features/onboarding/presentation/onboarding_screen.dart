import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/onboarding/application/onboarding_controller.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Five screens, matching the Claude Design prototype exactly: a welcome
/// screen, then three counted steps (income, savings, allocation), then a
/// success screen — each screen owns its own header and its own bottom
/// button, the way the prototype does it, rather than one shared app bar and
/// one shared button wrapping every page.
///
/// One real addition the prototype doesn't have: a name field, folded into
/// the welcome screen rather than given its own step. The prototype's demo
/// data never needed a name; this app's greeting ("Good evening, Aditi")
/// and `canSubmit` gate both do, and there's nowhere honest to get one
/// without asking. Savings still decided before any spending category is
/// shown, so the money is committed before it can be claimed — the PRD's
/// reversal, unchanged.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pageCount = 5;

  final _controller = PageController();
  int _step = 0;

  void _next() {
    if (_step < _pageCount - 1) {
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

  /// Fills in a sensible default for anything still unset, then submits
  /// immediately — the prototype's own skip does the same thing
  /// (`income: Number(s.incomeInput) || 45000`), landing straight on the
  /// dashboard rather than stepping through the rest of the wizard.
  /// Savings percent and the category split already default to sensible
  /// values from the moment onboarding starts, so income is the only real
  /// gap; `resetToDefaults` guards against a partially-edited, unbalanced
  /// allocation left over from an earlier step.
  Future<void> _skip() async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    final state = ref.read(onboardingControllerProvider);
    if (!state.isBalanced) controller.resetToDefaults();
    if (!state.income.isPositive) {
      controller.setIncome(Money.fromRupees(45000));
    }
    await _finish();
  }

  Future<void> _finish() async {
    try {
      await ref.read(onboardingControllerProvider.notifier).submit();
      AppHaptics.success();
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
    return Scaffold(
      body: SafeArea(
        child: PageView(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _step = index),
          children: [
            _WelcomeStep(onNext: _next, onSkip: _skip),
            _IncomeStep(onNext: _next, onBack: _back, onSkip: _skip),
            _SavingsStep(onNext: _next, onBack: _back, onSkip: _skip),
            _AllocationStep(onNext: _next, onBack: _back, onSkip: _skip),
            _SuccessStep(onFinish: _finish),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits: the per-step header, and the bottom CTA button
// ---------------------------------------------------------------------------

/// Back arrow (optional) + centered step counter + Skip — the prototype
/// builds this inline on every counted step rather than sharing one app bar.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.onSkip,
    this.onBack,
  });

  final int step;
  final VoidCallback? onBack;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SizedBox(
          width: 40,
          child: onBack == null
              ? null
              : PressableScale.onTap(
                  onTap: onBack,
                  child: Icon(Icons.arrow_back, color: scheme.onSurface),
                ),
        ),
        Text(
          'STEP $step OF 3',
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(
          width: 40,
          child: PressableScale.onTap(
            onTap: onSkip,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Skip', style: theme.textTheme.bodyMedium),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: PressableScale(
        child: FilledButton(
          onPressed: enabled && !busy ? onTap : null,
          child: busy
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 0 — welcome, and the one field the prototype doesn't have
// ---------------------------------------------------------------------------

class _WelcomeStep extends ConsumerStatefulWidget {
  const _WelcomeStep({required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final Future<void> Function() onSkip;

  @override
  ConsumerState<_WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends ConsumerState<_WelcomeStep> {
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
    final scheme = theme.colorScheme;
    final canProceed = ref.watch(
      onboardingControllerProvider.select(
        (s) => s.displayName.trim().isNotEmpty,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: canProceed ? 1 : 0.35,
              duration: const Duration(milliseconds: 200),
              child: PressableScale.onTap(
                onTap: canProceed ? widget.onSkip : null,
                child: Text(
                  'Skip to dashboard →',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'BUDGETWISE',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: AppType.display,
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ),
                  Gap.h16,
                  Text(
                    'Your money,\nwith a plan.',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontSize: 34,
                      height: 1.1,
                    ),
                  ),
                  Gap.h16,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      'Most apps tell you where your money went. BudgetWise '
                      'decides where it goes first — save before you spend, '
                      'every month.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.6,
                      ),
                    ),
                  ),
                  Gap.h28,
                  TextField(
                    controller: _field,
                    textCapitalization: TextCapitalization.words,
                    style: theme.textTheme.titleMedium,
                    decoration: const InputDecoration(hintText: 'Your name'),
                    onChanged: (value) => ref
                        .read(onboardingControllerProvider.notifier)
                        .setDisplayName(value),
                  ),
                  Gap.h20,
                  const _JourneyBadges(),
                  Gap.h12,
                  Text(
                    'EARN → SAVE → INVEST → SPEND',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Gap.h20,
          _StepButton(
            label: "Let's build your plan",
            enabled: canProceed,
            onTap: widget.onNext,
          ),
        ],
      ),
    );
  }
}

/// The E · S · I · S badges, connected by hairlines — decoration only, always
/// showing "earn" as the current step since this screen precedes all of them.
class _JourneyBadges extends StatelessWidget {
  const _JourneyBadges();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget badge(String letter, {required bool active}) => Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? scheme.primary : scheme.surfaceContainerLow,
        border: active ? null : Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        letter,
        style: theme.textTheme.labelLarge?.copyWith(
          color: active ? Colors.white : scheme.onSurface,
        ),
      ),
    );

    Widget line() => Container(
      width: 16,
      height: 1,
      color: scheme.outlineVariant,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );

    return Row(
      children: [
        badge('E', active: true),
        line(),
        badge('S', active: false),
        line(),
        badge('I', active: false),
        line(),
        badge('S', active: false),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — income
// ---------------------------------------------------------------------------

class _IncomeStep extends ConsumerStatefulWidget {
  const _IncomeStep({
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;
  final Future<void> Function() onSkip;

  @override
  ConsumerState<_IncomeStep> createState() => _IncomeStepState();
}

class _IncomeStepState extends ConsumerState<_IncomeStep> {
  late final TextEditingController _field;

  static final _quickIncomes = [
    15000,
    25000,
    45000,
    70000,
  ].map(Money.fromRupees).toList();

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

  void _setIncome(Money value) {
    _field.text = value.asRupees.toStringAsFixed(0);
    ref.read(onboardingControllerProvider.notifier).setIncome(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final previous = ref.watch(allBudgetsProvider).value;
    final canProceed = ref.watch(
      onboardingControllerProvider.select((s) => s.income.isPositive),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          _StepHeader(step: 1, onBack: widget.onBack, onSkip: widget.onSkip),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'What do you earn this month?',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 26,
                    ),
                  ),
                  Gap.h8,
                  Text(
                    'Salary, allowance, freelance work — anything recurring.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Gap.h28,
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '₹',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 28,
                            color: scheme.primary,
                          ),
                        ),
                        Gap.w8,
                        Expanded(
                          child: TextField(
                            controller: _field,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp('[0-9.]'),
                              ),
                            ],
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontSize: 36,
                            ),
                            decoration: InputDecoration(
                              hintText: '0',
                              hintStyle: theme.textTheme.headlineMedium
                                  ?.copyWith(
                                    fontSize: 36,
                                    color: scheme.onSurfaceVariant,
                                  ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            onChanged: (value) => ref
                                .read(onboardingControllerProvider.notifier)
                                .setIncome(
                                  Money.tryParse(value) ?? const Money.zero(),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Gap.h20,
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (previous != null && previous.isNotEmpty)
                        ActionChip(
                          label: Text(previous.first.income.formatCompact()),
                          avatar: const Icon(Icons.history, size: 16),
                          onPressed: () => _setIncome(previous.first.income),
                        ),
                      for (final amount in _quickIncomes)
                        ActionChip(
                          label: Text(amount.formatCompact()),
                          onPressed: () => _setIncome(amount),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Gap.h20,
          _StepButton(
            label: 'Continue',
            enabled: canProceed,
            onTap: widget.onNext,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — savings, before any spending is considered
// ---------------------------------------------------------------------------

class _SavingsStep extends ConsumerWidget {
  const _SavingsStep({
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          _StepHeader(step: 2, onBack: onBack, onSkip: onSkip),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'How much will you save first?',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 26,
                    ),
                  ),
                  Gap.h8,
                  Text(
                    'Before rent, before fun. Savings gets paid first.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Gap.h20,
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
                  Gap.h20,
                  if (state.savingsMode == SavingsMode.percent)
                    _PercentSlider(state: state, controller: controller)
                  else
                    _FixedAmountField(state: state, controller: controller),
                  Gap.h20,
                  Row(
                    children: [
                      Expanded(
                        child: MiniStatCard(
                          label: 'SAVING',
                          value: state.savingsTarget.format(),
                          tone: theme.colorScheme.primary,
                        ),
                      ),
                      Gap.w12,
                      Expanded(
                        child: MiniStatCard(
                          label: 'SPENDABLE',
                          value: state.spendable.format(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Gap.h20,
          _StepButton(label: 'Continue', onTap: onNext),
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
    return Slider(
      value: state.savingsPercent,
      min: 5,
      max: 60,
      divisions: 55,
      label: '${state.savingsPercent.toStringAsFixed(0)}%',
      onChanged: controller.setSavingsPercent,
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
// Step 3 — the split: one uniform, inline-slider card per category
// ---------------------------------------------------------------------------

class _AllocationStep extends ConsumerWidget {
  const _AllocationStep({
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  final VoidCallback onNext;
  final VoidCallback onBack;
  final Future<void> Function() onSkip;

  static const _dotColors = [
    Color(0xFFFF6B4A),
    Color(0xFF1B2340),
    Color(0xFF3A9D68),
    Color(0xFFC97F1E),
    Color(0xFF4C5FA8),
    Color(0xFFD64545),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(step: 3, onBack: onBack, onSkip: onSkip),
          Gap.h16,
          Text(
            'Now, divide the rest',
            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 22),
          ),
          Gap.h4,
          Text(
            'Allocate ${state.spendable.format()} across your categories.',
            style: theme.textTheme.bodyMedium,
          ),
          Gap.h16,
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < kDefaultCategories.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CategorySliderCard(
                      template: kDefaultCategories[i],
                      percent:
                          state.categoryPercents[kDefaultCategories[i].key] ??
                          0,
                      amount: state.amountFor(kDefaultCategories[i].key),
                      dotColor: _dotColors[i % _dotColors.length],
                      onChanged: (value) => controller.setCategoryPercent(
                        kDefaultCategories[i].key,
                        value,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  state.isBalanced
                      ? 'Every rupee is assigned'
                      : state.remainingPercent > 0
                      ? '${state.remainingPercent.toStringAsFixed(1)}% unassigned'
                      : '${state.remainingPercent.abs().toStringAsFixed(1)}% over',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              PressableScale.onTap(
                onTap: () {
                  AppHaptics.tap();
                  controller.resetToDefaults();
                },
                child: Text(
                  'Auto-balance',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Gap.h12,
          _StepButton(
            label: 'Create my plan',
            enabled: state.isBalanced,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _CategorySliderCard extends StatelessWidget {
  const _CategorySliderCard({
    required this.template,
    required this.percent,
    required this.amount,
    required this.dotColor,
    required this.onChanged,
  });

  final CategoryTemplate template;
  final double percent;
  final Money amount;
  final Color dotColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.card(scheme, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Gap.w8,
                  Text(template.name, style: theme.textTheme.titleSmall),
                  Gap.w8,
                  Text(
                    '${percent.toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              Text(
                amount.formatCompact(),
                style: theme.textTheme.titleSmall?.money.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: percent.clamp(0, 60),
            max: 60,
            divisions: 60,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — success
// ---------------------------------------------------------------------------

class _SuccessStep extends ConsumerWidget {
  const _SuccessStep({required this.onFinish});

  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                Gap.h20,
                Text(
                  'Your ${state.period.label} plan is ready!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 24,
                  ),
                ),
                Gap.h12,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Text(
                    'Savings come first, every category has a job, and the '
                    'dashboard will do the maths from here.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Gap.h28,
                Row(
                  children: [
                    Expanded(
                      child: MiniStatCard(
                        label: 'INCOME',
                        value: state.income.formatCompact(),
                      ),
                    ),
                    Gap.w12,
                    Expanded(
                      child: MiniStatCard(
                        label: 'SAVING',
                        value: state.savingsTarget.formatCompact(),
                        tone: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _StepButton(
            label: 'Go to dashboard',
            busy: state.isSubmitting,
            enabled: state.canSubmit || state.isSubmitting,
            onTap: onFinish,
          ),
        ],
      ),
    );
  }
}
