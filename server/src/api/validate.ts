// Parsing of untrusted request bodies (docs/online-protocol.md). Everything a client sends is
// checked here for type, size and shape before it reaches the Hub or a GameRoom; the game rules
// themselves are checked by the engine.

import { isIdShape } from "../auth/crypto.ts";
import { isCard } from "../engine/cards.ts";
import type { Card, Rank } from "../engine/cards.ts";
import { parseDeclaration } from "../engine/round.ts";
import { isBotLevel } from "../game/bots.ts";
import type { Device, GameRequest, SeatRequest } from "../hub/service.ts";
import type { ActionRequest } from "../room/service.ts";
import { fail, ok } from "./result.ts";
import type { Failure, Result } from "./result.ts";

export const LIMITS = {
  maxBodyBytes: 16 * 1024,
  displayName: 24,
  clubName: 40,
  identityToken: 8192,
  devSecret: 256,
  /** The most cards a hand holds (the dealer while burying). */
  maxCards: 33,
};

export const TARGET_RANKS: readonly Rank[] = [5, 10, 14];

function badRequest(message: string): Failure {
  return fail(400, "bad_request", message);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * A display or club name: whitespace trimmed and collapsed, no control or invisible formatting
 * characters, 1 to `max` characters (code points). With `truncate`, a long name is cut to `max`
 * instead of rejected (names that come from Apple).
 */
export function cleanName(value: unknown, max: number, truncate = false): string | null {
  if (typeof value !== "string" || value.length > 1000) return null;
  // Control and invisible formatting characters are refused (the emoji joiner U+200D is fine).
  if (/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u.test(value.replace(/[\t\n\r\u200d]/g, " "))) return null;
  let name = value.replace(/\s+/gu, " ").trim();
  let chars = Array.from(name);
  if (chars.length > max) {
    if (!truncate) return null;
    chars = chars.slice(0, max);
    name = chars.join("").trim();
  }
  return name.length > 0 ? name : null;
}

function parseCards(value: unknown, max: number): Card[] | null {
  if (!Array.isArray(value) || value.length > max || !value.every(isCard)) return null;
  return value.slice() as Card[];
}

export function parseActionRequest(body: unknown): Result<ActionRequest> {
  if (!isObject(body)) return badRequest("Send {\"version\": n, \"action\": {...}}.");
  const version = body.version;
  if (typeof version !== "number" || !Number.isSafeInteger(version) || version < 0) {
    return badRequest("version must be the game version you last saw.");
  }
  const action = body.action;
  if (!isObject(action) || typeof action.type !== "string") return badRequest("action needs a type.");
  switch (action.type) {
    case "pass":
      return ok({ version, action: { type: "pass" } });
    case "bid": {
      const d = action.declaration;
      if (!isObject(d)) return badRequest("A bid needs a declaration.");
      // Viewer-relative: a bid is always the viewer's own (seat 0).
      if (d.player !== undefined && d.player !== 0) return badRequest("A bid's declaration must be yours (player 0).");
      const declaration = parseDeclaration({ ...d, player: 0, suit: d.suit === null ? undefined : d.suit });
      if (declaration === null) return badRequest("That declaration is not well formed.");
      return ok({ version, action: { type: "bid", declaration } });
    }
    case "bury":
    case "play": {
      const cards = parseCards(action.cards, LIMITS.maxCards);
      if (cards === null) return badRequest("cards must be a list of card ids (0 to 107).");
      return ok({ version, action: { type: action.type, cards } });
    }
    default:
      return badRequest("action.type must be bid, pass, bury or play.");
  }
}

function parseSeat(value: unknown): SeatRequest | null {
  if (!isObject(value)) return null;
  if (typeof value.userId === "string" && value.bot === undefined) {
    return isIdShape(value.userId, "u") ? { userId: value.userId } : null;
  }
  if (isBotLevel(value.bot) && value.userId === undefined) return { bot: value.bot };
  return null;
}

export function parseGameRequest(body: unknown): Result<GameRequest> {
  if (!isObject(body)) return badRequest("Send {\"clubId\", \"seats\", \"targetRank\"}.");
  if (typeof body.clubId !== "string" || !isIdShape(body.clubId, "c")) return badRequest("clubId is not a club id.");
  if (!Array.isArray(body.seats) || body.seats.length !== 4) return badRequest("seats must list exactly four seats.");
  const seats: SeatRequest[] = [];
  for (const value of body.seats) {
    const seat = parseSeat(value);
    if (seat === null) return badRequest("Each seat is {\"userId\": \"u_...\"} or {\"bot\": \"standard\" | \"beginner\"}.");
    seats.push(seat);
  }
  const target = body.targetRank === undefined ? 14 : body.targetRank;
  if (!TARGET_RANKS.includes(target as Rank)) return badRequest("targetRank must be 5, 10 or 14.");
  return ok({ clubId: body.clubId, seats, targetRank: target as Rank });
}

/** APNs device tokens are hex (32 bytes today; Apple allows longer). */
export function isDeviceToken(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-fA-F]{32,200}$/.test(value) && value.length % 2 === 0;
}

export function parseDevice(body: unknown): Result<Device> {
  if (!isObject(body)) return badRequest("Send {\"platform\", \"token\", \"environment\"}.");
  if (body.platform !== "ios") return badRequest("platform must be ios.");
  if (!isDeviceToken(body.token)) return badRequest("token must be the device token in hex.");
  if (body.environment !== "sandbox" && body.environment !== "production") {
    return badRequest("environment must be sandbox or production.");
  }
  return ok({ platform: "ios", token: body.token.toLowerCase(), environment: body.environment });
}
