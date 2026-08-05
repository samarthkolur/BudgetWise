import 'package:budgetwise/core/providers.dart';
import 'package:budgetwise/core/widgets/async_view.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the expense entry sheet.
///
/// A bottom sheet rather than a route: recording an expense is a two-second
/// interruption to whatever the user was looking at, and pushing a full screen
/// would make it feel like a bigger commitment than it is.
Future<void> showExpenseSheet(
  BuildContext context,
  WidgetRef ref,
  String budgetId, {
  String? preselectedCategoryId,
  Expense? editing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _ExpenseSheet(
        budgetId: budgetId,
        preselectedCategoryId: preselectedCategoryId,
        editing: editing,
      ),
    ),
  );
}

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet({
    required this.budgetId,
    this.preselectedCategoryId,
    this.editing,
  });

  final String budgetId;
  final String? preselectedCategoryId;
  final Expense? editing;

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _note;

  String? _categoryId;
  late DateTime _date;
  late PaymentMethod _method;
  bool _busy = false;
  String? _amountError;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _amount = TextEditingController(
      text: editing == null ? '' : editing.amount.asRupees.toStringAsFixed(2),
    );
    _note = TextEditingController(text: editing?.note ?? '');
    _categoryId = editing?.categoryId ?? widget.preselectedCategoryId;
    _date = editing?.spentOn ?? DateTime.now();
    _method = editing?.paymentMethod ?? PaymentMethod.upi;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = Money.tryParse(_amount.text);
    if (amount == null || !amount.isPositive) {
      setState(() => _amountError = 'Enter an amount greater than zero');
      return;
    }
    if (_categoryId == null) return;

    setState(() {
      _busy = true;
      _amountError = null;
    });

    try {
      final repository = ref.read(expenseRepositoryProvider);
      if (_isEditing) {
        await repository.update(
          id: widget.editing!.id,
          categoryId: _categoryId!,
          amount: amount,
          spentOn: _date,
          paymentMethod: _method,
          note: _note.text,
        );
      } else {
        await repository.add(
          budgetId: widget.budgetId,
          categoryId: _categoryId!,
          amount: amount,
          spentOn: _date,
          paymentMethod: _method,
          note: _note.text,
        );
      }
      ref.refreshBudgetData();
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Bounded to the month being budgeted: an expense outside it belongs to a
      // different plan, and silently accepting one would make that month's
      // totals wrong without explanation.
      firstDate: DateTime(_date.year, _date.month),
      lastDate: DateTime(_date.year, _date.month + 1, 0),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider(widget.budgetId));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _isEditing ? 'Edit expense' : 'Add expense',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 18),

          TextField(
            controller: _amount,
            autofocus: !_isEditing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
            ],
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              prefixText: '₹ ',
              hintText: '0',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 18),

          Text('Category', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          AsyncView(
            value: categories,
            loading: const SizedBox(
              height: 44,
              child: Center(child: LinearProgressIndicator()),
            ),
            builder: (list) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in list)
                  ChoiceChip(
                    label: Text('${category.icon} ${category.name}'),
                    selected: _categoryId == category.id,
                    onSelected: (_) =>
                        setState(() => _categoryId = category.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _isToday(_date) ? 'Today' : '${_date.day}/${_date.month}',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<PaymentMethod>(
                  initialValue: _method,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  items: [
                    for (final method in PaymentMethod.values)
                      DropdownMenuItem(
                        value: method,
                        child: Text('${method.icon} ${method.label}'),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _method = value ?? _method),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Note (optional)'),
          ),
          const SizedBox(height: 20),

          FilledButton(
            onPressed: _busy || _categoryId == null ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(_isEditing ? 'Save changes' : 'Add expense'),
          ),
        ],
      ),
    );
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}
