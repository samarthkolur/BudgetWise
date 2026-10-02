/**
 * Server configuration, read from the process environment.
 *
 * Fails loudly at startup rather than lazily on first request. A server that
 * boots without a signing secret and only fails when someone tries to sign in
 * is a server that looks healthy while being useless. See CLAUDE.md
 * non-negotiable rule #4: MONGO_URI/JWT_SECRET (now DATABASE_URL/JWT_SECRET)
 * never leave the server.
 */
export class ConfigError extends Error {}

export interface Env {
  databaseUrl: string;
  jwtSecret: string;
  port: number;
  accessTokenMinutes: number;
  refreshTokenDays: number;
}

export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const databaseUrl = (source.DATABASE_URL ?? '').trim();
  const jwtSecret = (source.JWT_SECRET ?? '').trim();

  const missing: string[] = [];
  if (!databaseUrl) missing.push('DATABASE_URL');
  if (!jwtSecret) missing.push('JWT_SECRET');
  if (missing.length > 0) {
    throw new ConfigError(
      `Missing required environment variables: ${missing.join(', ')}.\n` +
        'See server/.env.example.',
    );
  }

  // 32 bytes is the floor for HS256 to be worth doing. A short secret is a
  // brute-forceable one, and this token is the only thing standing between a
  // request and someone else's financial history.
  if (jwtSecret.length < 32) {
    throw new ConfigError(
      `JWT_SECRET must be at least 32 characters (got ${jwtSecret.length}). ` +
        'Generate one with: openssl rand -base64 48',
    );
  }

  const port = parseIntOr(source.PORT, 8080);
  const accessTokenMinutes = parseIntOr(source.ACCESS_TOKEN_MINUTES, 60);
  const refreshTokenDays = parseIntOr(source.REFRESH_TOKEN_DAYS, 60);

  return { databaseUrl, jwtSecret, port, accessTokenMinutes, refreshTokenDays };
}

function parseIntOr(value: string | undefined, fallback: number): number {
  if (value === undefined || value.trim() === '') return fallback;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}
