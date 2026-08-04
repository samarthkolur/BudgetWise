import 'package:budgetwise/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money construction', () {
    test('stores paise exactly', () {
      expect(const Money(12345).minor, 12345);
      expect(Money.fromRupees(123.45).minor, 12345);
      expect(Money.fromRupees(1).minor, 100);
    });

    test('rounds fractional paise at the boundary, not through it', () {
      // 0.005 rupees is half a paisa; it must not silently truncate to zero.
      expect(Money.fromRupees(0.005).minor, 1);
      expect(Money.fromRupees(0.004).minor, 0);
    });

    test('survives the classic float case', () {
      // 0.1 + 0.2 != 0.3 in binary floating point. In paise it is just 30.
      final sum = Money.fromRupees(0.1) + Money.fromRupees(0.2);
      expect(sum, Money.fromRupees(0.3));
      expect(sum.minor, 30);
    });
  });

  group('Money.tryParse', () {
    test('accepts formatted input', () {
      expect(Money.tryParse('1,250')?.minor, 125000);
      expect(Money.tryParse('₹1250.50')?.minor, 125050);
      expect(Money.tryParse(' 42 ')?.minor, 4200);
    });

    test('rejects what is not an amount', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('-100'), isNull);
      expect(Money.tryParse('₹'), isNull);
    });
  });

  group('Money arithmetic', () {
    test('adds, subtracts and scales', () {
      expect((const Money(500) + const Money(250)).minor, 750);
      expect((const Money(500) - const Money(250)).minor, 250);
      expect((const Money(500) * 3).minor, 1500);
      expect((const Money(500) ~/ 3).minor, 166);
    });

    test('orZeroIfNegative clamps but abs does not', () {
      expect(const Money(-500).orZeroIfNegative, const Money.zero());
      expect(const Money(-500).abs.minor, 500);
    });

    test('ratioOf returns zero against a zero total', () {
      // An unallocated category must not render as 100% spent.
      expect(const Money(500).ratioOf(const Money.zero()), 0);
      expect(const Money(500).ratioOf(const Money(1000)), 0.5);
    });

    test('percent floors rather than rounds', () {
      // 33.33% of 1000.00 is 333.30; flooring leaves the remainder for the
      // allocator to distribute deliberately.
      expect(const Money(100000).percent(33.33).minor, 33330);
      expect(const Money(1000).percent(0.05).minor, 0);
    });
  });

  group('Money formatting', () {
    test('uses Indian digit grouping', () {
      expect(Money.fromRupees(125000).format(), '₹1,25,000.00');
      expect(Money.fromRupees(125000).formatCompact(), '₹1,25,000');
    });
  });

  group('Money comparison', () {
    test('orders and compares by value', () {
      expect(const Money(500) > const Money(250), isTrue);
      expect(const Money(500) >= const Money(500), isTrue);
      expect(const Money(250) < const Money(500), isTrue);
      expect(const Money(500) == const Money(500), isTrue);

      final sorted = [const Money(300), const Money(100), const Money(200)]..sort();
      expect(sorted.map((m) => m.minor), [100, 200, 300]);
    });

    test('sums an iterable', () {
      expect([const Money(100), const Money(250)].sum.minor, 350);
      expect(<Money>[].sum, const Money.zero());
    });
  });
}
