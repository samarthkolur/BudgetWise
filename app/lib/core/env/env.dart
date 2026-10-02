/// Build-time configuration, supplied by `--dart-define-from-file`.
///
///     flutter run --dart-define-from-file=config/dev.json
///
/// `config/*.json` is not committed; `config/example.json` is. Nothing secret
/// lives here: the app holds no database credential at all now, because it does
/// not talk to Postgres directly. It talks to the API, and the API holds the
/// connection string. That separation is the whole reason the server exists.
///
/// Read through `const String.fromEnvironment`, which is resolved at compile
/// time — there is no runtime lookup to fail and no `.env` file to forget to
/// ship.
abstract final class Env {
  /// Where the API lives. No trailing slash.
  ///
  /// On an Android emulator, `localhost` is the emulator itself — use
  /// `http://10.0.2.2:8080`. On a physical phone it must be the development
  /// machine's LAN address; the device has no route to your loopback.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isConfigured => missingKeys.isEmpty;

  /// Names what is missing, so a misconfigured build says so on screen instead
  /// of failing later as an unexplained network error.
  ///
  /// A value straight out of `config/example.json` counts as missing. Checking
  /// only for emptiness was not enough, and this was found by running the app
  /// on a real device: copying the example file gives every key a non-empty
  /// placeholder, so the guard passed, the app booted past the configuration
  /// screen, and the first API call failed against a backend that did not
  /// exist. A confusing failure three screens in is exactly what this check
  /// exists to prevent.
  static List<String> get missingKeys => [
    if (_unset(apiBaseUrl)) 'API_BASE_URL',
  ];

  static bool _unset(String value) =>
      value.isEmpty ||
      value.contains('YOUR_') ||
      value.contains('<your-') ||
      value.contains('ci-placeholder');
}
