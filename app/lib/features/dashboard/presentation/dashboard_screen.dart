import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/router/routes.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/core/widgets/score_ring.dart';
import 'package:budgetwise/features/auth/data/profile_repository.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/category_card.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/savings_reminder_card.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
                  _Greeting(profile: profile),
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
  const _Greeting({required this.profile});

  final Profile? profile;

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
                Text(part, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(name, style: theme.textTheme.headlineMedium),
              ],
            ),
          ),
          Gap.w12,
          PressableScale.onTap(
            onTap: () {
              AppHaptics.tap();
              context.push(Routes.settings);
            },
            child: CircleAvatar(
              radius: 22,
              backgroundColor: scheme.surfaceContainerHigh,
              backgroundImage: profile?.avatarUrl == null
                  ? null
                  : NetworkImage(profile!.avatarUrl!),
              child: profile?.avatarUrl != null
                  ? null
                  : Text(
                      name.characters.first.toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: AppType.display,
                        color: scheme.primary,
                      ),
                    ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final expenses = ref.watch(expensesProvider(summary.budgetId));
    final unlock = ref.watch(investingStatusProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Gap.h8,
        _SafeToSpendFigure(summary: summary),
        Gap.h16,

        Row(
          children: [
            Expanded(
              child: MiniStatCard(
                label: 'INCOME',
                value: summary.income.formatCompact(),
              ),
            ),
            Gap.w8,
            Expanded(
              child: MiniStatCard(
                label: 'SAVED',
                value: summary.savedActual.formatCompact(),
                tone: scheme.primary,
              ),
            ),
            Gap.w8,
            Expanded(
              child: MiniStatCard(
                label: 'SPENT',
                value: summary.spent.formatCompact(),
                tone: scheme.warning,
              ),
            ),
          ],
        ),
        Gap.h16,

        SavingsReminderCard(summary: summary),

        if (unlock != null && !unlock.isUnlocked) ...[
          Gap.h16,
          _InvestTeaserCard(unlock: unlock),
        ],

        Gap.h16,
        AsyncView(
          value: categories,
          loading: const SizedBox.shrink(),
          builder: (list) => _HealthScoreRow(
            summary: summary,
            categories: list,
            unlock: unlock,
          ),
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
                  SectionHeader(title: 'Spending categories'),
                  EmptyView(
                    icon: Icons.category_outlined,
                    title: 'No categories',
                    message: 'This month has no spending categories yet.',
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: 'Spending categories'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: Gap.md,
                  mainAxisSpacing: Gap.md,
                  childAspectRatio: 1.5,
                  children: [
                    for (final category in list)
                      CategoryCard(
                        category: category,
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

        Gap.h28,
        AsyncView(
          value: expenses,
          loading: const SizedBox.shrink(),
          builder: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            final recent = list.take(3).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Recent activity',
                  trailing: 'View ledger',
                  action: () => context.go(Routes.ledger),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
                  decoration: AppTheme.card(scheme),
                  child: ListSection(
                    children: [
                      for (final expense in recent)
                        _RecentExpenseRow(
                          expense: expense,
                          budgetId: summary.budgetId,
                        ),
                    ],
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

/// The hero figure.
///
/// The one number the screen exists for, on a navy card so it reads as the
/// screen's anchor at a glance.
class _SafeToSpendFigure extends StatelessWidget {
  const _SafeToSpendFigure({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final safe = summary.safeDaily();
    final spentRatio = summary.spent.ratioOf(summary.spendable).clamp(0.0, 1.0);
    final tone = safe.isExhausted ? scheme.exceeded : scheme.primary;

    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2340),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.cardShadow(Brightness.light),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            safe.isExhausted ? 'NOTHING LEFT TO SPEND' : 'SAFE TO SPEND TODAY',
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          Gap.h8,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedMoneyText(
              value: safe.perDay,
              style: theme.textTheme.displayMedium?.money.copyWith(
                color: tone,
              ),
            ),
          ),
          Gap.h8,
          Text(
            safe.daysRemaining <= 0
                ? 'The month is over'
                : '${summary.remaining.formatCompact()} left · '
                      '${safe.daysRemaining} days to go',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          Gap.h16,
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: spentRatio),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, animated, _) => LinearProgressIndicator(
                  value: animated,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(tone),
                ),
              ),
            ),
          ),
          Gap.h8,
          Text(
            '${(spentRatio * 100).round()}% of monthly budget',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prototype's invest-progress teaser: shown while the six-month streak
/// is still building, dropped once it's unlocked (the app shell then shows
/// the celebration exactly once, on the transition).
class _InvestTeaserCard extends StatelessWidget {
  const _InvestTeaserCard({required this.unlock});

  final UnlockClaim unlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final monthsToInvest = (6 - unlock.streakMonths).clamp(0, 6);
    final progress = (unlock.streakMonths / 6).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: AppTheme.card(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Investing unlocks in $monthsToInvest month'
            '${monthsToInvest == 1 ? "" : "s"}',
            style: theme.textTheme.titleSmall,
          ),
          Gap.h8,
          FlatBar(value: progress, color: scheme.primary, height: 8),
          Gap.h8,
          Text(
            '${unlock.streakMonths} of 6 months saved consistently',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// A compact, tappable row into the merged health-and-insights screen.
class _HealthScoreRow extends StatelessWidget {
  const _HealthScoreRow({
    required this.summary,
    required this.categories,
    required this.unlock,
  });

  final BudgetSummary summary;
  final List<CategorySpend> categories;
  final UnlockClaim? unlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = computeHealthScore(
      HealthScoreInput(
        savingsTarget: summary.savingsTarget,
        savingsActual: summary.savedActual,
        totalAllocated: summary.allocated,
        totalSpent: summary.spent,
        categoriesExceeded: categories
            .where((c) => c.progress.isExceeded)
            .length,
        categoryCount: categories.length,
        daysWithExpenses: summary.daysWithExpenses,
        daysElapsed: summary.period.daysElapsed(),
        investingUnlocked: unlock?.isUnlocked ?? false,
        investmentTarget: summary.investmentTarget ?? const Money.zero(),
        investmentActual: summary.investedActual,
      ),
    );

    return PressableScale.onTap(
      onTap: () {
        AppHaptics.tap();
        context.push(Routes.insights);
      },
      child: Container(
        padding: const EdgeInsets.all(Gap.lg),
        decoration: AppTheme.card(scheme),
        child: Row(
          children: [
            ScoreRing(score: score.score, label: '', size: 56, stroke: 6),
            Gap.w16,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Financial Health Score',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    '${score.band} · tap for details',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentExpenseRow extends ConsumerWidget {
  const _RecentExpenseRow({required this.expense, required this.budgetId});

  final Expense expense;
  final String budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        expense.note?.isNotEmpty ?? false
            ? expense.note!
            : expense.categoryName ?? 'Expense',
      ),
      subtitle: Text(
        [
          DateFormat('d MMM').format(expense.spentOn),
          expense.categoryName ?? 'Uncategorised',
        ].join(' · '),
      ),
      trailing: Text(
        '−${expense.amount.formatCompact()}',
        style: theme.textTheme.titleSmall?.money,
      ),
      onTap: () => showExpenseSheet(context, ref, budgetId, editing: expense),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: Gap.md,
      mainAxisSpacing: Gap.md,
      childAspectRatio: 1.5,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            decoration: AppTheme.card(scheme, radius: 16),
          ),
      ],
    );
  }
}
