import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/advisor_card.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/score_ring.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Insights, the health score, and the investing gate.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = Period.current();
    final summary = ref.watch(budgetSummaryProvider(period));

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(budgetSummaryProvider),
        builder: (data) {
          if (data == null) {
            return const EmptyView(
              icon: Icons.insights_outlined,
              title: 'Nothing to analyse yet',
              message: 'Set up this month to see how you are doing.',
            );
          }
          return _InsightsBody(summary: data);
        },
      ),
    );
  }
}

class _InsightsBody extends ConsumerWidget {
  const _InsightsBody({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final unlock = ref.watch(investingStatusProvider);

    return AsyncView(
      value: categories,
      onRetry: () => ref.invalidate(categoriesProvider),
      builder: (list) {
        final score = computeHealthScore(
          HealthScoreInput(
            savingsTarget: summary.savingsTarget,
            savingsActual: summary.savedActual,
            totalAllocated: summary.allocated,
            totalSpent: summary.spent,
            categoriesExceeded: list.where((c) => c.progress.isExceeded).length,
            categoryCount: list.length,
            daysWithExpenses: summary.daysWithExpenses,
            daysElapsed: summary.period.daysElapsed(),
            investingUnlocked: unlock.value?.isUnlocked ?? false,
            investmentTarget: summary.investmentTarget ?? const Money.zero(),
            investmentActual: summary.investedActual,
          ),
        );

        final insights = generateInsights(summary: summary, categories: list);

        return ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
          children: [
            _HealthScoreCard(score: score),
            Gap.h28,
            _InvestingCard(claim: unlock.value),
            Gap.h28,
            const AdvisorHeader(subtitle: 'Based on your budget rules'),
            ListSection(
              children: [
                for (final insight in insights) AdvisorCard(insight: insight),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HealthScoreCard extends StatelessWidget {
  const _HealthScoreCard({required this.score});

  final HealthScore score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: ScoreRing(score: score.score, label: score.band),
        ),
        Gap.h16,
        Center(
          child: Text(
            'Financial health this month',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Gap.h28,

        // The breakdown, because a score with no explanation is a grade —
        // and the PRD asked for motivation, not grading.
        for (final component in score.components)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(component.label, style: theme.textTheme.bodySmall),
                    Text(
                      '${component.earned.round()}/${component.available.round()}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                Gap.h4,
                FlatBar(
                  value: component.ratio,
                  color: theme.colorScheme.primary,
                  height: 4,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The investing gate, locked or unlocked.
///
/// While locked it shows progress toward the nearer of the two routes rather
/// than just refusing — the PRD's point is that the lock is a stage in a
/// journey, not a wall.
class _InvestingCard extends StatelessWidget {
  const _InvestingCard({required this.claim});

  final UnlockClaim? claim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = claim;
    if (data == null) return const SizedBox.shrink();

    final isUnlocked = data.isUnlocked;
    final streak = data.streakMonths;
    final monthsLeft = data.monthsRemaining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isUnlocked
                  ? Icons.trending_up_rounded
                  : Icons.lock_outline_rounded,
              size: 18,
              color: isUnlocked
                  ? theme.colorScheme.healthy
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isUnlocked ? 'Investing is unlocked' : 'Investing is locked',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isUnlocked
              ? 'You built the habit first. Investing features are available '
                    'from here on.'
              : 'Save consistently for six months, or build three months of '
                    'essential expenses as an emergency fund.',
          style: theme.textTheme.bodySmall,
        ),
        if (!isUnlocked) ...[
          Gap.h16,
          // Dots rather than a bar: "4 of 6" is something a person can
          // finish, where a percentage is just a number moving.
          StreakDots(completed: streak),
          Gap.h8,
          Text(
            '$streak of 6 months saved'
            '${monthsLeft > 0 ? " · $monthsLeft to go" : ""}',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ],
    );
  }
}
