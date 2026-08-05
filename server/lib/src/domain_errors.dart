/// Failures the repositories raise, in terms the HTTP layer can map.
///
/// Deliberately not `ArgumentError` or `StateError`. Those are subclasses of
/// `Error`, which Dart reserves for programmer mistakes that should crash —
/// catching them for control flow means a genuine bug (a null dereference, a
/// bad cast) gets quietly rendered as a 400 and returned to the user as though
/// they had typed something wrong.
///
/// These are `Exception`s because they describe things a caller can legitimately
/// do wrong and recover from.
sealed class DomainException implements Exception {
  const DomainException(this.message);
  final String message;

  @override
  String toString() => 'DomainException: $message';
}

/// The input was not acceptable — 400.
class ValidationException extends DomainException {
  const ValidationException(super.message);
}

/// The request conflicts with what already exists — 409.
class ConflictException extends DomainException {
  const ConflictException(super.message);
}

/// The action is not permitted in the account's current state — 403.
///
/// Used for the investing gate, where the refusal is about what the user has
/// earned rather than about who they are.
class NotPermittedException extends DomainException {
  const NotPermittedException(super.message);
}
