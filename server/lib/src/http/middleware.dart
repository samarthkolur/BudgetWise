import 'dart:convert';
import 'dart:math';

import 'package:budgetwise_server/src/auth/tokens.dart';
import 'package:budgetwise_server/src/http/errors.dart';
import 'package:shelf/shelf.dart';

/// Stamps every request with an id, echoed in the response and in any error
/// body. When a user reports a failure, this is the string that finds it in the
/// logs.
Middleware requestId() {
  final random = Random();
  return (innerHandler) {
    return (request) async {
      final id = List.generate(
        8,
        (_) => '0123456789abcdef'[random.nextInt(16)],
      ).join();
      final response = await innerHandler(
        request.change(context: {'requestId': id}),
      );
      return response.change(headers: {'x-request-id': id});
    };
  };
}

/// Rejects oversized bodies before they are parsed.
///
/// An expense is a few hundred bytes; a month's plan is a few kilobytes.
/// Without a cap, a single request can make the process allocate until it dies,
/// which is a denial of service that costs the sender nothing.
Middleware bodyLimit({int maxBytes = 256 * 1024}) {
  return (innerHandler) {
    return (request) async {
      final declared = request.contentLength;
      if (declared != null && declared > maxBytes) {
        return errorResponse(413, 'too_large', 'That request is too large.');
      }
      return innerHandler(request);
    };
  };
}

/// Requires a valid access token and attaches the [Principal].
///
/// **Every route that touches user data sits behind this.** The principal it
/// produces is the only accepted source of an owner id — repositories take it
/// from here, never from the request body, which the caller controls.
Middleware requireAuth(TokenService tokens) {
  return (innerHandler) {
    return (request) async {
      final header = request.headers['authorization'];
      if (header == null || !header.toLowerCase().startsWith('bearer ')) {
        return errorResponse(401, 'unauthorized', 'Sign in to continue.');
      }

      final principal = tokens.verifyAccessToken(header.substring(7).trim());
      return innerHandler(
        request.change(context: {'principal': principal}),
      );
    };
  };
}

/// The authenticated caller. Only valid inside a [requireAuth] pipeline.
Principal principalOf(Request request) {
  final principal = request.context['principal'];
  if (principal is! Principal) {
    // Reaching this means a route was mounted outside the auth pipeline — a
    // wiring mistake, and one that would otherwise surface as an unscoped
    // query returning somebody else's data.
    throw StateError('Route is not behind requireAuth');
  }
  return principal;
}

/// Permissive CORS, for the Flutter web target and local tooling.
///
/// Safe here because the API authenticates with a Bearer token rather than a
/// cookie: there is no ambient credential for another origin to ride on, so
/// CSRF is not the risk it would be for a session cookie.
Middleware cors() {
  const headers = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
    'access-control-allow-headers': 'authorization, content-type',
    'access-control-max-age': '86400',
  };

  return (innerHandler) {
    return (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: headers);
      }
      final response = await innerHandler(request);
      return response.change(headers: headers);
    };
  };
}

/// Reads and decodes a JSON object body.
Future<Map<String, dynamic>> readJson(Request request) async {
  final body = await request.readAsString();
  if (body.trim().isEmpty) return {};
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const ApiException.badRequest('Expected a JSON object.');
  }
  return decoded;
}

Response jsonResponse(Object? payload, {int status = 200}) => Response(
  status,
  body: jsonEncode(payload),
  headers: {'content-type': 'application/json'},
);
