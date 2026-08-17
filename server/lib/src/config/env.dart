import 'dart:io';

/// Server configuration, read from the process environment.
///
/// Fails loudly at startup rather than lazily on first request. A server that
/// boots without a signing secret and only fails when someone tries to sign in
/// is a server that looks healthy while being useless.
class Env {
  Env({
    required this.mongoUri,
    required this.databaseName,
    required this.jwtSecret,
    required this.googleWebClientId,
    required this.googleAndroidClientId,
    required this.googleIosClientId,
    required this.port,
    required this.accessTokenTtl,
    required this.refreshTokenTtl,
    this.allowDevLogin = false,
  });

  factory Env.fromPlatform([Map<String, String>? source]) {
    final env = source ?? Platform.environment;

    final allowDevLogin =
        (env['ALLOW_DEV_LOGIN'] ?? '').toLowerCase() == 'true';

    // GOOGLE_WEB_CLIENT_ID is required only when Google sign-in is the way in.
    // With dev login enabled the stack runs with no cloud service at all, and
    // demanding a Google client would defeat the point.
    final required = <String>[
      'MONGO_URI',
      'JWT_SECRET',
      if (!allowDevLogin) 'GOOGLE_WEB_CLIENT_ID',
    ];
    final missing = <String>[
      for (final key in required)
        if ((env[key] ?? '').trim().isEmpty) key,
    ];
    if (missing.isNotEmpty) {
      throw ConfigException(
        'Missing required environment variables: ${missing.join(', ')}.\n'
        'See server/.env.example.',
      );
    }

    final secret = env['JWT_SECRET']!;
    // 32 bytes is the floor for HS256 to be worth doing. A short secret is a
    // brute-forceable one, and this token is the only thing standing between a
    // request and someone else's financial history.
    if (secret.length < 32) {
      throw ConfigException(
        'JWT_SECRET must be at least 32 characters (got ${secret.length}). '
        'Generate one with: openssl rand -base64 48',
      );
    }

    final mongoUri = env['MONGO_URI']!;

    // The guard that actually matters. The flag alone can be set by accident;
    // the flag AND a loopback database together cannot describe a production
    // deployment. Failing here is loud and immediate — the alternative is a
    // server that looks healthy while handing out sessions for nothing.
    if (allowDevLogin && !isLocalDatabase(mongoUri)) {
      throw const ConfigException(
        'ALLOW_DEV_LOGIN is set, but MONGO_URI does not point at a local '
        'database.\n'
        'Dev login is an authentication bypass and is refused against any '
        'non-local database.',
      );
    }

    return Env(
      allowDevLogin: allowDevLogin,
      mongoUri: mongoUri,
      databaseName: env['MONGO_DB'] ?? 'budgetwise',
      jwtSecret: secret,
      // Empty is legitimate under dev login and impossible otherwise — the
      // required-keys check above already rejected it.
      googleWebClientId: env['GOOGLE_WEB_CLIENT_ID'] ?? '',
      googleAndroidClientId: env['GOOGLE_ANDROID_CLIENT_ID'] ?? '',
      googleIosClientId: env['GOOGLE_IOS_CLIENT_ID'] ?? '',
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      accessTokenTtl: Duration(
        minutes: int.tryParse(env['ACCESS_TOKEN_MINUTES'] ?? '') ?? 60,
      ),
      refreshTokenTtl: Duration(
        days: int.tryParse(env['REFRESH_TOKEN_DAYS'] ?? '') ?? 60,
      ),
    );
  }

  final String mongoUri;
  final String databaseName;

  /// Enables `/v1/auth/dev/login`, which issues a session with no credential.
  /// Only ever true against a local database — see [Env.fromPlatform].
  final bool allowDevLogin;

  /// Signs our own access tokens. Never leaves the server.
  final String jwtSecret;

  /// Every client ID that may appear in a Google ID token's `aud`.
  ///
  /// Android and iOS clients mint tokens with their own audience, so accepting
  /// only the web ID rejects every real phone. Accepting *any* audience would
  /// let a token minted for an unrelated app sign in here, which is the actual
  /// attack this list prevents.
  final String googleWebClientId;
  final String googleAndroidClientId;
  final String googleIosClientId;

  final int port;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  /// True only for a database on this machine.
  ///
  /// `mongodb+srv://` is rejected outright: it is the Atlas scheme, and there is
  /// no such thing as a loopback SRV cluster.
  static bool isLocalDatabase(String uri) {
    if (uri.startsWith('mongodb+srv://')) return false;
    final host = Uri.tryParse(uri)?.host.toLowerCase() ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == 'host.docker.internal' ||
        host == 'mongo';
  }

  Set<String> get allowedAudiences => {
    googleWebClientId,
    if (googleAndroidClientId.isNotEmpty) googleAndroidClientId,
    if (googleIosClientId.isNotEmpty) googleIosClientId,
  };
}

/// Configuration that is missing or unusable. Fatal at startup, by design.
class ConfigException implements Exception {
  const ConfigException(this.message);
  final String message;

  @override
  String toString() => 'ConfigException: $message';
}
