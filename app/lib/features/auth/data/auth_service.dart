import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/api/token_store.dart';
import 'package:budgetwise/core/errors/failures.dart';

/// Email/password sign-up and sign-in, exchanged for a BudgetWise session.
///
/// Replaces Google as the only identity provider — the server now holds a
/// password hash per account instead of verifying a third-party token, but the
/// session it hands back is the same `accessToken`/`refreshToken` pair either
/// way, which is why [TokenStore] and [ApiClient] needed no changes.
class AuthService {
  AuthService({required ApiClient api, required TokenStore tokens})
    : _api = api,
      _tokens = tokens;

  final ApiClient _api;
  final TokenStore _tokens;

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final response =
          await _api.postAnonymous('/v1/auth/signup', {
                'email': email.trim(),
                'password': password,
                'displayName': displayName.trim(),
              })
              as Map<String, dynamic>;
      await _save(response);
    } on AppFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  Future<void> logIn({required String email, required String password}) async {
    try {
      final response =
          await _api.postAnonymous('/v1/auth/login', {
                'email': email.trim(),
                'password': password,
              })
              as Map<String, dynamic>;
      await _save(response);
    } on AppFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Ends the session. The refresh token is revoked server-side first, so it
  /// cannot be replayed; a server that cannot be reached must not strand the
  /// user in a signed-in state, so the local clear below always happens
  /// regardless of whether the revoke call succeeded.
  Future<void> signOut() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken != null) {
      try {
        await _api.postAnonymous('/v1/auth/sign-out', {
          'refreshToken': refreshToken,
        });
      } on Object {
        // Local clear below is what matters.
      }
    }
    await _tokens.clear();
  }

  Future<void> _save(Map<String, dynamic> response) => _tokens.save(
    accessToken: response['accessToken'] as String,
    refreshToken: response['refreshToken'] as String,
  );
}
