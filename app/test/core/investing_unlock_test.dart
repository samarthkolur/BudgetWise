import 'package:budgetwise/core/budget/investing_unlock.dart';
import 'package:budgetwise/core/money/money.dart';
import 'package:budgetwise/core/time/period.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds [count] successful months ending with the month before [endingBefore].
List<SavingsMonth> _successfulMonths(int count, {required Period endingBefore}) {
  final months = <SavingsMonth>[];
  var cursor = endingBefore.previous;
  for (var i = 0; i < count; i++) {
    months.add(
      SavingsMonth(
        period: cursor,
        target: Money.fromRupees(5000),
        actual: Money.fromRupees(5000),
      ),
    );
    cursor = cursor.previous;
  }
  return months;
}

void main() {
  final august = Period(2026, 8);

  group('savingsStreak', () {
    test('counts consecutive successful completed months', () {
      final history = _successfulMonths(4, endingBefore: august);
      expect(savingsStreak(history, asOf: august), 4);
    });

    test('excludes the current month, which is still in progress', () {
      final history = [
        ..._successfulMonths(3, endingBefore: august),
        SavingsMonth(
          period: august,
          target: Money.fromRupees(5000),
          actual: Money.fromRupees(5000),
        ),
      ];
      // The in-progress month must not inflate the streak to 4.
      expect(savingsStreak(history, asOf: august), 3);
    });

    test('breaks on a missed month rather than counting around it', () {
      final history = [
        ..._successfulMonths(2, endingBefore: august),
        SavingsMonth(
          period: Period(2026, 5),
          target: Money.fromRupees(5000),
          actual: Money.fromRupees(1000),
        ),
        ..._successfulMonths(3, endingBefore: Period(2026, 5)),
      ];
      expect(savingsStreak(history, asOf: august), 2);
    });

    test('breaks on a gap in the history', () {
      final history = [
        SavingsMonth(
          period: Period(2026, 7),
          target: Money.fromRupees(5000),
          actual: Money.fromRupees(5000),
        ),
        // June missing entirely.
        SavingsMonth(
          period: Period(2026, 5),
          target: Money.fromRupees(5000),
          actual: Money.fromRupees(5000),
        ),
      ];
      expect(savingsStreak(history, asOf: august), 1);
    });

    test('a zero target does not count as keeping a commitment', () {
      final history = [
        SavingsMonth(
          period: Period(2026, 7),
          target: const Money.zero(),
          actual: const Money.zero(),
        ),
      ];
      expect(savingsStreak(history, asOf: august), 0);
    });

    test('empty history is a zero streak, not an error', () {
      expect(savingsStreak([], asOf: august), 0);
    });
  });

  group('emergencyFundRatio', () {
    test('measures savings against three months of essentials', () {
      final ratio = emergencyFundRatio(
        totalSaved: Money.fromRupees(60000),
        averageMonthlyEssentials: Money.fromRupees(20000),
      );
      expect(ratio, closeTo(1.0, 0.001));
    });

    test('an unknown denominator is not a satisfied cushion', () {
      final ratio = emergencyFundRatio(
        totalSaved: Money.fromRupees(100000),
        averageMonthlyEssentials: const Money.zero(),
      );
      expect(ratio, 0);
    });
  });

  group('evaluateInvestingUnlock', () {
    test('a 7-month history unlocks; a 3-month history does not', () {
      final seven = evaluateInvestingUnlock(
        history: _successfulMonths(7, endingBefore: august),
        totalSaved: Money.fromRupees(35000),
        averageMonthlyEssentials: Money.fromRupees(20000),
        asOf: august,
      );
      expect(seven.isUnlocked, isTrue);
      expect(seven.unlockedBy, UnlockRoute.savingsStreak);

      final three = evaluateInvestingUnlock(
        history: _successfulMonths(3, endingBefore: august),
        totalSaved: Money.fromRupees(15000),
        averageMonthlyEssentials: Money.fromRupees(20000),
        asOf: august,
      );
      expect(three.isUnlocked, isFalse);
      expect(three.monthsRemaining, 3);
    });

    test('a sufficient emergency fund unlocks without the streak', () {
      final status = evaluateInvestingUnlock(
        history: _successfulMonths(1, endingBefore: august),
        totalSaved: Money.fromRupees(90000),
        averageMonthlyEssentials: Money.fromRupees(20000),
        asOf: august,
      );
      expect(status.isUnlocked, isTrue);
      expect(status.unlockedBy, UnlockRoute.emergencyFund);
    });

    test('unlocking is permanent — a broken streak does not re-lock', () {
      final status = evaluateInvestingUnlock(
        history: const [],
        totalSaved: const Money.zero(),
        averageMonthlyEssentials: Money.fromRupees(20000),
        wasPreviouslyUnlocked: true,
        asOf: august,
      );
      expect(status.isUnlocked, isTrue);
      expect(status.streakMonths, 0);
    });

    test('progress tracks whichever route is closer', () {
      final status = evaluateInvestingUnlock(
        history: _successfulMonths(3, endingBefore: august),
        totalSaved: Money.fromRupees(50000), // 0.83 of a 60k cushion
        averageMonthlyEssentials: Money.fromRupees(20000),
        asOf: august,
      );
      // Fund route (0.83) is ahead of the streak route (0.5).
      expect(status.progress, closeTo(0.833, 0.01));
    });
  });
}
