import 'package:budgetwise_domain/budgetwise_domain.dart';

/// The nine categories a new month starts with.
///
/// Held as data rather than an enum so a user-defined category (`custom:<slug>`)
/// is representable without a schema change, and so the default split can be
/// tuned without touching any type. The percentages are a starting point the
/// user immediately adjusts, not advice — they sum to 100.
class CategoryTemplate {
  const CategoryTemplate({
    required this.key,
    required this.name,
    required this.icon,
    required this.defaultPercent,
    this.isEssential = false,
  });

  final String key;
  final String name;
  final String icon;
  final double defaultPercent;

  /// Counted toward the emergency-fund calculation. These are the categories a
  /// person cannot simply stop paying, which is what makes three months of them
  /// a meaningful cushion.
  final bool isEssential;
}

const kDefaultCategories = <CategoryTemplate>[
  CategoryTemplate(
    key: 'food',
    name: 'Food',
    icon: '🍽️',
    defaultPercent: 30,
    isEssential: true,
  ),
  CategoryTemplate(
    key: 'transport',
    name: 'Transport',
    icon: '🚌',
    defaultPercent: 12,
    isEssential: true,
  ),
  CategoryTemplate(
    key: 'bills',
    name: 'Bills',
    icon: '🧾',
    defaultPercent: 20,
    isEssential: true,
  ),
  CategoryTemplate(
    key: 'healthcare',
    name: 'Healthcare',
    icon: '💊',
    defaultPercent: 5,
    isEssential: true,
  ),
  CategoryTemplate(
    key: 'shopping',
    name: 'Shopping',
    icon: '🛍️',
    defaultPercent: 10,
  ),
  CategoryTemplate(
    key: 'entertainment',
    name: 'Entertainment',
    icon: '🎬',
    defaultPercent: 8,
  ),
  CategoryTemplate(
    key: 'subscriptions',
    name: 'Subscriptions',
    icon: '📺',
    defaultPercent: 5,
  ),
  CategoryTemplate(
    key: 'education',
    name: 'Education',
    icon: '📚',
    defaultPercent: 5,
  ),
  CategoryTemplate(
    key: 'misc',
    name: 'Miscellaneous',
    icon: '✨',
    defaultPercent: 5,
  ),
];

const kEssentialCategoryKeys = {'food', 'transport', 'bills', 'healthcare'};

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

/// One category's allocation and what has been spent against it.
///
/// Built from `v_category_spend`, so the allocated and spent figures come from
/// the same query and cannot disagree.
class CategorySpend {
  const CategorySpend({
    required this.id,
    required this.budgetId,
    required this.key,
    required this.name,
    required this.icon,
    required this.allocated,
    required this.spent,
    required this.allocatedPercent,
    required this.expenseCount,
    required this.sortOrder,
  });

  factory CategorySpend.fromJson(Map<String, dynamic> json) => CategorySpend(
    id: json['categoryId'] as String,
    budgetId: json['budgetId'] as String,
    key: json['categoryKey'] as String,
    name: json['displayName'] as String,
    icon: json['icon'] as String? ?? '•',
    allocated: Money((json['allocatedMinor'] as num).toInt()),
    spent: Money((json['spentMinor'] as num).toInt()),
    allocatedPercent: (json['allocatedPercent'] as num?)?.toDouble() ?? 0,
    expenseCount: (json['expenseCount'] as num?)?.toInt() ?? 0,
    sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String budgetId;
  final String key;
  final String name;
  final String icon;
  final Money allocated;
  final Money spent;
  final double allocatedPercent;
  final int expenseCount;
  final int sortOrder;

  CategoryProgress get progress =>
      CategoryProgress(allocated: allocated, spent: spent);

  bool get isEssential => kEssentialCategoryKeys.contains(key);
}

/// The dashboard header, from `v_budget_summary`.
class BudgetSummary {
  const BudgetSummary({
    required this.budgetId,
    required this.period,
    required this.income,
    required this.savingsTarget,
    required this.savedActual,
    required this.allocated,
    required this.spent,
    required this.spendable,
    required this.remaining,
    required this.investedActual,
    required this.categoryCount,
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
    allocated: Money((json['allocatedMinor'] as num).toInt()),
    spent: Money((json['spentMinor'] as num).toInt()),
    spendable: Money((json['spendableMinor'] as num).toInt()),
    remaining: Money((json['remainingMinor'] as num).toInt()),
    investedActual: Money((json['investedMinor'] as num).toInt()),
    categoryCount: (json['categoryCount'] as num).toInt(),
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
  final Money allocated;
  final Money spent;
  final Money spendable;
  final Money remaining;
  final Money investedActual;
  final Money? investmentTarget;
  final int categoryCount;
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

/// A recorded expense.
class Expense {
  const Expense({
    required this.id,
    required this.budgetId,
    required this.categoryId,
    required this.amount,
    required this.spentOn,
    required this.paymentMethod,
    this.note,
    this.categoryName,
    this.categoryIcon,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as Map<String, dynamic>?;
    return Expense(
      id: json['id'] as String,
      budgetId: json['budgetId'] as String,
      categoryId: json['categoryId'] as String,
      amount: Money((json['amountMinor'] as num).toInt()),
      spentOn: DateTime.parse(json['spentOn'] as String),
      paymentMethod: PaymentMethod.fromDb(
        json['paymentMethod'] as String? ?? 'upi',
      ),
      note: json['note'] as String?,
      categoryName: category?['displayName'] as String?,
      categoryIcon: category?['icon'] as String?,
    );
  }

  final String id;
  final String budgetId;
  final String categoryId;
  final Money amount;
  final DateTime spentOn;
  final PaymentMethod paymentMethod;
  final String? note;

  /// Populated when the row was fetched with its category joined.
  final String? categoryName;
  final String? categoryIcon;
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
