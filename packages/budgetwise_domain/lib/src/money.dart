import 'package:intl/intl.dart';
import 'package:meta/meta.dart';

/// An exact monetary amount, stored in **minor units** (paise).
///
/// Money never touches [double]. A budget is a sum of parts that must equal a
/// whole, and binary floating point cannot represent 0.1 — so `income * 0.15`
/// produces amounts that are individually plausible and collectively wrong.
/// Every amount in BudgetWise is an integer count of paise from the database
/// column through to the widget, and is converted to a display string exactly
/// once, at the edge.

@immutable
class Money implements Comparable<Money> {
  const Money(this.minor);

  const Money.zero() : minor = 0;

  /// Builds from a whole-rupee amount. Exact for [int]; for [double] inputs
  /// (a text field, a slider) the value is rounded to the nearest paisa, which
  /// is the only place a fractional value is allowed to exist.
  factory Money.fromRupees(num rupees) => Money((rupees * 100).round());

  /// Parses user input: "1,250", "1250.50", "₹1250". Returns null when the
  /// text is not a non-negative amount, so callers can show a field error
  /// rather than silently reading zero.
  static Money? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite || value < 0) {
      return null;
    }
    return Money.fromRupees(value);
  }

  /// Paise. The single source of truth; everything else is derived.
  final int minor;

  double get asRupees => minor / 100;

  bool get isZero => minor == 0;

  bool get isNegative => minor < 0;

  bool get isPositive => minor > 0;

  Money operator +(Money other) => Money(minor + other.minor);

  Money operator -(Money other) => Money(minor - other.minor);

  /// Scales by an integer count — three months of rent, five equal shares.
  Money operator *(int factor) => Money(minor * factor);

  /// Integer division, truncated toward zero. Used for per-day figures, where
  /// the remainder is deliberately discarded rather than shown as a fraction
  /// of a paisa.
  Money operator ~/(int divisor) => Money(minor ~/ divisor);

  Money operator -() => Money(-minor);

  bool operator <(Money other) => minor < other.minor;

  bool operator <=(Money other) => minor <= other.minor;

  bool operator >(Money other) => minor > other.minor;

  bool operator >=(Money other) => minor >= other.minor;

  /// Clamps at zero. "Remaining" is never negative in the UI — overspend is
  /// reported as its own quantity so the two are never confused.
  Money get orZeroIfNegative => isNegative ? const Money.zero() : this;

  Money get abs => isNegative ? Money(-minor) : this;

  /// This amount as a fraction of [total], in the range 0.0–n. Returns 0 when
  /// [total] is zero, because "spent 100% of a zero budget" is a claim about
  /// nothing and would render as a full red bar on an unallocated category.
  double ratioOf(Money total) => total.isZero ? 0 : minor / total.minor;

  /// A percentage of this amount, floored to the paisa. Flooring rather than
  /// rounding is what lets the largest-remainder allocator hand the shortfall out
  /// deliberately instead of letting each share round up independently.
  Money percent(double pct) => Money((minor * pct / 100).floor());

  /// `₹1,25,000.50` — Indian digit grouping, two decimals.
  String format({String locale = 'en_IN', String symbol = '₹'}) =>
      NumberFormat.currency(
        locale: locale,
        symbol: symbol,
        decimalDigits: 2,
      ).format(asRupees);

  /// `₹1,25,000` — no decimals. Used where the paise are noise: summary tiles,
  /// category cards, the safe-daily-spend figure.
  String formatCompact({String locale = 'en_IN', String symbol = '₹'}) =>
      NumberFormat.currency(
        locale: locale,
        symbol: symbol,
        decimalDigits: 0,
      ).format(asRupees);

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  @override
  String toString() => 'Money(${format()})';
}

extension MoneyIterable on Iterable<Money> {
  Money get sum => fold(const Money.zero(), (a, b) => a + b);
}
