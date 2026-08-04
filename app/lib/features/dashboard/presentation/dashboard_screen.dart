import 'package:budgetwise/core/budget/budget_math.dart';
import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/category_card.dart';
import 'package:budgetwise/features/dashboard/presentation/widgets/savings_reminder_card.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The home screen, built to answer one question.
///
/// The PRD's framing — "how much money can I safely spend today?" — is taken
/// literally: that figure is the largest thing on the screen, and everything
/// else is context for it.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = Period.current();
    final summary = ref.watch(budgetSummaryProvider(period));
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile == null ? 'Hi there' : 'Hi ${profile.firstName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refreshBudgetData(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: summary.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  showExpenseSheet(context, ref, summary.value!.budgetId),
              icon: const Icon(Icons.add),
              label: const Text('Expense'),
            ),
      body: AsyncView(
        value: summary,
        onRetry: () => ref.invalidate(budgetSummaryProvider),
        builder: (data) {
          if (data == null) {
            return const EmptyView(
              icon: '📋',
              title: 'No plan for this month yet',
              message: 'Set up your budget to get started.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refreshBudgetData(),
            child: _DashboardBody(summary: data),
          );
        },
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider(summary.budgetId));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _SafeToSpendCard(summary: summary),
        const SizedBox(height: 12),
        SavingsReminderCard(summary: summary),
        const SizedBox(height: 12),
        _MonthOverview(summary: summary),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Categories', style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${summary.period.daysRemaining()} days left',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AsyncView(
          value: categories,
          loading: const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          onRetry: () => ref.invalidate(categoriesProvider),
          builder: (list) {
            if (list.isEmpty) {
              return const EmptyView(
                icon: '🗂️',
                title: 'No categories',
                message: 'This month has no spending categories yet.',
              );
            }

            final byKey = {for (final c in list) c.key: c.progress};

            return Column(
              children: [
                for (final category in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CategoryCard(
                      category: category,
                      suggestion: category.progress.isExceeded
                          ? suggestReallocation(
                              overspend: category.progress.overspend,
                              categories: byKey,
                              excludingKey: category.key,
                            )
                          : null,
                      categoryNames: {for (final c in list) c.key: c.name},
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

/// The headline figure.
class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safe = summary.safeDaily();

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              safe.isExhausted
                  ? 'Nothing left to spend'
                  : 'Safe to spend today',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              safe.perDay.formatCompact(),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              safe.daysRemaining <= 0
                  ? 'The month is over'
                  : '${summary.remaining.formatCompact()} left · '
                        '${safe.daysRemaining} ${safe.daysRemaining == 1 ? "day" : "days"} to go',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer.withValues(
                  alpha: 0.85,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthOverview extends StatelessWidget {
  const _MonthOverview({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spentRatio = summary.spent.ratioOf(summary.spendable).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                _Stat(label: 'Income', value: summary.income.formatCompact()),
                _Stat(
                  label: 'Savings',
                  value: summary.savingsTarget.formatCompact(),
                  color: theme.colorScheme.primary,
                ),
                _Stat(label: 'Spent', value: summary.spent.formatCompact()),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: spentRatio,
                minHeight: 8,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(
                  theme.colorScheme.statusColor(
                    CategoryStatus.forRatio(spentRatio),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(spentRatio * 100).toStringAsFixed(0)}% of ${summary.spendable.formatCompact()} spent',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${summary.expenseCount} ${summary.expenseCount == 1 ? "entry" : "entries"}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
