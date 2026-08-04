/// Build-time configuration, supplied by `--dart-define-from-file`.
///
///     flutter run --dart-define-from-file=config/dev.json
///
/// `config/*.json` is not committed; `config/example.json` is. The anon key is
/// publishable — it is designed to ship inside a client — but environments still
/// have to stay swappable, and secrets must not learn the habit of living in
/// git. The real security boundary is RLS, not the secrecy of this key.
///
/// Read through `const String.fromEnvironment`, which is resolved at compile
/// time. There is no runtime lookup to fail, and no `.env` file to forget to
/// ship.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// The **web** OAuth client ID. Passed to Google Sign-In as `serverClientId`
  /// and configured in Supabase as the provider's client ID — it is the
  /// audience Supabase validates the ID token against. Not the Android one.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// iOS only. Android derives its client from the package name and signing
  /// certificate, so it needs no ID here — but the release SHA-1 must be
  /// registered on the Android OAuth client or sign-in works in debug and fails
  /// in production.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      googleWebClientId.isNotEmpty;

  /// Names what is missing, so a misconfigured build says so on screen instead
  /// of failing later as an unexplained network error.
  static List<String> get missingKeys => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
    if (googleWebClientId.isEmpty) 'GOOGLE_WEB_CLIENT_ID',
  ];
}
