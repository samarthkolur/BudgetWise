/**
 * Error mapping. Ported from server/lib/src/http/errors.dart and
 * server/lib/src/domain_errors.dart.
 *
 * Route handlers throw; they never build an error body themselves. That
 * keeps the status code for a given failure identical everywhere, which is
 * what lets the client branch on it.
 *
 * Response body shape: `{ error, message, requestId? }`. Stack traces and
 * driver messages are logged, never sent.
 */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }

  static badRequest(message: string): ApiError {
    return new ApiError(400, 'bad_request', message);
  }

  static unauthorized(message: string): ApiError {
    return new ApiError(401, 'unauthorized', message);
  }

  static notFound(message = 'That is no longer available.'): ApiError {
    return new ApiError(404, 'not_found', message);
  }

  static conflict(message: string): ApiError {
    return new ApiError(409, 'conflict', message);
  }

  static forbidden(message: string): ApiError {
    return new ApiError(403, 'forbidden', message);
  }
}

/**
 * Raised when a request references a parent (e.g. a budgetId) that exists
 * but belongs to someone else. Always maps to 404, never 403 — "that exists
 * but isn't yours" confirms the id is real, which is a slow enumeration
 * oracle. This is a deliberate, non-negotiable choice carried over from the
 * Dart version.
 */
export class NotOwnedError extends Error {
  readonly what: string;
  constructor(what: string) {
    super(`NotOwnedError(${what})`);
    this.what = what;
  }
}

/** The input was not acceptable — 400. */
export class ValidationError extends Error {}

/** The request conflicts with what already exists — 409. */
export class ConflictError extends Error {}

/**
 * The action is not permitted in the account's current state — 403. Used
 * only for the investing gate: the refusal is about what the account has
 * earned, not who they are.
 */
export class NotPermittedError extends Error {}
