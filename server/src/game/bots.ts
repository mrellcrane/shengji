// Server bots: the app's bots, ported from Swift (src/bots), deciding from the seat's SeatView exactly
// as the app's bots do (test/bots.parity.test.ts replays the Swift bots' choices). This module fits
// them to the online game:
//
//  - `chooseBotAction(view, level)`: the bot's action from what its seat sees, in the client
//    protocol's terms (a bid's declaration is one of `view.bidding.available`, player 0; a dealer
//    at a table of 5, 7 or 9 calls its friends with the burial, as the app's bots do). It also
//    drives the people in scripts/smoke.ts and the API tests, so they play like bots.
//  - `safeActions(round, seat)`: plain legal moves built from the rules alone, the fallback that
//    online.ts tries (and logs) should the engine ever refuse a bot's choice.

import type { BotLevel } from "../bots/index.ts";
import { decide, declaration, friendCalls } from "../bots/index.ts";
import { ruleFollow } from "../bots/builder.ts";
import { ALL_RANKS, ALL_SUITS, regularFace, tableFriendCount } from "../engine/cards.ts";
import type { Card, Rank } from "../engine/cards.ts";
import { friendCall } from "../engine/friends.ts";
import type { FriendCall } from "../engine/friends.ts";
import { biddingTurn, kittySizeOf, roundTable, turn } from "../engine/round.ts";
import type { Declaration, Round } from "../engine/round.ts";
import type { SeatView } from "../engine/seatview.ts";
import { sortCards } from "../engine/trump.ts";

export type { BotLevel } from "../bots/index.ts";

export function isBotLevel(value: unknown): value is BotLevel {
  return value === "standard" || value === "beginner";
}

export type BotAction =
  | { type: "bid"; declaration: Declaration }
  | { type: "pass" }
  /** `calls`: Finding Friends, the friends called (empty or absent at a table of fixed teams). */
  | { type: "bury"; cards: Card[]; calls?: FriendCall[] }
  | { type: "play"; cards: Card[] };

/**
 * What the bot seeing `view` does now (viewer-relative: a bid's declaration has player 0), or null
 * when the viewer has nothing to do. Bidding uses the declaration logic with
 * `view.bidding.available`; burying and playing use `decide`.
 */
export function chooseBotAction(view: SeatView, level: BotLevel): BotAction | null {
  if (view.phase === "bidding") {
    if (view.bidding === null || view.bidding.turn !== 0) return null;
    const choice = declaration(view, view.bidding.available, level);
    return choice === null ? { type: "pass" } : { type: "bid", declaration: choice };
  }
  const cards = decide(view, level);
  if (cards === null || cards.length === 0) return null;
  if (view.phase !== "burying") return { type: "play", cards };
  const calls = friendCalls(view, cards);
  return calls.length > 0 ? { type: "bury", cards, calls } : { type: "bury", cards };
}

/**
 * Friend calls from the rules alone (Finding Friends), for the safe burial: the first copy of the
 * top cards that are not of the trump rank, aces of each suit first. Always legal; empty at a table
 * of fixed teams.
 */
export function safeCalls(round: Round): FriendCall[] {
  const needed = tableFriendCount(roundTable(round));
  const calls: FriendCall[] = [];
  const ranks = ALL_RANKS.slice().reverse().filter((rank: Rank) => rank !== round.trumpRank);
  for (const rank of ranks) {
    for (const suit of ALL_SUITS) {
      if (calls.length >= needed) return calls;
      calls.push(friendCall(regularFace(rank, suit)));
    }
  }
  return calls;
}

/**
 * Plain legal moves for absolute `seat` from the rules alone (no strategy), in the order to try
 * them: pass a bid; bury the lowest cards in display order (as many as the kitty holds; with
 * Finding Friends calling `safeCalls`); lead the lowest card; follow with the play built straight
 * from the follow rules. Empty when the seat has nothing to do.
 */
export function safeActions(round: Round, seat: number): BotAction[] {
  if (biddingTurn(round) === seat) return [{ type: "pass" }];
  const hand = seat >= 0 && seat < round.hands.length ? round.hands[seat] : [];
  if (round.phase === "burying") {
    if (round.dealer !== seat) return [];
    const cards = sortCards(round.trump, hand).slice(0, kittySizeOf(round));
    const calls = safeCalls(round);
    return [calls.length > 0 ? { type: "bury", cards, calls } : { type: "bury", cards }];
  }
  if (turn(round) !== seat || hand.length === 0) return [];
  if (round.currentTrick.length === 0) return [{ type: "play", cards: sortCards(round.trump, hand).slice(0, 1) }];
  return [{ type: "play", cards: ruleFollow(hand, round.currentTrick[0].cards, round.trump) }];
}
