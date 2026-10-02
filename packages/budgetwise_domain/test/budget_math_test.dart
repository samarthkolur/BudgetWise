import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:test/test.dart';

void main() {
  group('safeDailySpend', () {
    test('divides what is left across the days that are left', () {
      final result = safeDailySpend(
        remaining: Money.fromRupees(3100),
        period: Period(2026, 8),
        now: DateTime(2026, 8, 21), // 11 days remaining, inclusive
      );
      expect(result.daysRemaining, 11);
      expect(result.perDay, Money.fromRupees(281));
    });

    test('floors to the rupee so the figure never over-promises', () {
      final result = safeDailySpend(
        remaining: Money.fromRupees(1000),
        period: Period(2026, 8),
        now: DateTime(2026, 8, 29), // 3 days
      );
      // 333.33 floors to 333, not 333.33 and not 334.
      expect(result.perDay, Money.fromRupees(333));
      expect(result.perDay.minor % 100, 0);
    });

    test('never divides by zero at the end of the month', () {
      final result = safeDailySpend(
        remaining: Money.fromRupees(500),
        period: Period(2026, 7),
        now: DateTime(2026, 8, 15), // period already over
      );
      expect(result.daysRemaining, 0);
      expect(result.perDay, const Money.zero());
    });

    test('an overspent month reports zero, not a negative daily allowance', () {
      final result = safeDailySpend(
        remaining: Money.fromRupees(-2000),
        period: Period(2026, 8),
        now: DateTime(2026, 8, 15),
      );
      expect(result.perDay, const Money.zero());
      expect(result.isExhausted, isTrue);
    });
  });
}
