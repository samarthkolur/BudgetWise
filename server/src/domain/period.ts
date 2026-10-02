/**
 * A budget month. Ported from
 * packages/budgetwise_domain/lib/src/period.dart.
 *
 * Every month-scoped row is keyed by the first day of its month. This is the
 * only place allowed to build that value, which is what keeps "which month is
 * this in" from being answered three different ways in three different
 * files.
 *
 * Mirrors the Dart version's `Period.current()`, which uses plain
 * `DateTime.now()` — no timezone handling beyond the server's own local
 * clock, exactly as specified.
 */
export class Period implements Comparable {
  readonly year: number;
  readonly month: number; // 1-12

  constructor(year: number, month: number) {
    // Normalise out-of-range months so Period(2026, 13) is January 2027
    // rather than silently producing an invalid period.
    const zeroBased = month - 1;
    const y = year + Math.floor(zeroBased / 12);
    const m = ((zeroBased % 12) + 12) % 12;
    this.year = y;
    this.month = m + 1;
  }

  static fromDate(date: Date): Period {
    return new Period(date.getFullYear(), date.getMonth() + 1);
  }

  static current(now: Date = new Date()): Period {
    return Period.fromDate(now);
  }

  /** Parses a `YYYY-MM-DD` (or any Date-parseable) period string. */
  static parse(value: string): Period {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      throw new Error(`Invalid period: ${value}`);
    }
    // Parse year/month from the string directly when it looks like
    // YYYY-MM-DD, to avoid UTC/local timezone shifting the day near
    // midnight. Falls back to the parsed Date's UTC fields otherwise.
    const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
    if (match) {
      return new Period(Number(match[1]), Number(match[2]));
    }
    return new Period(parsed.getUTCFullYear(), parsed.getUTCMonth() + 1);
  }

  /** The value stored in a `period date` column: `YYYY-MM-01`. */
  get isoDate(): string {
    const mm = String(this.month).padStart(2, '0');
    return `${this.year}-${mm}-01`;
  }

  /** A JS Date at UTC midnight of the first day — what Prisma expects for a `@db.Date` column. */
  toDate(): Date {
    return new Date(Date.UTC(this.year, this.month - 1, 1));
  }

  get next(): Period {
    return new Period(this.year, this.month + 1);
  }

  get previous(): Period {
    return new Period(this.year, this.month - 1);
  }

  isBefore(other: Period): boolean {
    return this.year < other.year || (this.year === other.year && this.month < other.month);
  }

  isAfter(other: Period): boolean {
    return other.isBefore(this);
  }

  equals(other: Period): boolean {
    return this.year === other.year && this.month === other.month;
  }

  compareTo(other: Period): number {
    return this.year !== other.year ? this.year - other.year : this.month - other.month;
  }

  toString(): string {
    return `Period(${this.isoDate})`;
  }
}

interface Comparable {
  compareTo(other: Period): number;
}
