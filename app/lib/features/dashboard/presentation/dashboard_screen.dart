import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/router/routes.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/advisor_card.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/category_card.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/savings_reminder_card.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:budgetwise/features/insights/domain/insight_rules.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The home screen.
///
/// The hero figure answers the PRD's question — "how much can I safely spend
/// today?" — and everything below it is context, ordered by how often a person
/// needs it: what is left, what is committed, what needs attention, then detail.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = Period.current();
    final summary = ref.watch(budgetSummaryProvider(period));
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      body: SafeArea(
        child: AsyncView(
          value: summary,
          onRetry: () => ref.invalidate(budgetSummaryProvider),
          builder: (data) {
            if (data == null) {
              return const EmptyView(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No plan for this month yet',
                message: 'Set up your budget to get started.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.refreshBudgetData(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.xxl),
                children: [
                  _Greeting(profile: profile, period: period),
                  _DashboardBody(summary: data),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile, required this.period});

  final Profile? profile;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hour = DateTime.now().hour;
    final part = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final name = profile?.firstName ?? 'there';

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.xl, Gap.xs, Gap.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  period.label.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: 2),
                Text('$part, $name', style: theme.textTheme.headlineMedium),
              ],
            ),
          ),
          Gap.w12,
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.surfaceContainerHigh,
            backgroundImage: profile?.avatarUrl == null
                ? null
                : NetworkImage(profile!.avatarUrl!),
            child: profile?.avatarUrl != null
                ? null
                : Text(
                    name.characters.first.toUpperCase(),
                    style: theme.textTheme.titleMedium,
                  ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.summary});

  final BudgetSummary summary;

  /// How many categories the glance view shows before "View all" takes over
  /// — the ledger is the full record, this is a highlight reel.
  static const _categoryPreviewCount = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final safe = summary.safeDaily();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Hero: the one number this screen exists for. A deliberately larger
        // gap sets it apart as the screen's anchor.
        Gap.h8,
        _SafeToSpendFigure(summary: summary),
        Gap.h28,

        // The month at a glance, lined up rather than boxed.
        StatRow(
          children: [
            StatColumn(
              icon: Icons.account_balance_wallet_outlined,
              label: 'REMAINING',
              value: summary.remaining.formatCompact(),
              footnote: 'of ${summary.spendable.formatCompact()}',
            ),
            StatColumn(
              icon: Icons.savings_outlined,
              label: 'SAVED',
              value: summary.savedActual.formatCompact(),
              footnote: 'of ${summary.savingsTarget.formatCompact()}',
              tone: summary.savingsOutstanding.isZero ? scheme.healthy : null,
            ),
            StatColumn(
              icon: Icons.calendar_today_outlined,
              label: 'DAYS LEFT',
              value: '${safe.daysRemaining}',
              footnote: 'in ${summary.period.shortLabel}',
            ),
          ],
        ),
        Gap.h28,

        SavingsReminderCard(summary: summary),

        // Guidance sits above the raw detail: what to do about the numbers is
        // worth more than the numbers themselves.
        AsyncView(
          value: categories,
          loading: const SizedBox.shrink(),
          builder: (list) {
            final insights = generateInsights(summary: summary, categories: list);
            if (insights.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Gap.h28,
                SectionHeader(
                  title: 'Insights',
                  trailing: insights.length > 2 ? 'View all' : null,
                  action: insights.length > 2
                      ? () => context.go(Routes.insights)
                      : null,
                ),
                ListSection(
                  children: [
                    for (final insight in insights.take(2))
                      AdvisorCard(insight: insight),
                  ],
                ),
              ],
            );
          },
        ),

        Gap.h28,
        AsyncView(
          value: categories,
          loading: const _CategorySkeleton(),
          onRetry: () => ref.invalidate(categoriesProvider),
          builder: (list) {
            if (list.isEmpty) {
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title: 'Spending by category'),
                  EmptyView(
                    icon: Icons.category_outlined,
                    title: 'No categories',
                    message: 'This month has no spending categories yet.',
                  ),
                ],
              );
            }
            final byKey = {for (final c in list) c.key: c.progress};
            final preview = list.take(_categoryPreviewCount).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Spending by category',
                  trailing: list.length > _categoryPreviewCount
                      ? 'View all'
                      : null,
                  action: list.length > _categoryPreviewCount
                      ? () => context.go(Routes.ledger)
                      : null,
                ),
                ListSection(
                  children: [
                    for (final category in preview)
                      CategoryCard(
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
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The hero figure.
///
/// The one number the screen exists for, in a tinted card so it reads as the
/// screen's anchor at a glance — scale, a tone-coloured number/label/bar, and
/// now a border do that job together. The corner illustration is pure
/// chrome, never a data source: it is fixed decoration, not a chart.
class _SafeToSpendFigure extends ConsumerWidget {
  const _SafeToSpendFigure({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safe = summary.safeDaily();
    final unlock = ref.watch(investingStatusProvider).value;
    final spentRatio = summary.spent.ratioOf(summary.spendable).clamp(0.0, 1.0);
    final tone = safe.isExhausted ? scheme.exceeded : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          tone.withValues(alpha: 0.08),
          scheme.surfaceContainerLow,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Stack(
        children: [
          Positioned(right: -8, top: -8, child: _HeroDecoration(tone: tone)),
          Column(
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
                        color: tone,
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
              Gap.h12,
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: AnimatedMoneyText(
                  value: safe.perDay,
                  style: theme.textTheme.displayLarge?.money.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Gap.h8,
              Text(
                safe.daysRemaining <= 0
                    ? 'The month is over'
                    : '${summary.spent.formatCompact()} spent • '
                          '${summary.remaining.formatCompact()} remaining',
                style: theme.textTheme.bodySmall,
              ),
              Gap.h16,
              FlatBar(value: spentRatio, color: tone),
              Gap.h8,
              Text(
                '${(spentRatio * 100).round()}% of monthly budget',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A light, fixed illustration — a wallet with a scatter of small marks
/// around it. Decoration only: nothing here is a value, a percentage, or a
/// chart, and it never changes shape based on data. It exists purely to keep
/// the hero card from reading as an empty rectangle of text.
class _HeroDecoration extends StatelessWidget {
  const _HeroDecoration({required this.tone});

  final Color tone;

  @override
  Widget build(BuildContext context) {
    final faint = tone.withValues(alpha: 0.18);
    final faintest = tone.withValues(alpha: 0.1);

    return SizedBox(
      width: 96,
      height: 84,
      child: Stack(
        children: [
          Positioned(
            right: 10,
            top: 18,
            child: Icon(Icons.account_balance_wallet_outlined, size: 40, color: faint),
          ),
          Positioned(right: 0, top: 0, child: _dot(faintest, 10)),
          Positioned(right: 34, top: 6, child: _dot(faint, 5)),
          Positioned(right: 4, top: 54, child: _dot(faint, 7)),
        ],
      ),
    );
  }

  Widget _dot(Color color, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListSection(
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.lg),
            child: Container(
              height: 14,
              width: 160,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}
