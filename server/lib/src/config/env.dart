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
  });

  factory Env.fromPlatform([Map<String, String>? source]) {
    final env = source ?? Platform.environment;

    final missing = <String>[
      for (final key in const [
        'MONGO_URI',
        'JWT_SECRET',
        'GOOGLE_WEB_CLIENT_ID',
      ])
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

    return Env(
      mongoUri: env['MONGO_URI']!,
      databaseName: env['MONGO_DB'] ?? 'budgetwise',
      jwtSecret: secret,
      googleWebClientId: env['GOOGLE_WEB_CLIENT_ID']!,
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
