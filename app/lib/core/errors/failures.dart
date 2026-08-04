import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything that can go wrong, in terms the UI can act on.
///
/// Repositories map Postgrest, Auth and socket exceptions to these at the data
/// boundary, so no widget ever branches on a driver-specific error class and no
/// raw database message reaches a user. A Postgres constraint name is a fact
/// about our schema; it is not an explanation anyone outside this codebase can
/// use.
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

/// The row exists but this user may not see it — or it does not exist at all.
/// RLS makes those indistinguishable from the client, which is the point.
class NotFoundFailure extends AppFailure {
  const NotFoundFailure([
    super.message = 'That is no longer available.',
    Object? cause,
  ]) : super(cause: cause);
}

/// A constraint said no. Usually recoverable by changing the input.
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

/// Translates a driver exception into an [AppFailure].
///
/// Postgres error codes are matched rather than message text: messages are
/// localised and reworded between versions, codes are not.
AppFailure mapError(Object error, [StackTrace? stackTrace]) {
  if (error is AppFailure) return error;

  if (error is SocketException ||
      error is TimeoutException ||
      _looksLikeNetwork(error)) {
    return NetworkFailure(
      "You're offline. Your changes will sync when you reconnect.",
      error,
    );
  }

  if (error is AuthException) {
    return AuthFailure(_authMessage(error), cause: error);
  }

  if (error is PostgrestException) {
    return switch (error.code) {
      // unique_violation
      '23505' => ConflictFailure(_uniqueMessage(error), cause: error),
      // foreign_key_violation — with composite FKs this most often means the
      // parent belongs to someone else, which is a permission problem wearing a
      // constraint's clothes.
      '23503' => const NotFoundFailure('That budget is no longer available.'),
      // check_violation
      '23514' => ValidationFailure(_checkMessage(error), cause: error),
      // not_null_violation
      '23502' => const ValidationFailure('Something required was missing.'),
      // insufficient_privilege — RLS refused it
      '42501' => const AuthFailure('You do not have access to that.'),
      // PostgREST: no rows where exactly one was expected
      'PGRST116' => const NotFoundFailure(),
      _ => UnexpectedFailure('Something went wrong. Please try again.', error),
    };
  }

  return UnexpectedFailure('Something went wrong. Please try again.', error);
}

/// The http package's `ClientException` is not on this project's import surface,
/// and Supabase wraps transport failures in several shapes besides it. Matching
/// on the rendered message is uglier than a type check but catches all of them,
/// and the cost of a false positive is only a friendlier error message.
bool _looksLikeNetwork(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('network is unreachable');
}

String _authMessage(AuthException error) {
  final raw = error.message.toLowerCase();
  if (raw.contains('expired')) {
    return 'Your session expired. Please sign in again.';
  }
  if (raw.contains('network') || raw.contains('failed host lookup')) {
    return "Couldn't reach the server. Check your connection.";
  }
  return 'Sign-in failed. Please try again.';
}

String _uniqueMessage(PostgrestException error) {
  final detail = '${error.message} ${error.details ?? ''}';
  if (detail.contains('monthly_budgets_one_per_month')) {
    return 'A plan already exists for that month.';
  }
  if (detail.contains('budget_categories_one_per_budget')) {
    return "That category is already in this month's plan.";
  }
  return 'That already exists.';
}

String _checkMessage(PostgrestException error) {
  final detail = '${error.message} ${error.details ?? ''}';
  if (detail.contains('savings_within_income')) {
    return 'Savings cannot be more than your income.';
  }
  if (detail.contains('period_is_month_start')) {
    return 'That month is not valid.';
  }
  if (detail.contains('amount_minor')) {
    return 'Enter an amount greater than zero.';
  }
  return 'Those values are not valid.';
}
