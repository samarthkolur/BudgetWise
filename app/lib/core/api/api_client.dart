import 'dart:convert';

import 'package:budgetwise/core/api/token_store.dart';
import 'package:budgetwise/core/env/env.dart';
import 'package:budgetwise/core/errors/failures.dart';
import 'package:http/http.dart' as http;

/// The only thing in the app that speaks HTTP to the API.
///
/// Two responsibilities beyond sending requests:
///
/// 1. **Attaching the access token**, so no caller has to remember to.
/// 2. **Refreshing it exactly once on a 401 and replaying the request.** Access
///    tokens are short-lived by design, so expiry during ordinary use is normal
///    rather than exceptional — if each screen handled it, some screen would
///    handle it wrong and the user would be bounced to sign-in mid-task.
///
/// The retry is deliberately single-shot. A refresh that itself 401s means the
/// session is genuinely over, and retrying again would be an infinite loop
/// against a server that has already said no twice.
class ApiClient {
  ApiClient({required TokenStore tokens, http.Client? httpClient})
    : _tokens = tokens,
      _http = httpClient ?? http.Client();

  final TokenStore _tokens;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('${Env.apiBaseUrl}$path');

  Future<dynamic> get(String path) => _send('GET', path, null);

  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body);

  Future<dynamic> patch(String path, [Object? body]) =>
      _send('PATCH', path, body);

  Future<dynamic> delete(String path) => _send('DELETE', path, null);

  /// Sends without a token — sign-in and refresh only.
  Future<dynamic> postAnonymous(String path, Object? body) async {
    final response = await _http.post(
      _uri(path),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body, {
    bool isRetry = false,
  }) async {
    final token = await _tokens.accessToken;
    if (token == null) {
      throw const AuthFailure('Sign in to continue.');
    }

    final response = await _dispatch(method, path, body, token);

    if (response.statusCode == 401 && !isRetry) {
      final refreshed = await _refresh();
      if (refreshed) return _send(method, path, body, isRetry: true);
      // The session is over. Clearing here rather than leaving a dead token in
      // storage is what lets the router notice and move the user to sign-in.
      await _tokens.clear();
      throw const AuthFailure('Your session expired. Please sign in again.');
    }

    return _decode(response);
  }

  Future<http.Response> _dispatch(
    String method,
    String path,
    Object? body,
    String token,
  ) {
    final uri = _uri(path);
    final headers = {
      'content-type': 'application/json',
      'authorization': 'Bearer $token',
    };
    final encoded = body == null ? null : jsonEncode(body);

    return switch (method) {
      'GET' => _http.get(uri, headers: headers),
      'POST' => _http.post(uri, headers: headers, body: encoded),
      'PATCH' => _http.patch(uri, headers: headers, body: encoded),
      'DELETE' => _http.delete(uri, headers: headers),
      _ => throw ArgumentError('Unsupported method $method'),
    };
  }

  Future<bool> _refresh() async {
    final refreshToken = await _tokens.refreshToken;
    if (refreshToken == null) return false;

    try {
      final response = await _http.post(
        _uri('/v1/auth/refresh'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode != 200) return false;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      await _tokens.save(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
      );
      return true;
    } on Object {
      return false;
    }
  }

  /// Turns a response into data, or into an [AppFailure].
  ///
  /// The server sends a machine-readable `error` code and a message already
  /// written for a human, so the mapping is on the code and the message passes
  /// through untouched. Inventing a second set of wordings on the client is how
  /// the same failure ends up phrased two different ways.
  dynamic _decode(http.Response response) {
    if (response.statusCode == 204 || response.body.isEmpty) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const UnexpectedFailure();
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final body = decoded is Map<String, dynamic>
        ? decoded
        : const <String, dynamic>{};
    final message =
        body['message'] as String? ?? 'Something went wrong. Please try again.';

    throw switch (response.statusCode) {
      400 => ValidationFailure(message),
      401 => AuthFailure(message),
      403 => ValidationFailure(message),
      404 => NotFoundFailure(message),
      409 => ConflictFailure(message),
      413 => const ValidationFailure('That was too large to send.'),
      _ => UnexpectedFailure(message),
    };
  }

  void close() => _http.close();
}

/// Wraps a call so transport failures surface as [NetworkFailure] rather than
/// as a raw socket error.
Future<T> guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on AppFailure {
    rethrow;
  } on Object catch (error, stackTrace) {
    throw mapError(error, stackTrace);
  }
}
