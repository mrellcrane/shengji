// Results passed between the HTTP layer, the Hub and the GameRooms (plain data, so they cross
// Durable Object RPC unchanged). A failure becomes `{"error": code, "message": ..., ...details}`.

export interface Failure {
  ok: false;
  status: number;
  code: string;
  /** A short learner-facing sentence. */
  message: string;
  /** Extra fields for the error body (e.g. the fresh game, view and version for "stale"). */
  details?: Record<string, unknown>;
  /** For 429: seconds until trying again makes sense (the retry-after header; default 60). */
  retryAfter?: number;
}

export type Result<T> = { ok: true; value: T } | Failure;

export function ok<T>(value: T): { ok: true; value: T } {
  return { ok: true, value };
}

export function fail(status: number, code: string, message: string, details?: Record<string, unknown>): Failure {
  return details === undefined ? { ok: false, status, code, message } : { ok: false, status, code, message, details };
}

export const NOT_FOUND_GAME = (): Failure => fail(404, "not_found", "That game doesn't exist any more.");
export const NOT_SEATED = (): Failure => fail(403, "not_seated", "You're not playing in this game.");
