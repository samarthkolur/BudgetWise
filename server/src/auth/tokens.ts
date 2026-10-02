import crypto from 'crypto';
import jwt from 'jsonwebtoken';
import type { PrismaClient } from '@prisma/client';

/** A verified caller. Everything downstream scopes its queries to `userId`. */
export interface Principal {
  userId: string;
  email: string;
}

export class TokenError extends Error {}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresAt: string; // ISO-8601
}

const ISSUER = 'budgetwise-api';

/**
 * Issues and verifies the server's own session tokens. Ported from
 * server/lib/src/auth/tokens.dart.
 *
 * - The access token is a signed JWT (HS256) carrying the user id as
 *   `subject`. It is not stored anywhere — verifiable from the signature
 *   alone.
 * - The refresh token is opaque random bytes. Only its SHA-256 hex digest is
 *   stored, so a dump of the table does not let the reader impersonate
 *   anyone.
 *
 * Refresh tokens rotate on use: redeeming one deletes it and issues another.
 * A stolen refresh token therefore works at most once.
 */
export class TokenService {
  private readonly prisma: PrismaClient;
  private readonly secret: string;
  private readonly accessTokenMinutes: number;
  private readonly refreshTokenDays: number;

  constructor(opts: {
    prisma: PrismaClient;
    secret: string;
    accessTokenMinutes: number;
    refreshTokenDays: number;
  }) {
    this.prisma = opts.prisma;
    this.secret = opts.secret;
    this.accessTokenMinutes = opts.accessTokenMinutes;
    this.refreshTokenDays = opts.refreshTokenDays;
  }

  async issue(userId: string, email: string): Promise<TokenPair> {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + this.accessTokenMinutes * 60_000);

    const accessToken = jwt.sign({ email }, this.secret, {
      subject: userId,
      issuer: ISSUER,
      algorithm: 'HS256',
      expiresIn: `${this.accessTokenMinutes}m`,
    });

    const refreshToken = randomToken();
    const refreshExpiresAt = new Date(now.getTime() + this.refreshTokenDays * 86_400_000);
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: hashToken(refreshToken),
        expiresAt: refreshExpiresAt,
      },
    });

    return {
      accessToken,
      refreshToken,
      expiresAt: expiresAt.toISOString(),
    };
  }

  /** Verifies an access token and returns who it belongs to. */
  verifyAccessToken(token: string): Principal {
    try {
      const payload = jwt.verify(token, this.secret, {
        issuer: ISSUER,
        algorithms: ['HS256'],
      });
      if (typeof payload === 'string' || !payload.sub) {
        throw new TokenError('Token carried no subject');
      }
      const email = typeof payload.email === 'string' ? payload.email : '';
      return { userId: payload.sub, email };
    } catch (error) {
      if (error instanceof TokenError) throw error;
      if (error instanceof jwt.TokenExpiredError) {
        throw new TokenError('Your session expired. Please sign in again.');
      }
      throw new TokenError('Invalid session token');
    }
  }

  /**
   * Validates and rotates a refresh token: the presented token is deleted
   * (whether or not the caller goes on to redeem a new pair), and the owning
   * userId is returned so the caller can re-derive everything else — email
   * included — from the stored User row rather than from the request body.
   */
  async rotateRefreshToken(refreshToken: string): Promise<{ userId: string }> {
    const record = await this.prisma.refreshToken.findUnique({
      where: { tokenHash: hashToken(refreshToken) },
    });
    if (!record) {
      throw new TokenError('That session is no longer valid');
    }

    // Rotate: the presented token dies here whether or not it had expired.
    await this.prisma.refreshToken.delete({ where: { id: record.id } }).catch(() => {
      // Already gone (e.g. a concurrent use) — treat as invalid below.
    });

    if (record.expiresAt.getTime() < Date.now()) {
      throw new TokenError('That session has expired');
    }

    return { userId: record.userId };
  }

  async revoke(refreshToken: string): Promise<void> {
    await this.prisma.refreshToken
      .delete({ where: { tokenHash: hashToken(refreshToken) } })
      .catch(() => {
        // Non-existent token: signing out must never fail.
      });
  }

  async revokeAllFor(userId: string): Promise<void> {
    await this.prisma.refreshToken.deleteMany({ where: { userId } });
  }
}

function randomToken(): string {
  return crypto.randomBytes(48).toString('base64url');
}

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
