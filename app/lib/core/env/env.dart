/// Build-time configuration, supplied by `--dart-define-from-file`.
///
///     flutter run --dart-define-from-file=config/dev.json
///
/// `config/*.json` is not committed; `config/example.json` is. Nothing secret
/// lives here: the app holds no database credential at all now, because it does
/// not talk to MongoDB. It talks to the API, and the API holds the connection
/// string. That separation is the whole reason the server exists.
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

  /// The **web** OAuth client ID. Passed to Google Sign-In as `serverClientId`,
  /// and the audience the API validates the returned ID token against. Not the
  /// Android one.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// iOS only. Android derives its client from the package name and signing
  /// certificate — but the release SHA-1 must be registered on the Google
  /// Android OAuth client, or sign-in works in debug and fails in production.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Shows the local sign-in button and lets the app start without a Google
  /// client ID.
  ///
  /// A build-time constant, so a release build compiled without it contains no
  /// path to the dev endpoint at all — the button is not hidden, it does not
  /// exist. The server has its own, independent guard: even a build with this
  /// on can only reach a server that also enabled it, against a local database.
  static const devLogin = bool.fromEnvironment('DEV_LOGIN');

  static bool get isConfigured => missingKeys.isEmpty;

  /// Names what is missing, so a misconfigured build says so on screen instead
  /// of failing later as an unexplained network error.
  ///
  /// A value straight out of `config/example.json` counts as missing. Checking
  /// only for emptiness was not enough, and this was found by running the app
  /// on a real device: copying the example file gives every key a non-empty
  /// placeholder, so the guard passed, the app booted past the configuration
  /// screen, and sign-in opened Google's account chooser before failing against
  /// a backend that did not exist. A confusing failure three screens in is
  /// exactly what this check exists to prevent.
  static List<String> get missingKeys => [
    if (_unset(apiBaseUrl)) 'API_BASE_URL',
    // Not needed when signing in locally — the whole point of DEV_LOGIN is that
    // the stack runs with no cloud service configured.
    if (!devLogin && _unset(googleWebClientId)) 'GOOGLE_WEB_CLIENT_ID',
  ];

  static bool _unset(String value) =>
      value.isEmpty ||
      value.contains('YOUR_') ||
      value.contains('<your-') ||
      value.contains('ci-placeholder');
}
