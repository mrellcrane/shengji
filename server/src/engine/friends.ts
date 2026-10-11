// Finding Friends (找朋友 zhǎo péngyou). Port of ShengjiCore/Sources/ShengjiCore/Engine/Friends.swift.
//
// With an odd number of players (5, 7 or 9) nobody has fixed partners. After burying, the dealer
// calls friends by naming cards, such as "the first A♠" or "the second K♥". Whoever plays that copy
// of the card this round joins the dealer's side, and nobody knows who the friends are until they
// play it. If the dealer (or someone already found) plays it, the dealer's side gains nobody, so it
// plays short-handed.
//
// Wire and storage format (Swift `FriendCall` Codable): `{"face": face index 0...53, "ordinal": n,
// "friend": seat}`. Swift leaves `friend` out until the card has been played; the server writes
// `null` (Swift decodes both). Clients send calls as `{"face", "ordinal"}`.

import { FACE_COUNT, cardDescription, faceOf, rankLabel, rankOf, tableFriendCount } from "./cards.ts";
import type { Card, Face, Rank, TableSize } from "./cards.ts";
import { normalizeSeat } from "./rules.ts";

/** A friend the dealer calls (Swift `FriendCall`). */
export interface FriendCall {
  /**
   * The card named: any suited card that is not of the trump rank (jokers and trump-rank cards
   * can't be called), as its face index 0...51.
   */
  face: Face;
  /** Which copy counts: 1 = the first one played this round, 2 = the second, up to the number of decks. */
  ordinal: number;
  /** The seat that played that copy, once it has been played (null until then). */
  friend: number | null;
}

/** A call of `face` (a face index) before anyone has played it. */
export function friendCall(face: Face, ordinal = 1): FriendCall {
  return { face, ordinal, friend: null };
}

/** The same call before anyone has played the card (Swift `unfound`). */
export function unfoundCall(call: FriendCall): FriendCall {
  return { face: call.face, ordinal: call.ordinal, friend: null };
}

/** A copy of the call (calls are values in Swift). */
export function copyCall(call: FriendCall): FriendCall {
  return { face: call.face, ordinal: call.ordinal, friend: call.friend };
}

/** True once the called copy has been played. */
export function isFound(call: FriendCall): boolean {
  return call.friend !== null;
}

/** "first", "second", ... for an ordinal (Swift `FriendCall.ordinalWord`). */
export function ordinalWord(n: number): string {
  switch (n) {
    case 1:
      return "first";
    case 2:
      return "second";
    case 3:
      return "third";
    case 4:
      return "fourth";
    case 5:
      return "fifth";
    default:
      return `#${n}`;
  }
}

/** e.g. "the first A♠" (Swift `FriendCall.description`). */
export function friendCallDescription(call: FriendCall): string {
  return `the ${ordinalWord(call.ordinal)} ${cardDescription(call.face)}`;
}

/** "the first A♠ and the second K♥" (Swift `spokenList`). */
export function friendCallList(calls: readonly FriendCall[]): string {
  const names = calls.map(friendCallDescription);
  switch (names.length) {
    case 0:
      return "no friends";
    case 1:
      return names[0];
    case 2:
      return `${names[0]} and ${names[1]}`;
    default:
      return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
  }
}

/**
 * Why the dealer can't make `calls` at `table` when `trumpRank` is trump, or null when they can:
 * exactly `tableFriendCount(table)` calls, each a suited card that is not of the trump rank, a copy
 * that exists (1 up to the number of decks), and no call made twice. Swift `FriendCall.problem`.
 */
export function friendCallProblem(calls: readonly FriendCall[], table: TableSize, trumpRank: Rank): string | null {
  const needed = tableFriendCount(table);
  if (needed <= 0) {
    return calls.length === 0 ? null : "Only a table with an odd number of players calls friends.";
  }
  if (calls.length !== needed) {
    const friends = needed === 1 ? "1 friend" : `${needed} friends`;
    return `Call exactly ${friends} (you called ${calls.length}).`;
  }
  const seen = new Set<string>();
  const decks = Math.max(table.decks, 1);
  for (const call of calls) {
    const rank = rankOf(call.face);
    if (rank === null) return "Jokers can't be called: pick a suited card.";
    if (rank === trumpRank) return `Trump-rank cards (${rankLabel(rank)}) can't be called: pick another card.`;
    if (!(call.ordinal >= 1 && call.ordinal <= decks)) {
      return (
        `With ${table.decks} decks there are only ${table.decks} copies of each card: ` +
        `call one of the first ${table.decks}.`
      );
    }
    const key = `${call.face}:${call.ordinal}`;
    if (seen.has(key)) {
      return `You called ${friendCallDescription(unfoundCall(call))} twice: pick a different card or copy.`;
    }
    seen.add(key);
  }
  return null;
}

/**
 * Calls with any friend found by `player`'s play of `cards`, given every card played before it this
 * round: a call is found when this play holds the copy that reaches its ordinal. Returns new call
 * objects (the inputs are not changed). Swift `[FriendCall].noting(_:by:playedBefore:)`.
 */
export function notingFriends(
  calls: readonly FriendCall[],
  cards: readonly Card[],
  player: number,
  playedBefore: readonly Card[],
): FriendCall[] {
  return calls.map((call) => {
    if (call.friend !== null) return copyCall(call);
    let before = 0;
    for (const card of playedBefore) if (faceOf(card) === call.face) before++;
    let now = 0;
    for (const card of cards) if (faceOf(card) === call.face) now++;
    if (!(before < call.ordinal && before + now >= call.ordinal)) return copyCall(call);
    return { face: call.face, ordinal: call.ordinal, friend: player };
  });
}

/** True if both lists hold the same calls in the same order (Swift `==`). */
export function sameCalls(a: readonly FriendCall[], b: readonly FriendCall[]): boolean {
  return (
    a.length === b.length &&
    a.every((call, i) => call.face === b[i].face && call.ordinal === b[i].ordinal && call.friend === b[i].friend)
  );
}

/** The same call with the friend's seat seen from `viewer` (who becomes seat 0) at a table of `players`. */
export function rotateFriendCall(call: FriendCall, viewer: number, players: number): FriendCall {
  return {
    face: call.face,
    ordinal: call.ordinal,
    friend: call.friend === null ? null : normalizeSeat(call.friend - viewer, players),
  };
}

/**
 * Parses untrusted friend calls (a client message): a list of `{"face", "ordinal"}` with an integer
 * face index 0...53 and an integer ordinal, returned unfound (a `friend` field is ignored, as Swift's
 * `bury` keeps `unfound` calls). Null when malformed or longer than `max`. Whether the calls are
 * allowed is `friendCallProblem`'s job: jokers, trump-rank cards and copies that don't exist are
 * well formed.
 */
export function parseFriendCalls(value: unknown, max = 16): FriendCall[] | null {
  if (!Array.isArray(value) || value.length > max) return null;
  const calls: FriendCall[] = [];
  for (const item of value) {
    if (typeof item !== "object" || item === null || Array.isArray(item)) return null;
    const v = item as Record<string, unknown>;
    if (typeof v.face !== "number" || !Number.isInteger(v.face) || v.face < 0 || v.face >= FACE_COUNT) return null;
    if (typeof v.ordinal !== "number" || !Number.isSafeInteger(v.ordinal)) return null;
    calls.push({ face: v.face, ordinal: v.ordinal, friend: null });
  }
  return calls;
}
