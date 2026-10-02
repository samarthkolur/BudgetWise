import { Router } from 'express';
import type { PrismaClient, User } from '@prisma/client';
import { ApiError, ConflictError } from '../http/errors';
import { asyncHandler } from '../http/middleware';
import { TokenService } from '../auth/tokens';
import { hashPassword, isPasswordLongEnough, verifyPassword } from '../auth/passwords';

/**
 * Sign-up, login, refresh and sign-out. Ported from
 * server/lib/src/routes/auth_routes.dart, with Google sign-in replaced by
 * email/password per the owner's explicit stack decision (see CLAUDE.md).
 *
 * These are the only routes reachable without a session.
 */
export function authRoutes(prisma: PrismaClient, tokens: TokenService): Router {
  const router = Router();

  router.post(
    '/signup',
    asyncHandler(async (req, res) => {
      const body = req.body ?? {};
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
      const password = typeof body.password === 'string' ? body.password : '';
      const displayName = typeof body.displayName === 'string' ? body.displayName : null;

      if (!email.includes('@')) {
        throw ApiError.badRequest('Enter a valid email address.');
      }
      if (!isPasswordLongEnough(password)) {
        throw ApiError.badRequest('Password must be at least 8 characters.');
      }

      const existing = await prisma.user.findUnique({ where: { email } });
      if (existing) {
        throw new ConflictError('An account with that email already exists.');
      }

      const passwordHash = await hashPassword(password);
      const user = await prisma.user.create({
        data: {
          email,
          passwordHash,
          displayName,
          currency: 'INR',
          locale: 'en_IN',
          onboardingCompletedAt: null,
        },
      });

      const pair = await tokens.issue(user.id, user.email);
      res.status(201).json({ ...pair, user: publicUser(user) });
    }),
  );

  router.post(
    '/login',
    asyncHandler(async (req, res) => {
      const body = req.body ?? {};
      const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
      const password = typeof body.password === 'string' ? body.password : '';

      const genericFailure = () => ApiError.unauthorized('Incorrect email or password.');

      const user = await prisma.user.findUnique({ where: { email } });
      if (!user) throw genericFailure();

      const valid = await verifyPassword(password, user.passwordHash);
      if (!valid) throw genericFailure();

      const updated = await prisma.user.update({
        where: { id: user.id },
        data: { lastSignInAt: new Date() },
      });

      const pair = await tokens.issue(updated.id, updated.email);
      res.status(200).json({ ...pair, user: publicUser(updated) });
    }),
  );

  router.post(
    '/refresh',
    asyncHandler(async (req, res) => {
      const body = req.body ?? {};
      const refreshToken = typeof body.refreshToken === 'string' ? body.refreshToken : '';
      if (!refreshToken) {
        throw ApiError.badRequest('No refresh token supplied.');
      }

      // Rotates: the old token dies here whether or not this succeeds.
      const { userId } = await tokens.rotateRefreshToken(refreshToken);

      // Email is re-derived from the stored User row, never from the request.
      const user = await prisma.user.findUnique({ where: { id: userId } });
      if (!user) {
        throw ApiError.unauthorized('Account not found.');
      }

      const pair = await tokens.issue(user.id, user.email);
      res.status(200).json({ ...pair, user: publicUser(user) });
    }),
  );

  router.post(
    '/sign-out',
    asyncHandler(async (req, res) => {
      const body = req.body ?? {};
      const refreshToken = typeof body.refreshToken === 'string' ? body.refreshToken : '';
      if (refreshToken) {
        await tokens.revoke(refreshToken);
      }
      // Always 204: whether the token existed is not the caller's business,
      // and signing out must never fail in a way that strands someone
      // signed in.
      res.status(204).end();
    }),
  );

  return router;
}

export function publicUser(user: User): Record<string, unknown> {
  return {
    id: user.id,
    email: user.email,
    displayName: user.displayName,
    avatarUrl: user.avatarUrl,
    currency: user.currency,
    locale: user.locale,
    onboardingCompletedAt: user.onboardingCompletedAt ? user.onboardingCompletedAt.toISOString() : null,
    investingUnlockedAt: user.investingUnlockedAt ? user.investingUnlockedAt.toISOString() : null,
  };
}
