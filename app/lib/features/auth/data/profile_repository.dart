import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/db/local_database.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:budgetwise_domain/budgetwise_domain.dart';
import 'package:uuid/uuid.dart';

/// Everything a screen needs to know about the signed-in — or local-only —
/// user. Two implementations: [ApiProfileRepository] when a session exists,
/// [LocalProfileRepository] otherwise. Neither the providers nor the screens
/// that consume this interface know or care which one they got.
abstract class ProfileRepository {
  Future<Profile> current();
  Future<Profile> updateProfile({required String displayName});
  Future<Profile> completeOnboarding();
  Future<UnlockClaim> investingStatus();
  Future<void> deleteAccount();
}

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._api);

  final ApiClient _api;

  @override
  Future<Profile> current() async => guarded(() async {
    final row = await _api.get('/v1/me') as Map<String, dynamic>;
    return Profile.fromJson(row);
  });

  @override
  Future<Profile> updateProfile({required String displayName}) async =>
      guarded(() async {
        final row =
            await _api.patch('/v1/me', {'displayName': displayName})
                as Map<String, dynamic>;
        return Profile.fromJson(row);
      });

  @override
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
  @override
  Future<UnlockClaim> investingStatus() async => guarded(() async {
    final row = await _api.get('/v1/investing/status') as Map<String, dynamic>;
    return UnlockClaim(
      isUnlocked: row['isUnlocked'] as bool? ?? false,
      newlyUnlocked: row['newlyUnlocked'] as bool? ?? false,
      streakMonths: (row['streakMonths'] as num?)?.toInt() ?? 0,
      fundRatio: (row['fundRatio'] as num?)?.toDouble() ?? 0,
    );
  });

  @override
  Future<void> deleteAccount() async => guarded(() => _api.delete('/v1/me'));
}

/// The on-device profile, used whenever no one is signed in.
///
/// A single row, created on first access rather than at install time — there
/// is no sign-up step to hang it off, so the first read of [current] is it.
class LocalProfileRepository implements ProfileRepository {
  LocalProfileRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  @override
  Future<Profile> current() async {
    final db = (await _dbFuture).db;
    final rows = await db.query('local_profile', limit: 1);
    if (rows.isNotEmpty) return _fromRow(rows.first);

    final profile = Profile(id: const Uuid().v4());
    await db.insert('local_profile', _toRow(profile));
    return profile;
  }

  @override
  Future<Profile> updateProfile({required String displayName}) async {
    final db = (await _dbFuture).db;
    final existing = await current();
    final updated = existing.copyWith(displayName: displayName);
    await db.update(
      'local_profile',
      _toRow(updated),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    return updated;
  }

  @override
  Future<Profile> completeOnboarding() async {
    final db = (await _dbFuture).db;
    final existing = await current();
    final updated = existing.copyWith(onboardingCompletedAt: DateTime.now());
    await db.update(
      'local_profile',
      _toRow(updated),
      where: 'id = ?',
      whereArgs: [updated.id],
    );
    return updated;
  }

  /// Investing is a server-verified achievement — there is nothing to unlock
  /// without a server to unlock it against, so local mode is always locked.
  @override
  Future<UnlockClaim> investingStatus() async =>
      const UnlockClaim(isUnlocked: false);

  @override
  Future<void> deleteAccount() async {
    final db = (await _dbFuture).db;
    await db.delete('local_profile');
    await db.delete('goals');
    await db.delete('expenses');
    await db.delete('categories');
    await db.delete('budgets');
  }

  static Profile _fromRow(Map<String, Object?> row) => Profile(
    id: row['id']! as String,
    email: row['email'] as String?,
    displayName: row['display_name'] as String?,
    avatarUrl: row['avatar_url'] as String?,
    currency: row['currency']! as String,
    locale: row['locale']! as String,
    onboardingCompletedAt: _date(row['onboarding_completed_at']),
    investingUnlockedAt: _date(row['investing_unlocked_at']),
  );

  static Map<String, Object?> _toRow(Profile profile) => {
    'id': profile.id,
    'email': profile.email,
    'display_name': profile.displayName,
    'avatar_url': profile.avatarUrl,
    'currency': profile.currency,
    'locale': profile.locale,
    'onboarding_completed_at': profile.onboardingCompletedAt?.toIso8601String(),
    'investing_unlocked_at': profile.investingUnlockedAt?.toIso8601String(),
  };

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
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
