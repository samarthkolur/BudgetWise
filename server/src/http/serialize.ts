/**
 * Renders a Prisma row as JSON the client can read: Date -> ISO-8601 string,
 * `userId` stripped (the client already knows who it is, and echoing it
 * invites code that trusts the body's owner instead of the token's).
 */
export function serialize<T extends Record<string, unknown>>(row: T): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(row)) {
    if (key === 'userId') continue;
    out[key] = value instanceof Date ? value.toISOString() : value;
  }
  return out;
}

export function serializeAll<T extends Record<string, unknown>>(rows: T[]): Record<string, unknown>[] {
  return rows.map(serialize);
}
