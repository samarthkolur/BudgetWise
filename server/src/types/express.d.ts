import type { Principal } from '../auth/tokens';

declare global {
  namespace Express {
    interface Request {
      principal?: Principal;
      requestId?: string;
    }
  }
}

export {};
