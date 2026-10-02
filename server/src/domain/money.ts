/**
 * Money helpers. Ported from packages/budgetwise_domain/lib/src/money.ts
 * (Dart). Money is always an integer count of paise — never a float.
 *
 * Only the pieces the server needs are ported: positivity/zero checks and a
 * ratio helper for the emergency-fund calculation. Display formatting stays
 * in the Flutter app.
 */
export function isPositive(minor: number): boolean {
  return minor > 0;
}

export function isZero(minor: number): boolean {
  return minor === 0;
}

/** This amount as a fraction of `totalMinor`. 0 when totalMinor is 0. */
export function ratioOf(minor: number, totalMinor: number): number {
  return totalMinor === 0 ? 0 : minor / totalMinor;
}
