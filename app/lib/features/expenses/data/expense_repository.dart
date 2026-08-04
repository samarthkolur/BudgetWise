import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExpenseRepository {
  ExpenseRepository(this._db);

  final SupabaseClient _db;

  /// A month's expenses, newest first, with each category joined so the list
  /// can show a name and icon without a second query per row.
  Future<List<Expense>> forBudget(String budgetId) async {
    try {
      final rows = await _db
          .from('expenses')
          .select('*, budget_categories(display_name, icon)')
          .eq('budget_id', budgetId)
          .order('spent_on', ascending: false)
          .order('created_at', ascending: false);
      return rows.map(Expense.fromJson).toList();
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<List<Expense>> forCategory(String categoryId) async {
    try {
      final rows = await _db
          .from('expenses')
          .select('*, budget_categories(display_name, icon)')
          .eq('category_id', categoryId)
          .order('spent_on', ascending: false);
      return rows.map(Expense.fromJson).toList();
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<Expense> add({
    required String budgetId,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    try {
      final row = await _db
          .from('expenses')
          .insert({
            'user_id': _db.auth.currentUser!.id,
            'budget_id': budgetId,
            'category_id': categoryId,
            'amount_minor': amount.minor,
            // Date only. The time an expense was entered is not the day it
            // belongs to, and storing a timestamp here would put a purchase
            // logged at 00:30 on the wrong day in some timezones.
            'spent_on': _dateOnly(spentOn),
            'payment_method': paymentMethod.name,
            'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
          })
          .select('*, budget_categories(display_name, icon)')
          .single();
      return Expense.fromJson(row);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<Expense> update({
    required String id,
    required String categoryId,
    required Money amount,
    required DateTime spentOn,
    required PaymentMethod paymentMethod,
    String? note,
  }) async {
    try {
      final row = await _db
          .from('expenses')
          .update({
            'category_id': categoryId,
            'amount_minor': amount.minor,
            'spent_on': _dateOnly(spentOn),
            'payment_method': paymentMethod.name,
            'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
          })
          .eq('id', id)
          .select('*, budget_categories(display_name, icon)')
          .single();
      return Expense.fromJson(row);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<void> delete(String id) async {
    try {
      await _db.from('expenses').delete().eq('id', id);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Average monthly spend on essentials across completed months.
  ///
  /// The denominator of the emergency-fund ratio. Computed over whole months
  /// only — including the current, partial month would understate the average
  /// and make the cushion look larger than it is.
  Future<Money> averageMonthlyEssentials() async {
    try {
      final rows = await _db
          .from('v_category_spend')
          .select(
            'budget_id, category_key, spent_minor, monthly_budgets!inner(period)',
          )
          .inFilter('category_key', kEssentialCategoryKeys.toList());

      final currentPeriod = Period.current();
      final byPeriod = <String, int>{};

      for (final row in rows) {
        final budget = row['monthly_budgets'] as Map<String, dynamic>?;
        if (budget == null) continue;
        final period = Period.parse(budget['period'] as String);
        if (!period.isBefore(currentPeriod)) continue;
        byPeriod.update(
          period.isoDate,
          (value) => value + (row['spent_minor'] as num).toInt(),
          ifAbsent: () => (row['spent_minor'] as num).toInt(),
        );
      }

      if (byPeriod.isEmpty) return const Money.zero();
      final total = byPeriod.values.fold<int>(0, (a, b) => a + b);
      return Money(total ~/ byPeriod.length);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
