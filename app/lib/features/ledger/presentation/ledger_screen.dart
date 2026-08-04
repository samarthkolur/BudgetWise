import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise/features/expenses/presentation/expense_sheet.dart';
import 'package:budgetwise/features/export/data/export_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ledger'),
        actions: [
          if (summary.value != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export',
              onPressed: () => _showExportSheet(context, ref, summary.value!),
            ),
        ],
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
                    icon: '📭',
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
    final current = Period.current();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () =>
                ref.read(selectedPeriodProvider.notifier).previous(),
          ),
          Column(
            children: [
              Text(period.label, style: theme.textTheme.titleMedium),
              if (period == current)
                Text('This month', style: theme.textTheme.bodySmall),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
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

class _LedgerBody extends ConsumerWidget {
  const _LedgerBody({required this.summary});

  final BudgetSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider(summary.budgetId));
    final expenses = ref.watch(expensesProvider(summary.budgetId));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _Row(label: 'Income', value: summary.income.format()),
                _Row(
                  label: 'Savings target',
                  value: summary.savingsTarget.format(),
                  color: theme.colorScheme.primary,
                ),
                _Row(
                  label: 'Savings actual',
                  value: summary.savedActual.format(),
                ),
                const Divider(height: 22),
                _Row(label: 'Spendable', value: summary.spendable.format()),
                _Row(label: 'Spent', value: summary.spent.format()),
                _Row(
                  label: 'Remaining',
                  value: summary.remaining.format(),
                  emphasise: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Allocations', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        AsyncView(
          value: categories,
          loading: const LinearProgressIndicator(),
          builder: (list) => Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (final category in list)
                    ListTile(
                      dense: true,
                      leading: Text(
                        category.icon,
                        style: const TextStyle(fontSize: 18),
                      ),
                      title: Text(category.name),
                      subtitle: Text(
                        '${category.spent.formatCompact()} of ${category.allocated.formatCompact()}',
                      ),
                      trailing: Text(
                        category.progress.isExceeded
                            ? '−${category.progress.overspend.formatCompact()}'
                            : category.progress.remaining.formatCompact(),
                        style: theme.textTheme.bodyMedium?.copyWith(
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
        ),
        const SizedBox(height: 18),
        Text('Transactions', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        AsyncView(
          value: expenses,
          loading: const LinearProgressIndicator(),
          builder: (list) {
            if (list.isEmpty) {
              return const EmptyView(
                icon: '🧾',
                title: 'No transactions',
                message: 'Expenses you record will appear here.',
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final expense in list)
                    _ExpenseTile(expense: expense, budgetId: summary.budgetId),
                ],
              ),
            );
          },
        ),
      ],
    );
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
        } on Object catch (error) {
          if (context.mounted) showFailure(context, error);
        }
      },
      child: ListTile(
        leading: Text(
          expense.categoryIcon ?? '•',
          style: const TextStyle(fontSize: 18),
        ),
        title: Text(
          expense.note?.isNotEmpty ?? false
              ? expense.note!
              : expense.categoryName ?? 'Expense',
        ),
        subtitle: Text(
          '${DateFormat('d MMM').format(expense.spentOn)} · ${expense.paymentMethod.label}',
        ),
        trailing: Text(
          expense.amount.format(),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: () => showExpenseSheet(context, ref, budgetId, editing: expense),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasise = false,
    this.color,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style:
                (emphasise
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyLarge)
                    ?.copyWith(
                      fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showExportSheet(
  BuildContext context,
  WidgetRef ref,
  BudgetSummary summary,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(
            'Export ${summary.period.label}',
            style: Theme.of(sheetContext).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final format in _ExportFormat.values)
            ListTile(
              leading: Text(format.icon, style: const TextStyle(fontSize: 22)),
              title: Text(format.label),
              subtitle: Text(format.description),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _runExport(context, ref, summary, format);
              },
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

enum _ExportFormat {
  xlsx(
    'Excel workbook',
    '📊',
    'Three sheets: summary, categories, transactions',
  ),
  csv('CSV', '📄', 'One file, opens anywhere'),
  pdf('PDF report', '📕', 'Formatted for reading and printing');

  const _ExportFormat(this.label, this.icon, this.description);

  final String label;
  final String icon;
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
