import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:budgetwise_server/src/db/mongo.dart';
import 'package:budgetwise_server/src/db/owned_collection.dart';
import 'package:budgetwise_server/src/domain_errors.dart';
import 'package:budgetwise_server/src/repositories/expense_repository.dart';
import 'package:mongo_dart/mongo_dart.dart';

/// The investing gate.
///
/// In Postgres this was `fn_investing_unlocked()` plus an INSERT policy on the
/// investments table that called it — so hiding the module in the UI and
/// refusing the write were one decision in one place, and a client that lied
/// about being unlocked was still refused by the database.
///
/// Mongo enforces nothing, so [recordInvestment] performs that check itself and
/// is the only path that writes an investment. The equivalence is deliberate:
/// if this check is ever bypassed, the gate is gone entirely.
///
/// The streak arithmetic itself is not reimplemented here — it comes from
/// `budgetwise_domain`, the same code the app uses to draw the progress dots.
class InvestingRepository {
  InvestingRepository(this._mongo, this.ownerId);

  final Mongo _mongo;
  final ObjectId ownerId;

  OwnedCollection get _budgets =>
      OwnedCollection(_mongo.collection(Col.budgets), ownerId);
  OwnedCollection get _savings =>
      OwnedCollection(_mongo.collection(Col.savings), ownerId);
  OwnedCollection get _investments =>
      OwnedCollection(_mongo.collection(Col.investments), ownerId);

  /// Builds the month-by-month savings record the streak is computed from.
  Future<List<SavingsMonth>> _history() async {
    final budgets = await _budgets.find(sort: {'period': -1});
    final months = <SavingsMonth>[];

    for (final budget in budgets) {
      final saved = await _savings.sum('amountMinor', {
        'budgetId': budget['_id'],
      });
      months.add(
        SavingsMonth(
          period: Period.parse(budget['period'] as String),
          target: Money((budget['savingsTargetMinor'] as num).toInt()),
          actual: Money(saved),
        ),
      );
    }
    return months;
  }

  /// Evaluates the gate and stamps the unlock the first time it is earned.
  ///
  /// `newlyUnlocked` is true only on the call that earned it, which is what the
  /// celebration keys off — otherwise it would fire on every launch thereafter.
  ///
  /// Unlocking is permanent: once `investingUnlockedAt` is set, the calculation
  /// is short-circuited. The PRD frames this as an achievement, and taking it
  /// back after a broken streak would make it a punishment nobody was warned
  /// about.
  Future<Map<String, dynamic>> claimUnlock() async {
    final users = _mongo.collection(Col.users);
    final user = await users.findOne(where.id(ownerId));
    final already = user?['investingUnlockedAt'] as DateTime?;

    final history = await _history();
    final totalSaved = Money(await _savings.sum('amountMinor'));
    final essentials = await ExpenseRepository(
      _mongo,
      ownerId,
    ).averageMonthlyEssentials();

    final status = evaluateInvestingUnlock(
      history: history,
      totalSaved: totalSaved,
      averageMonthlyEssentials: essentials,
      wasPreviouslyUnlocked: already != null,
    );

    final newlyUnlocked = already == null && status.isUnlocked;
    if (newlyUnlocked) {
      await users.updateOne(where.id(ownerId), {
        r'$set': {'investingUnlockedAt': DateTime.now().toUtc()},
      });
    }

    return {
      'isUnlocked': status.isUnlocked,
      'newlyUnlocked': newlyUnlocked,
      'streakMonths': status.streakMonths,
      'fundRatio': status.emergencyFundRatio,
    };
  }

  Future<bool> isUnlocked() async {
    final result = await claimUnlock();
    return result['isUnlocked'] as bool;
  }

  /// Records an investment — refused unless the gate is open.
  Future<Map<String, dynamic>> recordInvestment({
    required ObjectId budgetId,
    required Money amount,
    required String instrument,
    String? note,
  }) async {
    if (!amount.isPositive) {
      throw const ValidationException('Enter an amount greater than zero');
    }
    if (!await _budgets.owns(budgetId)) {
      throw const NotOwnedException('budget');
    }
    if (!await isUnlocked()) {
      throw const NotPermittedException(
        'Investing unlocks after six months of consistent saving, or once you '
        'have three months of essentials set aside.',
      );
    }

    return _investments.insert({
      'budgetId': budgetId,
      'amountMinor': amount.minor,
      'instrument': instrument,
      'investedOn': DateTime.now().toUtc(),
      'note': note,
    });
  }

  Future<List<Map<String, dynamic>>> forBudget(ObjectId budgetId) =>
      _investments.find(where: {'budgetId': budgetId});
}
