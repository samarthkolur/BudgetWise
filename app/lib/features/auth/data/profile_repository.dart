import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<Profile> current() async => guarded(() async {
    final row = await _api.get('/v1/me') as Map<String, dynamic>;
    return Profile.fromJson(row);
  });

  Future<Profile> completeOnboarding() async => guarded(() async {
    final row =
        await _api.patch('/v1/me', {'onboardingCompleted': true})
            as Map<String, dynamic>;
    return Profile.fromJson(row);
  });

  /// Asks the API whether investing has been earned, and stamps it if so.
  ///
  /// The decision is the server's, made by the same code that guards the
  /// investment write — a client that lied about being unlocked would still be
  /// refused, which is what makes hiding the module and refusing the write one
  /// decision rather than two.
  Future<UnlockClaim> investingStatus() async => guarded(() async {
    final row = await _api.get('/v1/investing/status') as Map<String, dynamic>;
    return UnlockClaim(
      isUnlocked: row['isUnlocked'] as bool? ?? false,
      newlyUnlocked: row['newlyUnlocked'] as bool? ?? false,
      streakMonths: (row['streakMonths'] as num?)?.toInt() ?? 0,
      fundRatio: (row['fundRatio'] as num?)?.toDouble() ?? 0,
    );
  });

  Future<void> deleteAccount() async => guarded(() => _api.delete('/v1/me'));
}

/// The result of asking whether investing is available.
class UnlockClaim {
  const UnlockClaim({
    required this.isUnlocked,
    this.newlyUnlocked = false,
    this.streakMonths = 0,
    this.fundRatio = 0,
  });

  final bool isUnlocked;

  /// True only on the call that earned it — what the celebration keys off, so
  /// it appears once rather than on every launch thereafter.
  final bool newlyUnlocked;

  final int streakMonths;
  final double fundRatio;

  int get monthsRemaining =>
      (kRequiredStreakMonths - streakMonths).clamp(0, kRequiredStreakMonths);

  double get progress {
    final byStreak = streakMonths / kRequiredStreakMonths;
    return (byStreak > fundRatio ? byStreak : fundRatio).clamp(0.0, 1.0);
  }
}
