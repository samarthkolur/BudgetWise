import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';

class GoalRepository {
  GoalRepository(this._api);

  final ApiClient _api;

  Future<List<Goal>> all() async => guarded(() async {
    final rows = await _api.get('/v1/goals') as List;
    return rows.map((r) => Goal.fromJson(r as Map<String, dynamic>)).toList();
  });

  Future<Goal> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
  }) async => guarded(() async {
    final row =
        await _api.post('/v1/goals', {
              'title': title,
              'targetMinor': target.minor,
              'targetDate': targetDate?.toUtc().toIso8601String(),
              'monthlyContributionMinor': monthlyContribution?.minor,
              'icon': icon,
            })
            as Map<String, dynamic>;
    return Goal.fromJson(row);
  });

  /// Adds money to a goal.
  ///
  /// The running total is the server's job — it recomputes from the
  /// contributions rather than incrementing, so an edit or a delete cannot
  /// drift it and the client never has to keep two numbers in step.
  Future<void> contribute({
    required String goalId,
    required Money amount,
    String? budgetId,
  }) async => guarded(
    () => _api.post('/v1/goals/$goalId/contribute', {
      'amountMinor': amount.minor,
      'budgetId': budgetId,
    }),
  );

  Future<void> delete(String goalId) async =>
      guarded(() => _api.delete('/v1/goals/$goalId'));
}
