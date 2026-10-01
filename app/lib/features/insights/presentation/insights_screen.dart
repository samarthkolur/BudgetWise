import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/score_ring.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The health-score detail screen: the ring, larger, plus the breakdown that
/// explains it.
///
/// Reached only by pushing from Home (the health-score row, or its own "tap
/// for details" hint) — not a tab. What used to live here alongside the
/// score — the rule-based advisor cards, the investing-lock progress — now
/// live on Home (the invest-teaser card) and in Alerts (the same
/// `generateInsights` output, presented as the actionable feed); showing
/// them a third time here would just be the same facts twice. This screen's
/// only job is answering "why is the score what it is."
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = Period.current();
    final summary = ref.watch(budgetSummaryProvider(period));

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Health Score')),
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xl, Gap.lg, Gap.xxl),
          children: [_HealthScoreCard(score: score)],
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
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ScoreRing(score: score.score, label: score.band),
        ),
        Gap.h28,

        // The breakdown, because a score with no explanation is a grade —
        // and the PRD asked for motivation, not grading.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
          decoration: AppTheme.card(scheme),
          child: Column(
            children: [
              for (var i = 0; i < score.components.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.md),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(right: Gap.md, top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: score.components[i].ratio >= 1
                              ? scheme.healthy
                              : scheme.warning,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              score.components[i].label,
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              '${score.components[i].earned.round()}/'
                              '${score.components[i].available.round()} points',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
