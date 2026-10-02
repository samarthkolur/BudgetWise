import bcrypt from 'bcryptjs';

/**
 * Password hashing. bcryptjs (pure JS) rather than native bcrypt — this
 * machine has a documented history of native-toolchain pain (see CLAUDE.md
 * "This machine"), so a pure-JS implementation avoids adding another one.
 */
const COST_FACTOR = 12;

export const MIN_PASSWORD_LENGTH = 8;

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, COST_FACTOR);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}

export function isPasswordLongEnough(password: string): boolean {
  return password.length >= MIN_PASSWORD_LENGTH;
}
