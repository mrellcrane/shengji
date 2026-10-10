// The bots: a port of ShengjiCore/Sources/ShengjiCore/Bots (Bot.swift), so online games with bots
// play exactly like the app's bots (test/bots.parity.test.ts replays the Swift bots' choices).
//
// Every decision is made from a SeatView alone, the visible-state model the server sends to the
// seat: the viewer is seat 0, the partner seat 2. Only the choices are ported; the learner-facing
// texts (reason, nudge, principle, concept) stay in the app. The bots are deterministic: there is
// no randomness, and ties are broken exactly as in Swift (stable sorts over the same orders).

import type { Card } from "../engine/cards.ts";
import type { Declaration } from "../engine/round.ts";
import type { SeatView } from "../engine/seatview.ts";
import { beginnerPlay } from "./beginner.ts";
import { buryDecision } from "./burying.ts";
import { chooseDeclaration } from "./declaring.ts";
import { standardFollow } from "./follow.ts";
import { standardLead } from "./lead.ts";
import { BotTable, DEFAULT_TUNING } from "./table.ts";
import type { BotTuning } from "./table.ts";

/** Swift `BotLevel`. */
export type BotLevel = "standard" | "beginner";

/**
 * What the viewer (seat 0) should do now: the 8 cards to bury when they are the dealer in phase
 * "burying", or a legal lead or follow in phase "playing" on their turn (throws only when guaranteed
 * against the unseen cards). Null when the viewer has nothing to do. Swift `Bot.decide(view:)`.
 */
export function decide(view: SeatView, level: BotLevel, tuning: Readonly<BotTuning> = DEFAULT_TUNING): Card[] | null {
  if (view.phase === "burying") return cardsToBury(view, level, tuning);
  if (view.phase !== "playing" || view.turn !== 0 || view.hand.length === 0) return null;
  const table = new BotTable(view, tuning);
  if (level === "beginner") return beginnerPlay(table);
  return table.isLeading ? standardLead(table) : standardFollow(table);
}

/**
 * Phase "burying" with the viewer as dealer (the hand includes the kitty): exactly 8 cards from the
 * hand to bury. Null otherwise. Swift `Bot.cardsToBury(view:)`.
 */
export function cardsToBury(view: SeatView, level: BotLevel, tuning: Readonly<BotTuning> = DEFAULT_TUNING): Card[] | null {
  return buryDecision(view, level, tuning);
}

/**
 * Declaring, offline while dealing (`available` = `availableDeclarations` for the viewer) or online
 * while bidding (`view.bidding.available`). One of `available` (with player 0) or null to pass.
 * Never overrides the partner. Swift `Bot.declaration(view:available:)`.
 */
export function declaration(
  view: SeatView,
  available: readonly Declaration[],
  level: BotLevel,
  tuning: Readonly<BotTuning> = DEFAULT_TUNING,
): Declaration | null {
  return chooseDeclaration(view, available, level, tuning);
}
