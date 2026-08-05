import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/advisor_card.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/category_card.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/savings_reminder_card.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The home screen, as a bento grid.
///
/// The hero tile answers the PRD's question — "how much can I safely spend
/// today?" — and everything below it is context, ordered by how often a person
/// needs it: what is left, what is committed, what needs attention, then detail.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = Period.current();
    final summary = ref.watch(budgetSummaryProvider(period));
    final profile = ref.watch(profileProvider).value;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: AsyncView(
          value: summary,
          onRetry: () => ref.invalidate(budgetSummaryProvider),
          builder: (data) {
            if (data == null) {
              return const EmptyView(
                icon: '◎',
                title: 'No plan for this month yet',
                message: 'Set up your budget to get started.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.refreshBudgetData(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, 110),
                children: [
                  _Greeting(
                    name: profile?.firstName ?? 'there',
                    period: period,
                  ),
                  _Bento(summary: data),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: summary.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  showExpenseSheet(context, ref, summary.value!.budgetId),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Expense',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.name, required this.period});

  final String name;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xl, Gap.xs, Gap.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(period.label.toUpperCase(), style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text('$part, $name', style: theme.textTheme.headlineMedium),
        ],
      ),
    );
  }
}

class _Bento extends ConsumerWidget {
  const _Bento({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final safe = summary.safeDaily();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero: the one number this screen exists for.
        _SafeToSpendTile(summary: summary),
        Gap.h12,

        // Three tiles: the month at a glance.
        BentoRow(
          children: [
            BentoStat(
              label: 'REMAINING',
              value: summary.remaining.formatCompact(),
              footnote: 'of ${summary.spendable.formatCompact()}',
              icon: Icons.account_balance_wallet_outlined,
            ),
            BentoStat(
              label: 'SAVED',
              value: summary.savedActual.formatCompact(),
              footnote: 'of ${summary.savingsTarget.formatCompact()}',
              icon: Icons.savings_outlined,
              tone: summary.savingsOutstanding.isZero ? scheme.healthy : null,
            ),
            BentoStat(
              label: 'DAYS LEFT',
              value: '${safe.daysRemaining}',
              footnote: 'in ${summary.period.shortLabel}',
              icon: Icons.calendar_today_outlined,
            ),
          ],
        ),
        Gap.h12,

        SavingsReminderCard(summary: summary),

        // Guidance sits above the raw detail: what to do about the numbers is
        // worth more than the numbers themselves.
        AsyncView(
          value: categories,
          loading: const SizedBox.shrink(),
          builder: (list) {
            final insights = generateInsights(
              summary: summary,
              categories: list,
            ).take(2).toList();
            if (insights.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Gap.h28,
                const AdvisorHeader(subtitle: 'Based on your budget rules'),
                Gap.h12,
                for (final insight in insights) ...[
                  AdvisorCard(insight: insight),
                  Gap.h8,
                ],
              ],
            );
          },
        ),

        Gap.h28,
        const SectionHeader(title: 'Where it goes'),
        AsyncView(
          value: categories,
          loading: const _CategorySkeleton(),
          onRetry: () => ref.invalidate(categoriesProvider),
          builder: (list) {
            if (list.isEmpty) {
              return const EmptyView(
                icon: '◇',
                title: 'No categories',
                message: 'This month has no spending categories yet.',
              );
            }
            final byKey = {for (final c in list) c.key: c.progress};
            return Column(
              children: [
                for (final category in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: CategoryCard(
                      category: category,
                      categoryNames: {for (final c in list) c.key: c.name},
                      suggestion: category.progress.isExceeded
                          ? suggestReallocation(
                              overspend: category.progress.overspend,
                              categories: byKey,
                              excludingKey: category.key,
                            )
                          : null,
                      onTap: () => showExpenseSheet(
                        context,
                        ref,
                        summary.budgetId,
                        preselectedCategoryId: category.id,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The hero tile.
///
/// Tinted with the accent and the only tile using display type, so there is
/// never a question about what this screen is for.
class _SafeToSpendTile extends ConsumerWidget {
  const _SafeToSpendTile({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safe = summary.safeDaily();
    final unlock = ref.watch(investingStatusProvider).value;
    final spentRatio = summary.spent.ratioOf(summary.spendable).clamp(0.0, 1.0);

    return BentoTile(
      tone: safe.isExhausted ? scheme.exceeded : scheme.primary,
      padding: const EdgeInsets.all(Gap.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  safe.isExhausted
                      ? 'NOTHING LEFT TO SPEND'
                      : 'SAFE TO SPEND TODAY',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: safe.isExhausted ? scheme.exceeded : scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (unlock != null && unlock.streakMonths > 0)
                TonePill(
                  label: '${unlock.streakMonths} mo streak',
                  tone: scheme.primary,
                  icon: Icons.local_fire_department_outlined,
                ),
            ],
          ),
          Gap.h8,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              safe.perDay.formatCompact(),
              style: theme.textTheme.displayLarge?.money.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Gap.h16,
          FlatBar(
            value: spentRatio,
            color: safe.isExhausted ? scheme.exceeded : scheme.primary,
          ),
          Gap.h8,
          Text(
            safe.daysRemaining <= 0
                ? 'The month is over'
                : '${summary.spent.formatCompact()} spent · '
                      '${summary.remaining.formatCompact()} left for '
                      '${safe.daysRemaining} ${safe.daysRemaining == 1 ? "day" : "days"}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Container(
              height: 84,
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
      ],
    );
  }
}
