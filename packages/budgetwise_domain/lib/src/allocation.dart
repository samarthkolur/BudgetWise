import 'package:budgetwise_domain/src/money.dart';

/// One share of a divided total.
class Allocation<T> {
  const Allocation({
    required this.key,
    required this.percent,
    required this.amount,
  });

  final T key;
  final double percent;
  final Money amount;

  Allocation<T> copyWithAmount(Money value) =>
      Allocation(key: key, percent: percent, amount: value);
}

/// Divides [total] among [percents] so the parts sum to **exactly** [total].
///
/// Uses the largest-remainder (Hamilton) method: floor every share, then hand
/// the leftover paise out one at a time to the shares with the largest
/// discarded fraction.
///
/// The naive alternative — rounding each share independently — is wrong in a
/// way that is easy to ship and hard to explain. Splitting ₹10,000 three ways
/// at 33.33 / 33.33 / 33.34 gives 3333.00 + 3333.00 + 3334.00 = ₹10,000.00 by
/// luck; splitting ₹1,000 seven ways does not, and the dashboard then shows a
/// few paise that belong to no category. Users read that as the app losing
/// their money, and they are not wrong to.
///
/// Ties in the remainder are broken by input order, so the result is
/// deterministic: the same bundle always produces the same allocation.
List<Allocation<T>> allocateByPercent<T>({
  required Money total,
  required Map<T, double> percents,
}) {
  if (percents.isEmpty) return const [];

  final keys = percents.keys.toList();

  // Work in a scaled integer space so the remainder comparison is exact and
  // never itself a floating-point judgement call.
  final scaledShares = <int>[
    for (final key in keys) (total.minor * (percents[key] ?? 0) * 1000).round(),
  ];

  final floors = <int>[for (final s in scaledShares) s ~/ 100000];
  final distributed = floors.fold<int>(0, (a, b) => a + b);
  var remainder = total.minor - distributed;

  // Order by discarded fraction, largest first; input order breaks ties.
  final order = List<int>.generate(keys.length, (i) => i)
    ..sort((a, b) {
      final fracA = scaledShares[a] % 100000;
      final fracB = scaledShares[b] % 100000;
      final byFraction = fracB.compareTo(fracA);
      return byFraction != 0 ? byFraction : a.compareTo(b);
    });

  final amounts = List<int>.from(floors);

  // `remainder` is negative only if the percentages sum above 100, which the
  // caller should have rejected. Handle it anyway rather than looping forever.
  var cursor = 0;
  while (remainder > 0 && order.isNotEmpty) {
    amounts[order[cursor % order.length]] += 1;
    remainder -= 1;
    cursor++;
  }
  while (remainder < 0 && order.isNotEmpty) {
    amounts[order[cursor % order.length]] -= 1;
    remainder += 1;
    cursor++;
  }

  return [
    for (var i = 0; i < keys.length; i++)
      Allocation(
        key: keys[i],
        percent: percents[keys[i]] ?? 0,
        amount: Money(amounts[i]),
      ),
  ];
}

/// Money left to spend after savings and investment are taken off the top.
///
/// This is the Earn → Save → Invest → Spend order expressed as arithmetic:
/// spending is what remains, never the starting point.
Money spendableIncome({
  required Money income,
  required Money savingsTarget,
  Money investmentTarget = const Money.zero(),
}) => (income - savingsTarget - investmentTarget).orZeroIfNegative;

/// Resolves a savings goal expressed either as a fixed amount or as a
/// percentage of income into a concrete amount, capped at income.
Money resolveSavingsTarget({
  required Money income,
  required SavingsMode mode,
  Money? fixedAmount,
  double? percent,
}) {
  final target = switch (mode) {
    SavingsMode.fixed => fixedAmount ?? const Money.zero(),
    SavingsMode.percent => income.percent(percent ?? 0),
  };
  return target > income ? income : target.orZeroIfNegative;
}

enum SavingsMode {
  fixed,
  percent;

  static SavingsMode fromDb(String value) => SavingsMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => SavingsMode.percent,
  );
}
