import 'package:budgetwise/core/api/api_client.dart';
import 'package:budgetwise/core/api/token_store.dart';
import 'package:budgetwise/core/env/env.dart';
import 'package:budgetwise/core/errors/failures.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Google sign-in, exchanged for a BudgetWise session.
///
/// The app sends the Google ID token to our API, which verifies it against
/// Google and returns tokens it signed. `google_sign_in`
/// remains only the native account picker — it holds no session and makes no
/// authorization decision.
///
/// Written against google_sign_in v7, which replaced `signIn()` with
/// `initialize()` + `authenticate()`. The major version is pinned because every
/// tutorial still shows the v6 API.
class GoogleAuthService {
  GoogleAuthService({
    required ApiClient api,
    required TokenStore tokens,
    GoogleSignIn? googleSignIn,
  }) : _api = api,
       _tokens = tokens,
       _google = googleSignIn ?? GoogleSignIn.instance;

  final ApiClient _api;
  final TokenStore _tokens;
  final GoogleSignIn _google;

  bool _initialised = false;

  Future<void> _ensureInitialised() async {
    if (_initialised) return;
    await _google.initialize(
      // iOS reads its client from here; Android derives its own from the
      // package name and signing certificate, so it passes nothing.
      clientId: Env.googleIosClientId.isEmpty ? null : Env.googleIosClientId,
      // The audience our API validates the returned ID token against. This is
      // the WEB client ID, not the Android one.
      serverClientId: Env.googleWebClientId,
    );
    _initialised = true;
  }

  /// Opens the account picker and exchanges the result for a session.
  ///
  /// Throws [AuthCancelled] when the user dismisses the sheet — a cancellation
  /// is a decision, not a failure, and callers treat it as silence.
  Future<void> signIn() async {
    try {
      await _ensureInitialised();

      final account = await _google.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        // Almost always configuration rather than the user: the serverClientId
        // is wrong, or this build's SHA-1 is not registered on the Google
        // Android OAuth client.
        throw const AuthFailure(
          "Google didn't return a sign-in token. Please try again.",
        );
      }

      final response =
          await _api.postAnonymous('/v1/auth/google', {'idToken': idToken})
              as Map<String, dynamic>;

      await _tokens.save(
        accessToken: response['accessToken'] as String,
        refreshToken: response['refreshToken'] as String,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthCancelled();
      }
      throw AuthFailure(_messageFor(error), cause: error);
    } on AppFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw mapError(error, stackTrace);
    }
  }

  /// Ends the session everywhere it exists.
  ///
  /// The refresh token is revoked server-side first, so it cannot be replayed;
  /// then Google is signed out so the next sign-in shows the account picker
  /// rather than silently reusing the previous account — on a shared device,
  /// skipping that signs the wrong person back in.
  Future<void> signOut() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken != null) {
      try {
        await _api.postAnonymous('/v1/auth/sign-out', {
          'refreshToken': refreshToken,
        });
      } on Object {
        // A server that cannot be reached must not strand the user in a
        // signed-in state. The local clear below is what matters here.
      }
    }

    try {
      await _ensureInitialised();
      await _google.signOut();
    } on Object {
      // Same reasoning.
    }

    await _tokens.clear();
  }

  String _messageFor(GoogleSignInException error) => switch (error.code) {
    GoogleSignInExceptionCode.canceled => 'Sign-in cancelled',
    GoogleSignInExceptionCode.interrupted =>
      'Sign-in was interrupted. Please try again.',
    GoogleSignInExceptionCode.clientConfigurationError =>
      'Sign-in is not configured correctly for this build.',
    GoogleSignInExceptionCode.providerConfigurationError =>
      'Google sign-in is unavailable on this device.',
    GoogleSignInExceptionCode.uiUnavailable =>
      'Sign-in is unavailable right now. Please try again.',
    GoogleSignInExceptionCode.userMismatch =>
      'That was a different account. Please try again.',
    GoogleSignInExceptionCode.unknownError =>
      'Sign-in failed. Please try again.',
  };
}
