import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:test/test.dart';

void main() {
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
