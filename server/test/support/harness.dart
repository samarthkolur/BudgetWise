import 'dart:convert';
import 'dart:io';

import 'package:budgetwise_server/budgetwise_server.dart';
import 'package:http/http.dart' as http;
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';

/// A stand-in for Google's tokeninfo endpoint.
///
/// The tests must exercise the real verifier — audience check, issuer check,
/// expiry check — without contacting Google, so the HTTP client is swapped and
/// the response is composed here. A verifier tested against a mock of *itself*
/// would prove nothing.
class FakeGoogle extends http.BaseClient {
  FakeGoogle({required this.audience});

  final String audience;

  /// Tokens the fake will honour: token string -> claims.
  final Map<String, Map<String, dynamic>> _tokens = {};

  /// Registers a token that will verify successfully.
  String issue({
    required String subject,
    required String email,
    String? name,
    String? audienceOverride,
    DateTime? expiry,
  }) {
    final token = 'fake-$subject-${_tokens.length}';
    _tokens[token] = {
      'aud': audienceOverride ?? audience,
      'iss': 'https://accounts.google.com',
      'sub': subject,
      'email': email,
      'name': name,
      'email_verified': 'true',
      'exp':
          ((expiry ?? DateTime.now().add(const Duration(hours: 1)))
                      .millisecondsSinceEpoch ~/
                  1000)
              .toString(),
    };
    return token;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = request.url.queryParameters['id_token'];
    final claims = _tokens[token];
    if (claims == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"invalid_token"}')),
        400,
      );
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(claims))),
      200,
    );
  }
}

/// A running API backed by a real MongoDB, exercised through the real
/// middleware pipeline in-process.
///
/// No port is bound: the handler is called directly, which keeps the suite fast
/// while still running every request through auth, error mapping and routing
/// exactly as production does.
class Harness {
  Harness._(this.mongo, this.api, this.google, this.databaseName);

  final Mongo mongo;
  final BudgetWiseApi api;
  final FakeGoogle google;
  final String databaseName;

  static const audience = 'test-web-client.apps.googleusercontent.com';

  static Future<Harness> start() async {
    final uri =
        Platform.environment['MONGO_TEST_URI'] ?? 'mongodb://localhost:27018';
    // One database per suite process, cleared between tests by [reset].
    //
    // Not one per test: creating a database means creating index files, and
    // doing that dozens of times in a few seconds was enough to make WiredTiger
    // abort with a fatal assertion. Emptying collections is both faster and
    // gentler, and gives the same isolation.
    final databaseName =
        'budgetwise_test_${DateTime.now().microsecondsSinceEpoch}';

    final mongo = await Mongo.connect('$uri/$databaseName');
    await mongo.ensureIndexes();

    final google = FakeGoogle(audience: audience);
    final env = Env(
      mongoUri: uri,
      databaseName: databaseName,
      jwtSecret: 'test-secret-that-is-definitely-long-enough-000000',
      googleWebClientId: audience,
      googleAndroidClientId: '',
      googleIosClientId: '',
      port: 0,
      accessTokenTtl: const Duration(hours: 1),
      refreshTokenTtl: const Duration(days: 30),
    );

    final api = BudgetWiseApi(
      env: env,
      mongo: mongo,
      verifier: GoogleVerifier(
        allowedAudiences: {audience},
        httpClient: google,
      ),
    );

    return Harness._(mongo, api, google, databaseName);
  }

  Future<void> stop() async {
    await mongo.db.drop();
    await mongo.close();
  }

  /// Empties every collection, leaving the indexes in place.
  Future<void> reset() async {
    for (final name in Col.all) {
      await mongo.collection(name).deleteMany(<String, Object>{});
    }
  }

  Handler get handler => api.handler;

  /// Signs a new user in and returns their session.
  Future<Session> signIn({
    required String subject,
    required String email,
  }) async {
    final idToken = google.issue(subject: subject, email: email);
    final response = await post('/v1/auth/google', {'idToken': idToken});
    final raw = await response.readAsString();
    if (response.statusCode != 200) {
      throw StateError('sign-in failed: ${response.statusCode} $raw');
    }
    final body = jsonDecode(raw) as Map<String, dynamic>;
    return Session(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      userId: (body['user'] as Map<String, dynamic>)['id'] as String,
      harness: this,
    );
  }

  Future<Response> get(String path, {String? token}) =>
      _send('GET', path, null, token);

  Future<Response> post(String path, Object? body, {String? token}) =>
      _send('POST', path, body, token);

  Future<Response> patch(String path, Object? body, {String? token}) =>
      _send('PATCH', path, body, token);

  Future<Response> delete(String path, {String? token}) =>
      _send('DELETE', path, null, token);

  Future<Response> _send(
    String method,
    String path,
    Object? body,
    String? token,
  ) async {
    return handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }
}

/// A signed-in user, with helpers that carry the token automatically.
class Session {
  Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.harness,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final Harness harness;

  ObjectId get ownerId => ObjectId.fromHexString(userId);

  Future<Response> get(String path) => harness.get(path, token: accessToken);
  Future<Response> post(String path, Object? body) =>
      harness.post(path, body, token: accessToken);
  Future<Response> patch(String path, Object? body) =>
      harness.patch(path, body, token: accessToken);
  Future<Response> delete(String path) =>
      harness.delete(path, token: accessToken);
}

/// Reads a JSON body.
Future<T> jsonBody<T>(Response response) async =>
    jsonDecode(await response.readAsString()) as T;

/// Two categories, split evenly, summing exactly to [spendableMinor].
List<Map<String, dynamic>> categoriesFor(int spendableMinor) {
  // Two categories, split evenly, so the arithmetic in the tests stays obvious.
  final half = spendableMinor ~/ 2;
  return [
    {
      'categoryKey': 'food',
      'displayName': 'Food',
      'icon': '🍽️',
      'allocatedMinor': half,
      'allocatedPercent': 50.0,
      'sortOrder': 0,
    },
    {
      'categoryKey': 'bills',
      'displayName': 'Bills',
      'icon': '🧾',
      'allocatedMinor': spendableMinor - half,
      'allocatedPercent': 50.0,
      'sortOrder': 1,
    },
  ];
}
