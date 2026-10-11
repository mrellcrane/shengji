// Server bots: the app's bots, ported from Swift (src/bots), deciding from the seat's SeatView exactly
// as the app's bots do (test/bots.parity.test.ts replays the Swift bots' choices). This module fits
// them to the online game:
//
//  - `chooseBotAction(view, level)`: the bot's action from what its seat sees, in the client
//    protocol's terms (a bid's declaration is one of `view.bidding.available`, player 0). It also
//    drives the people in scripts/smoke.ts and the API tests, so they play like bots.
//  - `safeActions(round, seat)`: plain legal moves built from the rules alone, the fallback that
//    online.ts tries (and logs) should the engine ever refuse a bot's choice.

import type { BotLevel } from "../bots/index.ts";
import { decide, declaration } from "../bots/index.ts";
import { ruleFollow } from "../bots/builder.ts";
import type { Card } from "../engine/cards.ts";
import { biddingTurn, kittySizeOf, turn } from "../engine/round.ts";
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
  | { type: "bury"; cards: Card[] }
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
  return view.phase === "burying" ? { type: "bury", cards } : { type: "play", cards };
}

/**
 * Plain legal moves for absolute `seat` from the rules alone (no strategy), in the order to try
 * them: pass a bid; bury the lowest cards in display order (as many as the kitty holds); lead the
 * lowest card; follow with the play built straight from the follow rules. Empty when the seat has
 * nothing to do.
 */
export function safeActions(round: Round, seat: number): BotAction[] {
  if (biddingTurn(round) === seat) return [{ type: "pass" }];
  const hand = seat >= 0 && seat < round.hands.length ? round.hands[seat] : [];
  if (round.phase === "burying") {
    return round.dealer === seat ? [{ type: "bury", cards: sortCards(round.trump, hand).slice(0, kittySizeOf(round)) }] : [];
  }
  if (turn(round) !== seat || hand.length === 0) return [];
  if (round.currentTrick.length === 0) return [{ type: "play", cards: sortCards(round.trump, hand).slice(0, 1) }];
  return [{ type: "play", cards: ruleFollow(hand, round.currentTrick[0].cards, round.trump) }];
}
