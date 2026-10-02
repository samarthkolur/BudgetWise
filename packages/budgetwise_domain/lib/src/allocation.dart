import 'package:budgetwise_domain/src/money.dart';

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
