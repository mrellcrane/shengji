// Which live sockets of a game make room for a new one. A phone that loses its network (or is
// put away) often leaves its old socket open on the server until the connection times out, and
// reconnects with a new one; without a per-person cap those piled up until the game's socket
// limit refused everyone. Each person keeps their newest few; the oldest are closed (code
// CLOSE_REPLACED). Eight seats (the biggest table) times the per-person cap stays below the game's
// cap, so a seated player is never refused. Also how a client's close is answered (closeReplyCode).

/** At most this many live sockets per person per game (a phone and a tablet, with room for stale ones). */
export const MAX_SOCKETS_PER_USER = 4;
/** At most this many live sockets per game (a safety limit, never reached by eight seats). */
export const MAX_SOCKETS = 40;
/** Close code for a socket replaced by a newer connection of the same person. */
export const CLOSE_REPLACED = 4001;

export interface OpenSocket {
  userId: string;
  /** Unix ms when it connected. */
  connectedAt: number;
}

/**
 * Indexes (into `open`) of the sockets to close before `userId` connects once more: their oldest
 * beyond MAX_SOCKETS_PER_USER - 1. Null if the game would still be over MAX_SOCKETS.
 */
export function socketsToReplace(open: readonly OpenSocket[], userId: string): number[] | null {
  const mine = open
    .map((socket, index) => ({ socket, index }))
    .filter(({ socket }) => socket.userId === userId)
    .sort((a, b) => a.socket.connectedAt - b.socket.connectedAt || a.index - b.index);
  const excess = Math.max(0, mine.length - (MAX_SOCKETS_PER_USER - 1));
  const close = mine
    .slice(0, excess)
    .map(({ index }) => index)
    .sort((a, b) => a - b);
  if (open.length - close.length >= MAX_SOCKETS) return null;
  return close;
}

/**
 * The code to answer a client's close with: theirs, unless it is one that only reports what
 * happened and may not be sent (1005: the client gave no code; 1006: the connection dropped;
 * 1015: TLS failed), which close() refuses. Answering those with 1000 completes the closing
 * handshake; without an answer the client waited (about 10 seconds) and saw an unclean close.
 */
export function closeReplyCode(code: number): number {
  const sendable = Number.isInteger(code) && code >= 1000 && code <= 4999 && ![1004, 1005, 1006, 1015].includes(code);
  return sendable ? code : 1000;
}
