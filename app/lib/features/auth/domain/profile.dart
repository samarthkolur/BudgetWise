import 'package:budgetwise/core/money/money.dart';

/// The user's own row in `profiles`, created by a database trigger on sign-up.
class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.avatarUrl,
    this.currency = 'INR',
    this.locale = 'en_IN',
    this.onboardingCompletedAt,
    this.investingUnlockedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    displayName: json['display_name'] as String?,
    avatarUrl: json['avatar_url'] as String?,
    currency: json['currency'] as String? ?? 'INR',
    locale: json['locale'] as String? ?? 'en_IN',
    onboardingCompletedAt: _date(json['onboarding_completed_at']),
    investingUnlockedAt: _date(json['investing_unlocked_at']),
  );

  final String id;
  final String? displayName;
  final String? avatarUrl;
  final String currency;
  final String locale;
  final DateTime? onboardingCompletedAt;

  /// Set once and never cleared. Investing is an achievement, not a state.
  final DateTime? investingUnlockedAt;

  bool get hasCompletedOnboarding => onboardingCompletedAt != null;
  bool get isInvestingUnlocked => investingUnlockedAt != null;

  /// First name only. A dashboard greeting reads better as "Hi Samarth" than
  /// with a full legal name Google happened to supply.
  String get firstName {
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  String get currencySymbol => switch (currency) {
    'INR' => '₹',
    'USD' => r'$',
    'EUR' => '€',
    'GBP' => '£',
    _ => currency,
  };

  Profile copyWith({
    String? displayName,
    DateTime? onboardingCompletedAt,
    DateTime? investingUnlockedAt,
  }) => Profile(
    id: id,
    displayName: displayName ?? this.displayName,
    avatarUrl: avatarUrl,
    currency: currency,
    locale: locale,
    onboardingCompletedAt: onboardingCompletedAt ?? this.onboardingCompletedAt,
    investingUnlockedAt: investingUnlockedAt ?? this.investingUnlockedAt,
  );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}

/// Formats an amount in this profile's currency.
extension ProfileMoneyFormat on Profile {
  String format(Money amount) =>
      amount.format(locale: locale, symbol: currencySymbol);
  String formatCompact(Money amount) =>
      amount.formatCompact(locale: locale, symbol: currencySymbol);
}
