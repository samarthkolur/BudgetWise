import 'package:budgetwise_domain/budgetwise_domain.dart';

/// A month's plan.
class MonthlyBudget {
  const MonthlyBudget({
    required this.id,
    required this.period,
    required this.income,
    required this.savingsTarget,
    required this.savingsMode,
    this.savingsPercent,
    this.investmentTarget,
    this.savingsConfirmedAt,
    this.status = 'active',
    this.carriedFromPeriod,
  });

  factory MonthlyBudget.fromJson(Map<String, dynamic> json) => MonthlyBudget(
    id: json['id'] as String,
    period: Period.parse(json['period'] as String),
    income: Money((json['incomeMinor'] as num).toInt()),
    savingsTarget: Money((json['savingsTargetMinor'] as num).toInt()),
    savingsMode: SavingsMode.fromDb(
      json['savingsMode'] as String? ?? 'percent',
    ),
    savingsPercent: (json['savingsPercent'] as num?)?.toDouble(),
    investmentTarget: json['investmentTargetMinor'] == null
        ? null
        : Money((json['investmentTargetMinor'] as num).toInt()),
    savingsConfirmedAt: json['savingsConfirmedAt'] == null
        ? null
        : DateTime.parse(json['savingsConfirmedAt'] as String).toLocal(),
    status: json['status'] as String? ?? 'active',
    carriedFromPeriod: json['carriedFromPeriod'] == null
        ? null
        : Period.parse(json['carriedFromPeriod'] as String),
  );

  final String id;
  final Period period;
  final Money income;
  final Money savingsTarget;
  final SavingsMode savingsMode;
  final double? savingsPercent;
  final Money? investmentTarget;

  /// When the user confirmed they moved the money. Drives the PRD's reminder
  /// card, which stays visible until this is set and then becomes a success
  /// indicator. No bank integration — the point is the habit.
  final DateTime? savingsConfirmedAt;

  final String status;
  final Period? carriedFromPeriod;

  bool get isSavingsConfirmed => savingsConfirmedAt != null;

  Money get spendable => spendableIncome(
    income: income,
    savingsTarget: savingsTarget,
    investmentTarget: investmentTarget ?? const Money.zero(),
  );
}

/// The dashboard header, from `v_budget_summary`.
class BudgetSummary {
  const BudgetSummary({
    required this.budgetId,
    required this.period,
    required this.income,
    required this.savingsTarget,
    required this.savedActual,
    required this.spent,
    required this.spendable,
    required this.remaining,
    required this.investedActual,
    required this.expenseCount,
    required this.daysWithExpenses,
    required this.savingsConfirmedAt,
    this.investmentTarget,
  });

  factory BudgetSummary.fromJson(Map<String, dynamic> json) => BudgetSummary(
    budgetId: json['budgetId'] as String,
    period: Period.parse(json['period'] as String),
    income: Money((json['incomeMinor'] as num).toInt()),
    savingsTarget: Money((json['savingsTargetMinor'] as num).toInt()),
    savedActual: Money((json['savedMinor'] as num).toInt()),
    spent: Money((json['spentMinor'] as num).toInt()),
    spendable: Money((json['spendableMinor'] as num).toInt()),
    remaining: Money((json['remainingMinor'] as num).toInt()),
    investedActual: Money((json['investedMinor'] as num).toInt()),
    expenseCount: (json['expenseCount'] as num).toInt(),
    daysWithExpenses: (json['daysWithExpenses'] as num).toInt(),
    savingsConfirmedAt: json['savingsConfirmedAt'] == null
        ? null
        : DateTime.parse(json['savingsConfirmedAt'] as String).toLocal(),
    investmentTarget: json['investmentTargetMinor'] == null
        ? null
        : Money((json['investmentTargetMinor'] as num).toInt()),
  );

  final String budgetId;
  final Period period;
  final Money income;
  final Money savingsTarget;
  final Money savedActual;
  final Money spent;
  final Money spendable;
  final Money remaining;
  final Money investedActual;
  final Money? investmentTarget;
  final int expenseCount;
  final int daysWithExpenses;
  final DateTime? savingsConfirmedAt;

  bool get isSavingsConfirmed => savingsConfirmedAt != null;

  /// Savings still to be moved this month.
  Money get savingsOutstanding =>
      (savingsTarget - savedActual).orZeroIfNegative;

  SafeDailySpend safeDaily({DateTime? now}) =>
      safeDailySpend(remaining: remaining, period: period, now: now);
}

/// A recorded expense — a single debit, with no category. The history is
/// the categorisation: what it was and when, not which bucket it counted
/// against.
class Expense {
  const Expense({
    required this.id,
    required this.budgetId,
    required this.amount,
    required this.spentOn,
    required this.paymentMethod,
    this.note,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'] as String,
      budgetId: json['budgetId'] as String,
      amount: Money((json['amountMinor'] as num).toInt()),
      spentOn: DateTime.parse(json['spentOn'] as String),
      paymentMethod: PaymentMethod.fromDb(
        json['paymentMethod'] as String? ?? 'upi',
      ),
      note: json['note'] as String?,
    );
  }

  final String id;
  final String budgetId;
  final Money amount;
  final DateTime spentOn;
  final PaymentMethod paymentMethod;
  final String? note;
}

enum PaymentMethod {
  cash('Cash', '💵'),
  upi('UPI', '📱'),
  card('Card', '💳'),
  netbanking('Net banking', '🏦'),
  other('Other', '•');

  const PaymentMethod(this.label, this.icon);

  final String label;
  final String icon;

  static PaymentMethod fromDb(String value) => PaymentMethod.values.firstWhere(
    (m) => m.name == value,
    orElse: () => PaymentMethod.other,
  );
}

/// A long-term savings goal.
class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.target,
    required this.saved,
    required this.status,
    this.icon,
    this.targetDate,
    this.monthlyContribution,
  });

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    title: json['title'] as String,
    target: Money((json['targetMinor'] as num).toInt()),
    saved: Money((json['savedMinor'] as num).toInt()),
    status: json['status'] as String? ?? 'active',
    icon: json['icon'] as String?,
    targetDate: json['targetDate'] == null
        ? null
        : DateTime.parse(json['targetDate'] as String),
    monthlyContribution: json['monthlyContributionMinor'] == null
        ? null
        : Money((json['monthlyContributionMinor'] as num).toInt()),
  );

  final String id;
  final String title;
  final Money target;
  final Money saved;
  final String status;
  final String? icon;
  final DateTime? targetDate;
  final Money? monthlyContribution;

  Money get remaining => (target - saved).orZeroIfNegative;

  double get progress => saved.ratioOf(target).clamp(0.0, 1.0);

  bool get isAchieved => status == 'achieved' || saved >= target;

  /// Months to completion at the current contribution rate, or null when there
  /// is no rate to project from. Returning null rather than infinity keeps the
  /// UI honest: "no date yet" is the truth, and a made-up date is not.
  int? get monthsToTarget {
    final rate = monthlyContribution;
    if (rate == null || rate.isZero || isAchieved) return null;
    return (remaining.minor / rate.minor).ceil();
  }

  Period? get projectedCompletion {
    final months = monthsToTarget;
    if (months == null) return null;
    final now = Period.current();
    return Period(now.year, now.month + months);
  }

  /// What must be set aside each month to hit [targetDate] — the number the
  /// user actually needs, as opposed to the one they guessed.
  Money? get requiredMonthly {
    final date = targetDate;
    if (date == null || isAchieved) return null;
    final months = Period.current().monthsUntil(Period.fromDate(date));
    if (months <= 0) return remaining;
    return Money((remaining.minor / months).ceil());
  }
}
