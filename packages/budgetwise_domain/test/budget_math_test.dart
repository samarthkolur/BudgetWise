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

  group('CategoryProgress', () {
    test('reports remaining and status while under budget', () {
      const progress = CategoryProgress(
        allocated: Money(500000),
        spent: Money(200000),
      );
      expect(progress.remaining.minor, 300000);
      expect(progress.overspend, const Money.zero());
      expect(progress.status, CategoryStatus.healthy);
      expect(progress.isExceeded, isFalse);
    });

    test('warns before the limit, not at it', () {
      const atSeventyFour = CategoryProgress(
        allocated: Money(10000),
        spent: Money(7400),
      );
      const atSeventyFive = CategoryProgress(
        allocated: Money(10000),
        spent: Money(7500),
      );
      expect(atSeventyFour.status, CategoryStatus.healthy);
      expect(atSeventyFive.status, CategoryStatus.warning);
    });

    test('states overspend as its own quantity, not a negative remainder', () {
      const progress = CategoryProgress(
        allocated: Money(500000),
        spent: Money(620000),
      );
      expect(progress.remaining, const Money.zero());
      expect(progress.overspend.minor, 120000);
      expect(progress.status, CategoryStatus.exceeded);
    });

    test('clamps the progress bar but not the underlying ratio', () {
      const progress = CategoryProgress(
        allocated: Money(1000),
        spent: Money(1400),
      );
      expect(progress.ratio, closeTo(1.4, 0.001));
      expect(progress.displayRatio, 1.0);
    });

    test('an unallocated category is not 100% spent', () {
      const progress = CategoryProgress(
        allocated: Money.zero(),
        spent: Money.zero(),
      );
      expect(progress.ratio, 0);
      expect(progress.status, CategoryStatus.healthy);
    });
  });

  group('suggestReallocation', () {
    final categories = {
      'food': const CategoryProgress(
        allocated: Money(500000),
        spent: Money(620000),
      ),
      'transport': const CategoryProgress(
        allocated: Money(300000),
        spent: Money(100000),
      ),
      'shopping': const CategoryProgress(
        allocated: Money(200000),
        spent: Money(150000),
      ),
    };

    test('draws from the largest surplus', () {
      final suggestion = suggestReallocation(
        overspend: const Money(120000),
        categories: categories,
        excludingKey: 'food',
      );
      expect(suggestion, isNotNull);
      expect(suggestion!.fromKey, 'transport');
      expect(suggestion.amount.minor, 120000);
    });

    test('takes only what the source actually has', () {
      final suggestion = suggestReallocation(
        overspend: const Money(900000),
        categories: categories,
        excludingKey: 'food',
      );
      expect(suggestion!.amount.minor, 200000); // transport's whole surplus
    });

    test('says nothing rather than inventing a source', () {
      final exhausted = {
        'food': const CategoryProgress(
          allocated: Money(1000),
          spent: Money(2000),
        ),
        'bills': const CategoryProgress(
          allocated: Money(1000),
          spent: Money(1000),
        ),
      };
      expect(
        suggestReallocation(
          overspend: const Money(1000),
          categories: exhausted,
          excludingKey: 'food',
        ),
        isNull,
      );
    });

    test('returns nothing when there is no overspend to cover', () {
      expect(
        suggestReallocation(
          overspend: const Money.zero(),
          categories: categories,
          excludingKey: 'food',
        ),
        isNull,
      );
    });
  });
}
