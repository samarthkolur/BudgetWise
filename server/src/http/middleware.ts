import crypto from 'crypto';
import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { ApiError, ConflictError, NotOwnedError, NotPermittedError, ValidationError } from './errors';
import { TokenError, TokenService } from '../auth/tokens';

/**
 * Stamps every request with an id, echoed in the response and in any error
 * body. Ported from server/lib/src/http/middleware.dart's `requestId()`.
 */
export function requestId(): RequestHandler {
  return (req: Request, res: Response, next: NextFunction) => {
    const id = randomHex(8);
    req.requestId = id;
    res.setHeader('x-request-id', id);
    next();
  };
}

function randomHex(length: number): string {
  const alphabet = '0123456789abcdef';
  let out = '';
  const bytes = crypto.randomBytes(length);
  for (let i = 0; i < length; i++) {
    out += alphabet[bytes[i] % 16];
  }
  return out;
}

/**
 * Rejects oversized bodies before they are parsed, by declared
 * Content-Length. An expense or a month's budget is a few hundred bytes; a
 * single request without this cap could make the process allocate until it
 * dies, which is a denial of service that costs the sender nothing. Mirrors
 * server/lib/src/http/middleware.dart's `bodyLimit()`. `express.json()` is
 * also configured with the same byte limit as a second check against a
 * sender that lies about Content-Length.
 */
export function bodyLimit(maxBytes = 256 * 1024): RequestHandler {
  return (req: Request, res: Response, next: NextFunction) => {
    const declared = req.headers['content-length'];
    if (declared && Number(declared) > maxBytes) {
      next(new ApiError(413, 'too_large', 'That request is too large.'));
      return;
    }
    next();
  };
}

/**
 * Permissive CORS. Safe here because the API authenticates with a Bearer
 * token rather than a cookie — there is no ambient credential for another
 * origin to ride on, so CSRF is not the risk it would be for a session
 * cookie.
 */
export function cors(): RequestHandler {
  return (req: Request, res: Response, next: NextFunction) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type');
    res.setHeader('Access-Control-Max-Age', '86400');
    if (req.method === 'OPTIONS') {
      res.status(200).end();
      return;
    }
    next();
  };
}

/**
 * Requires a valid access token and attaches `req.principal`.
 *
 * Every route that touches user data sits behind this. The principal it
 * produces is the only accepted source of an owner id — repositories take it
 * from here, never from the request body, which the caller controls.
 */
export function requireAuth(tokens: TokenService): RequestHandler {
  return (req: Request, res: Response, next: NextFunction) => {
    const header = req.headers.authorization;
    if (!header || !header.toLowerCase().startsWith('bearer ')) {
      next(ApiError.unauthorized('Sign in to continue.'));
      return;
    }
    try {
      req.principal = tokens.verifyAccessToken(header.slice(7).trim());
      next();
    } catch (error) {
      next(error);
    }
  };
}

/** The authenticated caller. Only valid inside a requireAuth pipeline. */
export function principalOf(req: Request) {
  if (!req.principal) {
    // Reaching this means a route was mounted outside the auth pipeline — a
    // wiring mistake that would otherwise surface as an unscoped query
    // returning somebody else's data.
    throw new Error('Route is not behind requireAuth');
  }
  return req.principal;
}

/** Wraps an async Express handler so a rejected promise reaches the error middleware. */
export function asyncHandler(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<void>,
): RequestHandler {
  return (req, res, next) => {
    handler(req, res, next).catch(next);
  };
}

/**
 * Catches everything a handler can throw and renders it once. Mirrors
 * server/lib/src/http/errors.dart's errorHandler Middleware exactly,
 * including the 404-not-403 treatment of NotOwnedError.
 */
export function errorHandler(
  onError?: (error: unknown) => void,
): (err: unknown, req: Request, res: Response, next: NextFunction) => void {
  return (err, req, res, _next) => {
    const requestId = req.requestId;
    const body = (code: string, message: string) => ({
      error: code,
      message,
      ...(requestId ? { requestId } : {}),
    });

    if (err instanceof ApiError) {
      res.status(err.status).json(body(err.code, err.message));
      return;
    }
    if (err instanceof NotOwnedError) {
      // Deliberately 404, not 403. See NotOwnedError's doc comment.
      res.status(404).json(body('not_found', 'That is no longer available.'));
      return;
    }
    if (err instanceof TokenError) {
      res.status(401).json(body('unauthorized', err.message));
      return;
    }
    if (err instanceof ValidationError) {
      res.status(400).json(body('bad_request', err.message));
      return;
    }
    if (err instanceof ConflictError) {
      res.status(409).json(body('conflict', err.message));
      return;
    }
    if (err instanceof NotPermittedError) {
      res.status(403).json(body('forbidden', err.message));
      return;
    }
    // Body-parser payload-too-large and malformed-JSON errors.
    const maybe = err as { type?: string; status?: number } | undefined;
    if (maybe?.type === 'entity.too.large' || maybe?.status === 413) {
      res.status(413).json(body('too_large', 'That request is too large.'));
      return;
    }
    if (maybe?.type === 'entity.parse.failed') {
      res.status(400).json(body('bad_request', 'That request could not be read.'));
      return;
    }

    onError?.(err);
    res.status(500).json(body('internal', 'Something went wrong. Please try again.'));
  };
}
