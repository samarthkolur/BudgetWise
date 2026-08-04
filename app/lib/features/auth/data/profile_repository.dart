import 'package:budgetwise/core/budget/investing_unlock.dart';
import 'package:budgetwise/core/errors/failures.dart';
import 'package:budgetwise/features/auth/domain/profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileRepository {
  ProfileRepository(this._db);

  final SupabaseClient _db;

  /// The signed-in user's profile.
  ///
  /// Created by a database trigger on `auth.users`, so it always exists by the
  /// time a session does — no insert-after-first-sign-in race to lose.
  Future<Profile> current() async {
    try {
      final row = await _db
          .from('profiles')
          .select()
          .eq('id', _db.auth.currentUser!.id)
          .single();
      return Profile.fromJson(row);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<void> completeOnboarding() async {
    try {
      await _db
          .from('profiles')
          .update({
            'onboarding_completed_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', _db.auth.currentUser!.id);
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Asks the database whether investing has been earned, and stamps it if so.
  ///
  /// The decision is made server-side by `fn_claim_investing_unlock`, not here.
  /// The same condition guards the `investments` insert policy, so hiding the
  /// module and refusing the write are one decision in one place — a client
  /// that lied about being unlocked would still be refused by the database.
  Future<UnlockClaim> claimInvestingUnlock() async {
    try {
      final rows = await _db.rpc<List<dynamic>>('fn_claim_investing_unlock');
      if (rows.isEmpty) return const UnlockClaim(isUnlocked: false);
      final row = rows.first as Map<String, dynamic>;
      return UnlockClaim(
        isUnlocked: row['is_unlocked'] as bool? ?? false,
        newlyUnlocked: row['newly_unlocked'] as bool? ?? false,
        streakMonths: (row['streak_months'] as num?)?.toInt() ?? 0,
        fundRatio: (row['fund_ratio'] as num?)?.toDouble() ?? 0,
      );
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }
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

  /// True only on the call that earned it — what the celebration screen keys
  /// off, so it appears once rather than on every launch thereafter.
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
