import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/router/routes.dart';
import 'package:budgetwise/core/theme/app_theme.dart';
import 'package:budgetwise/core/theme/app_typography.dart';
import 'package:budgetwise/core/theme/category_icons.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/core/widgets/bento.dart';
import 'package:budgetwise/core/widgets/motion.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:budgetwise/features/export/data/export_service.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// The monthly ledger: income, savings, allocations, every transaction, and the
/// month's totals — the spreadsheet the PRD says users should never have to
/// maintain by hand.
class LedgerScreen extends ConsumerWidget {
  const LedgerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(selectedPeriodProvider);
    final summary = ref.watch(budgetSummaryProvider(period));
    final months = ref.watch(allBudgetsProvider).value ?? const [];

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Ledger', style: theme.textTheme.headlineMedium),
        toolbarHeight: 76,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 12),
            child: Text(
              'Track your monthly finances',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _MonthSwitcher(period: period, available: months),
          Expanded(
            child: AsyncView(
              value: summary,
              onRetry: () => ref.invalidate(budgetSummaryProvider),
              builder: (data) {
                if (data == null) {
                  return EmptyView(
                    icon: Icons.event_busy_outlined,
                    title: 'Nothing for ${period.label}',
                    message: 'There is no plan recorded for this month.',
                  );
                }
                return _LedgerBody(summary: data);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSwitcher extends ConsumerWidget {
  const _MonthSwitcher({required this.period, required this.available});

  final Period period;
  final List<MonthlyBudget> available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = Period.current();

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundIconButton(
            icon: Icons.chevron_left,
            onPressed: () =>
                ref.read(selectedPeriodProvider.notifier).previous(),
          ),
          Column(
            children: [
              Text(period.label, style: theme.textTheme.titleLarge),
              if (period == current)
                Text(
                  'This month',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          _RoundIconButton(
            icon: Icons.chevron_right,
            // A future month has no plan and nothing to show. Stopping at the
            // current month keeps the user out of a permanent empty state they
            // have to navigate back out of.
            onPressed: period.isBefore(current)
                ? () => ref.read(selectedPeriodProvider.notifier).next()
                : null,
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: onPressed == null
            ? scheme.onSurfaceVariant.withValues(alpha: 0.4)
            : scheme.onSurface,
        shape: const CircleBorder(),
      ),
    );
  }
}

class _LedgerBody extends ConsumerWidget {
  const _LedgerBody({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final expenses = ref.watch(expensesProvider(summary.budgetId));

    final spentRatio = (summary.spent.ratioOf(summary.spendable) * 100)
        .clamp(0, 100)
        .round();
    final remainingRatio = (summary.remaining.ratioOf(summary.spendable) * 100)
        .clamp(0, 100)
        .round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.xxl),
      children: [
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
                label: 'SAVINGS TARGET',
                value: summary.savingsTarget.formatCompact(),
                tone: scheme.primary,
              ),
            ),
            Gap.w8,
            Expanded(
              child: MiniStatCard(
                label: 'SAVINGS ACTUAL',
                value: summary.savedActual.formatCompact(),
              ),
            ),
          ],
        ),
        Gap.h8,
        Row(
          children: [
            Expanded(
              child: MiniStatCard(
                label: 'SPENDABLE',
                value: summary.spendable.formatCompact(),
                footnote: 'Income − savings',
              ),
            ),
            Gap.w8,
            Expanded(
              child: MiniStatCard(
                label: 'SPENT',
                value: summary.spent.formatCompact(),
                footnote: '$spentRatio% of spendable',
              ),
            ),
            Gap.w8,
            Expanded(
              child: MiniStatCard(
                label: 'REMAINING',
                value: summary.remaining.formatCompact(),
                tone: scheme.primary,
                footnote: '$remainingRatio% left',
              ),
            ),
          ],
        ),
        Gap.h16,

        Row(
          children: [
            for (final format in _ExportFormat.values) ...[
              if (format != _ExportFormat.values.first) Gap.w8,
              Expanded(
                child: PressableScale.onTap(
                  onTap: () => _runExport(context, ref, summary, format),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: AppTheme.card(scheme, radius: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          format.icon,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                        Gap.h4,
                        Text(
                          format.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),

        Gap.h28,
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Allocations', style: theme.textTheme.titleMedium),
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.insights),
              style: OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.trending_up_rounded, size: 16),
              label: const Text('View insights'),
            ),
          ],
        ),
        Gap.h12,
        AsyncView(
          value: categories,
          loading: const LinearProgressIndicator(),
          builder: (list) => Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            decoration: AppTheme.card(scheme),
            child: ListSection(
              children: [
                for (final category in list)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: IconBadge(
                      icon: categoryIconFor(category.key),
                      size: 34,
                      iconSize: 16,
                    ),
                    title: Text(category.name),
                    subtitle: Text(
                      '${category.spent.formatCompact()} of ${category.allocated.formatCompact()}',
                    ),
                    trailing: Text(
                      category.progress.isExceeded
                          ? '−${category.progress.overspend.formatCompact()}'
                          : category.progress.remaining.formatCompact(),
                      style: theme.textTheme.bodyMedium?.money.copyWith(
                        color: category.progress.isExceeded
                            ? theme.colorScheme.error
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Gap.h16,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            Gap.w4,
            Text(
              'All amounts are from your current budget settings.',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        Gap.h28,
        const SectionHeader(title: 'Transactions'),
        AsyncView(
          value: expenses,
          loading: const LinearProgressIndicator(),
          builder: (list) {
            if (list.isEmpty) {
              return const EmptyView(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions',
                message: 'Expenses you record will appear here.',
              );
            }
            return _TransactionGroups(list: list, budgetId: summary.budgetId);
          },
        ),
      ],
    );
  }
}

/// Transactions, grouped under a day heading. `list` already arrives sorted
/// most-recent-first (the repository's own order), so grouping only needs to
/// notice when the day changes, not re-sort.
class _TransactionGroups extends StatelessWidget {
  const _TransactionGroups({required this.list, required this.budgetId});

  final List<Expense> list;
  final String budgetId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = <String, List<Expense>>{};
    for (final expense in list) {
      groups.putIfAbsent(_dayLabel(expense.spentOn), () => []).add(expense);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.sm),
            child: Text(
              entry.key.toUpperCase(),
              style: theme.textTheme.labelMedium,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
            margin: const EdgeInsets.only(bottom: Gap.lg),
            decoration: AppTheme.card(scheme),
            child: ListSection(
              children: [
                for (final expense in entry.value)
                  _ExpenseTile(expense: expense, budgetId: budgetId),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('d MMMM').format(date);
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense, required this.budgetId});

  final Expense expense;
  final String budgetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.errorContainer,
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this expense?'),
            content: Text(
              '${expense.amount.format()} · ${expense.categoryName ?? "Uncategorised"}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) async {
        try {
          await ref.read(expenseRepositoryProvider).delete(expense.id);
          ref.refreshBudgetData();
          AppHaptics.warning();
        } on Object catch (error) {
          if (context.mounted) showFailure(context, error);
        }
      },
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          expense.note?.isNotEmpty ?? false
              ? expense.note!
              : expense.categoryName ?? 'Expense',
        ),
        subtitle: Text(
          [
            DateFormat('d MMM').format(expense.spentOn),
            if (expense.note?.isNotEmpty ?? false)
              expense.categoryName ?? 'Uncategorised',
            expense.paymentMethod.label,
          ].join(' · '),
        ),
        trailing: Text(
          expense.amount.format(),
          style: Theme.of(context).textTheme.titleSmall?.money,
        ),
        onTap: () => showExpenseSheet(context, ref, budgetId, editing: expense),
      ),
    );
  }
}

enum _ExportFormat {
  xlsx(
    'Excel workbook',
    Icons.table_chart_outlined,
    'Three sheets: summary, categories, transactions',
  ),
  csv('CSV', Icons.description_outlined, 'One file, opens anywhere'),
  pdf(
    'PDF report',
    Icons.picture_as_pdf_outlined,
    'Formatted for reading and printing',
  );

  const _ExportFormat(this.label, this.icon, this.description);

  final String label;
  final IconData icon;
  final String description;
}

Future<void> _runExport(
  BuildContext context,
  WidgetRef ref,
  BudgetSummary summary,
  _ExportFormat format,
) async {
  final messenger = ScaffoldMessenger.of(context)
    ..showSnackBar(SnackBar(content: Text('Preparing ${format.label}…')));

  try {
    final categories = await ref
        .read(budgetRepositoryProvider)
        .categoriesFor(summary.budgetId);
    final expenses = await ref
        .read(expenseRepositoryProvider)
        .forBudget(summary.budgetId);
    final data = MonthExport(
      summary: summary,
      categories: categories,
      expenses: expenses,
    );

    const service = ExportService();
    final file = switch (format) {
      _ExportFormat.xlsx => await service.writeXlsx(data),
      _ExportFormat.csv => await service.writeCsv(data),
      _ExportFormat.pdf => await service.writePdf(data),
    };

    messenger.hideCurrentSnackBar();
    await service.share(file, 'BudgetWise — ${summary.period.label}');
  } on Object catch (error) {
    messenger.hideCurrentSnackBar();
    if (context.mounted) showFailure(context, error);
  }
}
