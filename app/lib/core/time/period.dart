import 'package:intl/intl.dart';

/// A budget month.
///
/// Every month-scoped row in the database is keyed by the first day of its
/// month, and the column carries a check constraint saying so. This type is the
/// only thing in the app allowed to build that value, which is what keeps
/// "which month is this expense in" from being answered three different ways in
/// three different files.
///
/// Month arithmetic is done in the user's **local** zone. An expense logged at
/// 11pm on the 31st belongs to that month as the user lived it, not as UTC saw
/// it; storage is UTC, interpretation is local.
class Period implements Comparable<Period> {
  const Period._(this.year, this.month);

  factory Period(int year, int month) {
    // Normalise out-of-range months so `Period(2026, 13)` is January 2027
    // rather than an assertion nobody sees until production.
    final zeroBased = month - 1;
    final y = year + (zeroBased / 12).floor();
    final m = zeroBased % 12;
    return Period._(y, m + 1);
  }

  factory Period.fromDate(DateTime date) => Period(date.year, date.month);

  factory Period.current({DateTime? now}) => Period.fromDate(now ?? DateTime.now());

  /// Parses the `date` column, which Postgres renders as `YYYY-MM-DD`.
  factory Period.parse(String value) {
    final parsed = DateTime.parse(value);
    return Period(parsed.year, parsed.month);
  }

  final int year;
  final int month;

  /// The value stored in a `period date` column.
  String get isoDate => DateFormat('yyyy-MM-dd').format(firstDay);

  DateTime get firstDay => DateTime(year, month);

  /// Last instant of the month, in local time.
  DateTime get lastDay => DateTime(year, month + 1, 0, 23, 59, 59, 999);

  int get totalDays => DateTime(year, month + 1, 0).day;

  Period get next => Period(year, month + 1);

  Period get previous => Period(year, month - 1);

  bool get isCurrent => this == Period.current();

  bool contains(DateTime date) => date.year == year && date.month == month;

  /// Days left including today, floored at zero. Inclusive because a user
  /// checking their budget at 9am today still gets to spend today — the safe
  /// daily figure must not divide by the days *after* this one.
  int daysRemaining({DateTime? now}) {
    final today = now ?? DateTime.now();
    if (!contains(today)) {
      // A past month has nothing remaining; a future month has all of it.
      return isBefore(Period.fromDate(today)) ? 0 : totalDays;
    }
    return totalDays - today.day + 1;
  }

  int daysElapsed({DateTime? now}) => totalDays - daysRemaining(now: now);

  bool isBefore(Period other) =>
      year < other.year || (year == other.year && month < other.month);

  bool isAfter(Period other) => other.isBefore(this);

  /// Whole months from this period to [other]; negative when [other] is older.
  int monthsUntil(Period other) =>
      (other.year - year) * 12 + (other.month - month);

  /// `August 2026`
  String get label => DateFormat('MMMM yyyy').format(firstDay);

  /// `Aug 2026`
  String get shortLabel => DateFormat('MMM yyyy').format(firstDay);

  @override
  int compareTo(Period other) =>
      year != other.year ? year.compareTo(other.year) : month.compareTo(other.month);

  @override
  bool operator ==(Object other) =>
      other is Period && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => 'Period($isoDate)';
}
