import 'package:budgetwise/core/env/env.dart';
import 'package:budgetwise/core/errors/failures.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Google sign-in, exchanged for a Supabase session.
///
/// **Supabase Auth is the identity system.** It owns `auth.users`, issues and
/// refreshes the JWT, and supplies the `auth.uid()` that every RLS policy keys
/// on. Google is the single enabled provider inside it, and this class is only
/// the native account picker — it holds no session and makes no authorization
/// decision. The source of truth for "who is signed in" is always
/// `supabase.auth.currentSession`.
///
/// The native ID-token flow is used rather than `signInWithOAuth`: it shows the
/// platform account sheet instead of handing off to a browser, and needs no
/// deep-link configuration or redirect allowlist entry.
///
/// Written against google_sign_in v7, which replaced `signIn()` with
/// `initialize()` + `authenticate()` and moved access tokens to
/// `authorizationClient`. The major version is pinned in pubspec.yaml; check
/// the package README before changing it.
class GoogleAuthService {
  GoogleAuthService(this._supabase, {GoogleSignIn? googleSignIn})
    : _google = googleSignIn ?? GoogleSignIn.instance;

  final SupabaseClient _supabase;
  final GoogleSignIn _google;

  bool _initialised = false;

  Future<void> _ensureInitialised() async {
    if (_initialised) return;
    await _google.initialize(
      // iOS reads its client from here; Android derives its own from the
      // package name and signing certificate, so it passes nothing.
      clientId: Env.googleIosClientId.isEmpty ? null : Env.googleIosClientId,
      // The audience Supabase validates the returned ID token against. This is
      // the WEB client ID, not the Android one.
      serverClientId: Env.googleWebClientId,
    );
    _initialised = true;
  }

  /// Opens the account picker and exchanges the result for a Supabase session.
  ///
  /// Throws [AuthCancelled] when the user dismisses the sheet — a cancellation
  /// is a decision, not a failure, and callers are expected to treat it as
  /// silence rather than showing an error.
  Future<AuthResponse> signIn() async {
    try {
      await _ensureInitialised();

      final account = await _google.authenticate(
        scopeHint: const ['email', 'profile'],
      );

      final idToken = account.authentication.idToken;
      if (idToken == null) {
        // Almost always a configuration problem rather than a user one: the
        // serverClientId is wrong, or this build's SHA-1 is not registered on
        // the Google Android OAuth client.
        throw const AuthFailure(
          "Google didn't return a sign-in token. Please try again.",
        );
      }

      // Access token is optional for Supabase, but supplying it lets the
      // session carry Google's own token where a later feature needs it.
      final authorization = await account.authorizationClient
          .authorizationForScopes(const ['email', 'profile']);

      return await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization?.accessToken,
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

  /// Ends both sessions.
  ///
  /// Google is signed out as well as Supabase, so the next sign-in shows the
  /// account picker rather than silently reusing the previous account — on a
  /// shared device, skipping this signs the wrong person back in.
  Future<void> signOut() async {
    try {
      await _ensureInitialised();
      await _google.signOut();
    } on Object catch (_) {
      // A failure to clear the Google account must not strand the user in a
      // signed-in state. The Supabase sign-out below is the one that matters.
    }
    await _supabase.auth.signOut();
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
