import 'package:budgetwise/core/budget/health_score.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
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
              icon: '📈',
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _HealthScoreCard(score: score),
            const SizedBox(height: 14),
            _InvestingCard(claim: unlock.value),
            const SizedBox(height: 20),
            Text(
              'What we noticed',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final insight in insights)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InsightCard(insight: insight),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${score.score}',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4),
                  child: Text('/ 100', style: theme.textTheme.titleMedium),
                ),
                const Spacer(),
                Chip(
                  label: Text(score.band),
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Financial health this month',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // The breakdown, because a score with no explanation is a grade —
            // and the PRD asked for motivation, not grading.
            for (final component in score.components)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(component.label, style: theme.textTheme.bodySmall),
                        Text(
                          '${component.earned.round()}/${component.available.round()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: component.ratio,
                        minHeight: 5,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
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
    final progress = data.progress;
    final monthsLeft = data.monthsRemaining;

    return Card(
      color: isUnlocked ? theme.colorScheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isUnlocked ? '📈' : '🔒',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isUnlocked
                        ? 'Investing is unlocked'
                        : 'Investing is locked',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$streak of 6 months saved'
                '${monthsLeft > 0 ? " · $monthsLeft to go" : ""}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, background) = switch (insight.tone) {
      InsightTone.warning => ('⚠️', theme.colorScheme.tertiaryContainer),
      InsightTone.celebration => ('🎉', theme.colorScheme.primaryContainer),
      InsightTone.info => ('💡', theme.colorScheme.surfaceContainerLow),
    };

    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(insight.body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
