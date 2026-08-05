import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:test/test.dart';

void main() {
  group('allocateByPercent', () {
    test('parts always sum to exactly the total', () {
      // The property that matters. Naive per-share rounding fails this.
      final cases = <(int, Map<String, double>)>[
        (100000, {'a': 33.33, 'b': 33.33, 'c': 33.34}),
        (
          100000,
          {
            'a': 14.28,
            'b': 14.28,
            'c': 14.29,
            'd': 14.29,
            'e': 14.28,
            'f': 14.29,
            'g': 14.29,
          },
        ),
        (123457, {'food': 30, 'transport': 20, 'bills': 25, 'misc': 25}),
        (1, {'a': 50, 'b': 50}),
        (7, {'a': 33.33, 'b': 33.33, 'c': 33.34}),
      ];

      for (final (totalMinor, percents) in cases) {
        final result = allocateByPercent(
          total: Money(totalMinor),
          percents: percents,
        );
        final summed = result.map((a) => a.amount).sum;
        expect(
          summed.minor,
          totalMinor,
          reason:
              'allocation of $totalMinor across $percents lost or invented paise',
        );
      }
    });

    test('distributes the remainder to the largest fractions first', () {
      // ₹10.00 split three ways: 333 + 333 + 334 paise, and the extra paisa
      // goes to the share with the largest discarded fraction.
      final result = allocateByPercent(
        total: const Money(1000),
        percents: {'a': 33.33, 'b': 33.33, 'c': 33.34},
      );
      expect(result.map((a) => a.amount.minor).toList(), [333, 333, 334]);
    });

    test('is deterministic — ties break by input order', () {
      final first = allocateByPercent(
        total: const Money(100),
        percents: {'a': 33.333, 'b': 33.333, 'c': 33.334},
      );
      final second = allocateByPercent(
        total: const Money(100),
        percents: {'a': 33.333, 'b': 33.333, 'c': 33.334},
      );
      expect(
        first.map((a) => a.amount.minor).toList(),
        second.map((a) => a.amount.minor).toList(),
      );
    });

    test('handles an empty map and a zero total', () {
      expect(
        allocateByPercent(
          total: const Money(1000),
          percents: <String, double>{},
        ),
        isEmpty,
      );

      final zero = allocateByPercent(
        total: const Money.zero(),
        percents: {'a': 50, 'b': 50},
      );
      expect(zero.map((a) => a.amount).sum, const Money.zero());
    });

    test('carries the percent through onto each allocation', () {
      final result = allocateByPercent(
        total: const Money(10000),
        percents: {'food': 60, 'misc': 40},
      );
      expect(result.first.key, 'food');
      expect(result.first.percent, 60);
      expect(result.first.amount.minor, 6000);
    });
  });

  group('spendableIncome', () {
    test('takes savings then investment off the top', () {
      final spendable = spendableIncome(
        income: Money.fromRupees(50000),
        savingsTarget: Money.fromRupees(10000),
        investmentTarget: Money.fromRupees(5000),
      );
      expect(spendable, Money.fromRupees(35000));
    });

    test('never goes negative', () {
      final spendable = spendableIncome(
        income: Money.fromRupees(1000),
        savingsTarget: Money.fromRupees(5000),
      );
      expect(spendable, const Money.zero());
    });
  });

  group('resolveSavingsTarget', () {
    test('resolves a percentage against income', () {
      final target = resolveSavingsTarget(
        income: Money.fromRupees(50000),
        mode: SavingsMode.percent,
        percent: 20,
      );
      expect(target, Money.fromRupees(10000));
    });

    test('passes a fixed amount through', () {
      final target = resolveSavingsTarget(
        income: Money.fromRupees(50000),
        mode: SavingsMode.fixed,
        fixedAmount: Money.fromRupees(7500),
      );
      expect(target, Money.fromRupees(7500));
    });

    test('caps at income — you cannot save more than you earned', () {
      final target = resolveSavingsTarget(
        income: Money.fromRupees(1000),
        mode: SavingsMode.fixed,
        fixedAmount: Money.fromRupees(5000),
      );
      expect(target, Money.fromRupees(1000));
    });
  });
}
