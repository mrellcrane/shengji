// Beginner-level play, legal and simple. Port of ShengjiCore/Sources/ShengjiCore/Bots/BotBeginner.swift
// (BeginnerPlay), choices only.
//  - Leads the lowest card of its longest plain suit (the lowest trump if it has no plain cards).
//  - Follows with its lowest legal cards, unless its highest legal play would win the trick right now.

import { ALL_SUITS } from "../engine/cards.ts";
import type { Card } from "../engine/cards.ts";
import { winningIndex } from "../engine/rules.ts";
import { CostModel, FollowBuilder } from "./builder.ts";
import { leadCheck } from "./lead.ts";
import { noteFallback } from "./table.ts";
import type { BotTable } from "./table.ts";

/** The beginner bot's lead or follow. */
export function beginnerPlay(table: BotTable): Card[] {
  return table.isLeading ? lead(table) : follow(table);
}

function lead(table: BotTable): Card[] {
  let longest: Card[] = [];
  for (const suit of ALL_SUITS) {
    const mine = table.cards(suit);
    if (mine.length > longest.length) longest = mine;
  }
  if (longest.length > 0) return leadCheck([longest[0]], table);
  if (table.hand.length === 0) return [];
  return leadCheck([table.hand[0]], table);
}

function follow(table: BotTable): Card[] {
  const trick = table.view.currentTrick;
  const builder = new FollowBuilder(table.hand, trick.length > 0 ? trick[0].cards : [], table.trump);
  const high = builder.build(new CostModel(table, "highest"));
  if (builder.isLegal(high) && winningIndex([...trick, { player: table.seat, cards: high }], table.trump) === trick.length) {
    return high;
  }
  let low = builder.build(new CostModel(table, "lowest"));
  if (!builder.isLegal(low)) {
    noteFallback();
    low = builder.fallback();
  }
  return low;
}
