import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoalRepository {
  GoalRepository(this._db);

  final SupabaseClient _db;

  Future<List<Goal>> all() async {
    try {
      final rows = await _db.from('goals').select().order('created_at');
      return rows.map(Goal.fromJson).toList();
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<Goal> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
  }) async {
    try {
      final row = await _db
          .from('goals')
          .insert({
            'user_id': _db.auth.currentUser!.id,
            'title': title.trim(),
            'target_minor': target.minor,
            'target_date': targetDate == null ? null : _dateOnly(targetDate),
            'monthly_contribution_minor': monthlyContribution?.minor,
            'icon': icon,
          })
          .select()
          .single();
      return Goal.fromJson(row);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Adds money to a goal.
  ///
  /// Only `goal_contributions` is written. `goals.saved_minor` is maintained by
  /// a database trigger that recomputes the sum rather than incrementing it, so
  /// an edit or a delete cannot drift the total — and the client never has to
  /// remember to keep two numbers in step.
  Future<void> contribute({
    required String goalId,
    required Money amount,
    String? budgetId,
  }) async {
    try {
      await _db.from('goal_contributions').insert({
        'user_id': _db.auth.currentUser!.id,
        'goal_id': goalId,
        'budget_id': budgetId,
        'amount_minor': amount.minor,
      });
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<void> delete(String goalId) async {
    try {
      await _db.from('goals').delete().eq('id', goalId);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<void> abandon(String goalId) async {
    try {
      await _db.from('goals').update({'status': 'abandoned'}).eq('id', goalId);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
