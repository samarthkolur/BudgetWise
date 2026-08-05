import 'dart:convert';

import 'package:budgetwise_server/src/auth/google_verifier.dart';
import 'package:budgetwise_server/src/auth/tokens.dart';
import 'package:budgetwise_server/src/db/owned_collection.dart';
import 'package:budgetwise_server/src/domain_errors.dart';
import 'package:shelf/shelf.dart';

/// One place that turns a thrown object into a response.
///
/// Route handlers throw; they never build an error body. That keeps the status
/// code for a given failure identical everywhere, which is what lets the client
/// branch on it — a 404 from one route and a 400 from another for the same
/// condition is how client error handling rots.
///
/// The response body is deliberately thin: a machine-readable `error` code and
/// a `message` already written for a human. Stack traces and driver messages
/// are logged, never sent — a Mongo error string tells an attacker about the
/// schema and tells the user nothing.
Response errorResponse(
  int status,
  String code,
  String message, {
  String? requestId,
}) => Response(
  status,
  body: jsonEncode({
    'error': code,
    'message': message,
    if (requestId != null) 'requestId': requestId,
  }),
  headers: {'content-type': 'application/json'},
);

/// Thrown by handlers for conditions that map to a specific status.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  const ApiException.badRequest(this.message)
    : status = 400,
      code = 'bad_request';

  const ApiException.unauthorized(this.message)
    : status = 401,
      code = 'unauthorized';

  const ApiException.notFound([this.message = 'That is no longer available.'])
    : status = 404,
      code = 'not_found';

  const ApiException.conflict(this.message) : status = 409, code = 'conflict';

  const ApiException.forbidden(this.message) : status = 403, code = 'forbidden';

  final int status;
  final String code;
  final String message;
}

/// Catches everything a handler can throw and renders it once.
Middleware errorHandler({void Function(Object, StackTrace)? onError}) {
  return (innerHandler) {
    return (request) async {
      final requestId = request.context['requestId'] as String?;
      try {
        return await innerHandler(request);
      } on ApiException catch (error) {
        return errorResponse(
          error.status,
          error.code,
          error.message,
          requestId: requestId,
        );
      } on NotOwnedException {
        // Deliberately 404, not 403. "That exists but is not yours" confirms
        // the id is real, which is a slow enumeration oracle.
        return errorResponse(
          404,
          'not_found',
          'That is no longer available.',
          requestId: requestId,
        );
      } on TokenException catch (error) {
        return errorResponse(
          401,
          'unauthorized',
          error.message,
          requestId: requestId,
        );
      } on GoogleAuthException catch (error) {
        return errorResponse(
          401,
          'unauthorized',
          error.message,
          requestId: requestId,
        );
      } on ValidationException catch (error) {
        return errorResponse(
          400,
          'bad_request',
          error.message,
          requestId: requestId,
        );
      } on ConflictException catch (error) {
        return errorResponse(
          409,
          'conflict',
          error.message,
          requestId: requestId,
        );
      } on NotPermittedException catch (error) {
        return errorResponse(
          403,
          'forbidden',
          error.message,
          requestId: requestId,
        );
      } on FormatException {
        return errorResponse(
          400,
          'bad_request',
          'That request could not be read.',
          requestId: requestId,
        );
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
        return errorResponse(
          500,
          'internal',
          'Something went wrong. Please try again.',
          requestId: requestId,
        );
      }
    };
  };
}
