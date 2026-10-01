import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/budget/domain/models.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Two implementations: [ApiGoalRepository] talks to the server,
/// [LocalGoalRepository] talks to the on-device database. Neither the
/// providers nor the screens that consume this interface know or care which
/// one they got.
abstract class GoalRepository {
  Future<List<Goal>> all();
  Future<Goal> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
  });
  Future<void> contribute({
    required String goalId,
    required Money amount,
    String? budgetId,
  });
  Future<void> delete(String goalId);
}

class ApiGoalRepository implements GoalRepository {
  ApiGoalRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Goal>> all() async => guarded(() async {
    final rows = await _api.get('/v1/goals') as List;
    return rows.map((r) => Goal.fromJson(r as Map<String, dynamic>)).toList();
  });

  @override
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
  @override
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

  @override
  Future<void> delete(String goalId) async =>
      guarded(() => _api.delete('/v1/goals/$goalId'));
}

/// Talks to the on-device database, used whenever no one is signed in.
///
/// Contributions increment `saved_minor` directly rather than being recorded
/// as their own rows — there is no local-only need for a contribution
/// history yet, and adding one now would be schema surface a future sync has
/// to reconcile for no present benefit.
class LocalGoalRepository implements GoalRepository {
  LocalGoalRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  @override
  Future<List<Goal>> all() async {
    final db = (await _dbFuture).db;
    final rows = await db.query('goals', orderBy: 'rowid');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Goal> create({
    required String title,
    required Money target,
    DateTime? targetDate,
    Money? monthlyContribution,
    String? icon,
  }) async {
    final db = (await _dbFuture).db;
    final goal = Goal(
      id: const Uuid().v4(),
      title: title,
      target: target,
      saved: const Money.zero(),
      status: 'active',
      icon: icon,
      targetDate: targetDate,
      monthlyContribution: monthlyContribution,
    );
    await db.insert('goals', _toRow(goal));
    return goal;
  }

  @override
  Future<void> contribute({
    required String goalId,
    required Money amount,
    String? budgetId,
  }) async {
    final db = (await _dbFuture).db;
    final rows = await db.query(
      'goals',
      where: 'id = ?',
      whereArgs: [goalId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final goal = _fromRow(rows.first);
    final saved = goal.saved + amount;
    await db.update(
      'goals',
      {
        'saved_minor': saved.minor,
        'status': saved >= goal.target ? 'achieved' : goal.status,
      },
      where: 'id = ?',
      whereArgs: [goalId],
    );
  }

  @override
  Future<void> delete(String goalId) async {
    final db = (await _dbFuture).db;
    await db.delete('goals', where: 'id = ?', whereArgs: [goalId]);
  }

  static Goal _fromRow(Map<String, Object?> row) => Goal(
    id: row['id']! as String,
    title: row['title']! as String,
    target: Money(row['target_minor']! as int),
    saved: Money(row['saved_minor']! as int),
    status: row['status']! as String,
    icon: row['icon'] as String?,
    targetDate: row['target_date'] == null
        ? null
        : DateTime.parse(row['target_date']! as String),
    monthlyContribution: row['monthly_contribution_minor'] == null
        ? null
        : Money(row['monthly_contribution_minor']! as int),
  );

  static Map<String, Object?> _toRow(Goal goal) => {
    'id': goal.id,
    'title': goal.title,
    'target_minor': goal.target.minor,
    'saved_minor': goal.saved.minor,
    'status': goal.status,
    'icon': goal.icon,
    'target_date': goal.targetDate?.toIso8601String(),
    'monthly_contribution_minor': goal.monthlyContribution?.minor,
  };
}
