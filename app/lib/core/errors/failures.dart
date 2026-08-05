import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Everything that can go wrong, in terms the UI can act on.
///
/// The API sends a machine-readable `error` code and a message already written
/// for a human, so the API client maps status codes to these types and passes the
/// message through. Nothing above the data layer branches on an HTTP status,
/// and no server-side detail reaches a user.
///
/// The client never speaks to the database, so it has no database errors to
/// understand — the server owns that translation and the client only has to know
/// its own API.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause});

  /// Shown to the user as-is. Written in the second person, no error codes.
  final String message;
  final Object? cause;

  @override
  String toString() => '${objectRuntimeType(this, 'AppFailure')}: $message';
}

/// No usable connection, or the request never completed.
class NetworkFailure extends AppFailure {
  const NetworkFailure([
    super.message =
        "You're offline. Your changes will sync when you reconnect.",
    Object? cause,
  ]) : super(cause: cause);
}

/// The session is gone or was never valid. The router sends these to sign-in.
class AuthFailure extends AppFailure {
  const AuthFailure(super.message, {super.cause});
}

/// The user abandoned the Google sheet. Not an error — no toast, no log.
class AuthCancelled extends AuthFailure {
  const AuthCancelled() : super('Sign-in cancelled');
}

/// The thing exists but is not this user's — or does not exist at all.
///
/// The server reports both as 404 on purpose: distinguishing them would confirm
/// that an id is real, which is a slow enumeration oracle.
class NotFoundFailure extends AppFailure {
  const NotFoundFailure([
    super.message = 'That is no longer available.',
    Object? cause,
  ]) : super(cause: cause);
}

/// The input was refused. Usually recoverable by changing it.
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause});
}

/// A duplicate of something that must be unique — most often a second budget
/// for a month that already has one.
class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, {super.cause});
}

/// The catch-all. Carries the original so it can be logged, never displayed.
class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([
    super.message = 'Something went wrong. Please try again.',
    Object? cause,
  ]) : super(cause: cause);
}

/// Maps a transport-level error into an [AppFailure].
///
/// HTTP status mapping happens in the API client; this handles what fails before a
/// response exists — no network, DNS failure, a dropped socket.
AppFailure mapError(Object error, [StackTrace? stackTrace]) {
  if (error is AppFailure) return error;

  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      _looksLikeNetwork(error)) {
    return NetworkFailure(
      "You're offline. Your changes will sync when you reconnect.",
      error,
    );
  }

  return UnexpectedFailure('Something went wrong. Please try again.', error);
}

/// The http package's `ClientException` is not on this project's import
/// surface, and a dropped connection surfaces in several shapes besides it.
/// Matching on the rendered message is uglier than a type check but catches all
/// of them, and the cost of a false positive is only a friendlier message.
bool _looksLikeNetwork(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable');
}
