// Burying the kitty (dealer only): exactly 8 cards from the dealer's hand. Port of
// ShengjiCore/Sources/ShengjiCore/Bots/BotBurying.swift, choices only.
//  - Standard: never trumps unless there are fewer than 8 other cards; avoids aces, pairs and point
//    cards; prefers emptying short plain suits entirely (a void lets you trump that suit later);
//    otherwise the lowest singles.
//  - Beginner: the 8 lowest cards that aren't trumps.

import { ALL_SUITS, cardPoints, faceOf } from "../engine/cards.ts";
import type { Card } from "../engine/cards.ts";
import { KITTY_SIZE } from "../engine/round.ts";
import type { SeatView } from "../engine/seatview.ts";
import { TOP_PLAIN_STRENGTH, groupOf, isTrump, strength } from "../engine/trump.ts";
import type { SuitGroup } from "../engine/trump.ts";
import type { BotLevel } from "./bot.ts";
import { CostModel, cheapest as cheapestByCost } from "./builder.ts";
import { BotTable, DEFAULT_TUNING } from "./table.ts";
import type { BotTuning } from "./table.ts";

/** The 8 cards to bury, or null unless the viewer is the dealer, burying, with at least 8 cards. */
export function buryDecision(view: SeatView, level: BotLevel, tuning: Readonly<BotTuning> = DEFAULT_TUNING): Card[] | null {
  if (view.phase !== "burying" || view.dealer !== 0 || view.hand.length < KITTY_SIZE) return null;
  const table = new BotTable(view, tuning);
  return level === "beginner" ? beginner(table) : standard(table);
}

/** How much it hurts to bury a card (lower = bury first). */
function cost(card: Card, table: BotTable): number {
  const level = strength(table.trump, card);
  let value: number;
  if (isTrump(table.trump, card)) {
    value = 1000 + 10 * level;
  } else {
    value = 2 * level;
    if (level >= TOP_PLAIN_STRENGTH) value += 40;
  }
  value += 4 * cardPoints(card);
  if (table.pairFaces.has(faceOf(card))) value += 40;
  if (table.tractorFaces.has(faceOf(card))) value += 20;
  return value;
}

function cheapest(cards: readonly Card[], count: number, table: BotTable): Card[] {
  if (count <= 0) return [];
  const scored = cards.map((card) => ({ card, cost: cost(card, table), key: table.order.key(card) }));
  scored.sort((a, b) => a.cost - b.cost || a.key - b.key || a.card - b.card);
  return scored.slice(0, count).map((s) => s.card);
}

function standard(table: BotTable): Card[] {
  const size = KITTY_SIZE;
  const suits = ALL_SUITS.filter((suit) => table.cards(suit).length > 0);
  const trumpCount = table.trumps.length;
  // A void is only worth much with trumps to ruff with.
  const voidBonus = trumpCount >= 8 ? 30 : trumpCount >= 5 ? 18 : 6;

  let best: { cards: Card[]; score: number } | null = null;
  for (let mask = 0; mask < 1 << suits.length; mask++) {
    const voided = new Set<SuitGroup>();
    const chosen: Card[] = [];
    suits.forEach((suit, index) => {
      if ((mask & (1 << index)) === 0) return;
      voided.add(suit);
      chosen.push(...table.cards(suit));
    });
    if (chosen.length > size) continue;
    const rest = table.hand.filter((card) => !voided.has(groupOf(table.trump, card)));
    const cards = [...chosen, ...cheapest(rest, size - chosen.length, table)];
    if (cards.length !== size) continue;
    let score = -voidBonus * voided.size;
    for (const card of cards) score += cost(card, table);
    if (best !== null && best.score <= score) continue;
    best = { cards, score };
  }
  return best?.cards ?? cheapest(table.hand, size, table);
}

function beginner(table: BotTable): Card[] {
  return cheapestByCost(table.hand, KITTY_SIZE, new CostModel(table, "lowest"));
}
