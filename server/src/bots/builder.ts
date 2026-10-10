// Card costs and legal follows. Port of ShengjiCore/Sources/ShengjiCore/Bots/BotFollowBuilder.swift
// (CostModel, ScoredCard, BotPick, FollowBuilder). Sorts are stable, as in Swift, so ties keep the
// order of their input exactly as the Swift bots do.

import { cardPoints, faceOf, without } from "../engine/cards.ts";
import type { Card, Face } from "../engine/cards.ts";
import { SINGLE, componentsOf, decompose, groupOfCards, pairsIn, shapeCardCount, tractorsIn } from "../engine/combos.ts";
import type { Component } from "../engine/combos.ts";
import { followRequirement, searchTractors, validateFollow } from "../engine/rules.ts";
import type { FollowRequirement } from "../engine/rules.ts";
import { groupOf, isTrump, strength } from "../engine/trump.ts";
import type { SuitGroup, Trump } from "../engine/trump.ts";
import { cardOrder } from "./table.ts";
import type { BotTable } from "./table.ts";

/** What a play is trying to do, which decides how much each card costs to give up. */
export type CostMode =
  /** Losing the trick to an opponent: keep points, pairs and high cards. */
  | "dump"
  /** Partner is winning for now but could be beaten: points are only half lost. */
  | "guarded"
  /** Partner wins: point cards are welcome (without breaking pairs). */
  | "feed"
  /** This seat wins: points come back to the team. */
  | "win"
  /** Plain card value, ignoring points (used to compare plays). */
  | "keep"
  /** Beginner habits: plain cards by rank, trumps last. */
  | "lowest"
  /** Beginner habits: trumps first, then the highest plain cards. */
  | "highest";

/** Card costs for one mode (lower = happier to play it). */
export class CostModel {
  readonly table: BotTable;
  readonly mode: CostMode;

  constructor(table: BotTable, mode: CostMode) {
    this.table = table;
    this.mode = mode;
  }

  /** Cost of playing `card` on its own. */
  loose(card: Card): number {
    const value = this.table.value(card);
    const penalty = this.table.pairPenalty(card);
    const points = cardPoints(card);
    switch (this.mode) {
      case "dump":
        return value + penalty + 4 * points;
      case "guarded":
        return value + penalty + 2 * points;
      case "feed":
        // Points are welcome, but not at the price of breaking a pair.
        return penalty > 0 ? value + penalty : value - 4 * points;
      case "win":
        return value + penalty - 3 * points;
      case "keep":
        return value + penalty;
      case "lowest":
        return this.rawRank(card);
      case "highest":
        return -this.rawRank(card);
    }
  }

  /** Cost of playing both cards of a pair (or every card of a tractor) together. */
  pair(cards: readonly Card[]): number {
    let total = 0;
    for (const card of cards) total += this.unit(card);
    return total;
  }

  /** Cost of a whole play: cards played with their twin count as a pair, the rest on their own. */
  costOf(play: readonly Card[]): number {
    const counts = new Map<Face, number>();
    for (const card of play) counts.set(faceOf(card), (counts.get(faceOf(card)) ?? 0) + 1);
    let total = 0;
    for (const card of play) total += (counts.get(faceOf(card)) ?? 0) >= 2 ? this.unit(card) : this.loose(card);
    return total;
  }

  private unit(card: Card): number {
    const value = this.table.value(card);
    const linked = this.table.tractorFaces.has(faceOf(card)) ? 10 : 0;
    const points = cardPoints(card);
    switch (this.mode) {
      case "dump":
        return value + linked + 4 * points;
      case "guarded":
        return value + linked + 2 * points;
      case "feed":
        return value + linked - 4 * points;
      case "win":
        return value + linked - 3 * points;
      case "keep":
        return value + linked;
      case "lowest":
        return this.rawRank(card);
      case "highest":
        return -this.rawRank(card);
    }
  }

  private rawRank(card: Card): number {
    return (isTrump(this.table.trump, card) ? 100 : 0) + strength(this.table.trump, card);
  }
}

/** The `count` cheapest cards (ties: display order, then id). Swift `BotPick.cheapest`. */
export function cheapest(cards: readonly Card[], count: number, costs: CostModel): Card[] {
  if (count <= 0) return [];
  const scored = cards.map((card) => ({ card, cost: costs.loose(card), key: costs.table.order.key(card) }));
  scored.sort((a, b) => a.cost - b.cost || a.key - b.key || a.card - b.card);
  return scored.slice(0, count).map((s) => s.card);
}

/** Card groups (pairs, tractors) ordered cheapest first (ties: lowest first card). Swift `BotPick.cheapestFirst`. */
export function cheapestFirst(groups: readonly Card[][], costs: CostModel): Card[][] {
  const scored = groups.map((cards) => ({
    cards,
    cost: costs.pair(cards),
    key: cards.length > 0 ? costs.table.order.key(cards[0]) * 200 + cards[0] : 0,
  }));
  scored.sort((a, b) => a.cost - b.cost || a.key - b.key);
  return scored.map((s) => s.cards);
}

/** A legal follow built from the follow rules alone (the bots' safety net, `FollowBuilder.fallback`). */
export function ruleFollow(hand: readonly Card[], lead: readonly Card[], trump: Trump): Card[] {
  return new FollowBuilder(hand, lead, trump).fallback();
}

function sum(values: readonly number[]): number {
  let total = 0;
  for (const value of values) total += value;
  return total;
}

interface TractorSearch {
  best: { cost: number; tractors: Card[][] } | null;
  budget: number;
}

/**
 * Builds legal follows: the cards owed by `followRequirement` first, then filler, each chosen by a
 * cost function. Swift `FollowBuilder`.
 */
export class FollowBuilder {
  readonly trump: Trump;
  readonly lead: Card[];
  readonly count: number;
  readonly ledGroup: SuitGroup;
  /** Own cards of the led group, and the rest (display order). */
  readonly held: Card[];
  readonly others: Card[];
  readonly requirement: FollowRequirement;
  /** The lead's components, largest first. */
  readonly leadComponents: Component[];

  constructor(hand: readonly Card[], lead: readonly Card[], trump: Trump) {
    this.trump = trump;
    this.lead = lead.slice();
    this.count = lead.length;
    const group = groupOfCards(lead, trump) ?? (lead.length > 0 ? groupOf(trump, lead[0]) : "trump");
    this.ledGroup = group;
    const sortedHand = cardOrder(trump).sorted(hand);
    this.held = sortedHand.filter((card) => groupOf(trump, card) === group);
    this.others = sortedHand.filter((card) => groupOf(trump, card) !== group);
    this.requirement =
      this.held.length >= lead.length && lead.length >= 2
        ? followRequirement(lead, this.held, trump)
        : { tractorLengths: [], totalPairs: 0 };
    this.leadComponents =
      lead.length === 1
        ? [{ shape: SINGLE, cards: lead.slice(), group, topStrength: strength(trump, lead[0]) }]
        : decompose(lead, trump);
  }

  get hand(): Card[] {
    return [...this.held, ...this.others];
  }

  isLegal(play: readonly Card[]): boolean {
    return play.length > 0 && validateFollow(play, this.hand, this.lead, this.trump) === null;
  }

  /**
   * The cheapest play under `costs` that meets the follow rules (empty only if the owed tractors
   * could not be found, which the rules guarantee never happens).
   */
  build(costs: CostModel): Card[] {
    const { held, others, count } = this;
    if (held.length <= count) return [...held, ...cheapest(others, count - held.length, costs)];
    if (count === 1) return cheapest(held, 1, costs);
    let pool = held.slice();
    const play: Card[] = [];
    const lengths = this.requirement.tractorLengths.slice().sort((a, b) => b - a);
    if (lengths.length > 0) {
      const tractors = this.cheapestTractors(pool, lengths, costs);
      if (tractors === null) return [];
      for (const tractor of tractors) {
        play.push(...tractor);
        pool = without(pool, tractor);
      }
    }
    let owed = this.requirement.totalPairs - sum(lengths);
    if (owed > 0) {
      for (const pair of cheapestFirst(pairsIn(pool, this.trump), costs)) {
        if (owed <= 0) continue;
        play.push(...pair);
        pool = without(pool, pair);
        owed -= 1;
      }
    }
    play.push(...cheapest(pool, count - play.length, costs));
    return play;
  }

  /** Plays of the led group that copy a single-component lead (the only in-suit plays that can win). */
  inSuitShapes(): Card[][] {
    const { held, count } = this;
    if (held.length === 0) return [];
    if (held.length <= count) return held.length === count ? [held.slice()] : [];
    if (this.leadComponents.length !== 1) return [];
    const shape = this.leadComponents[0].shape;
    const plays: Card[][] = [];
    for (const component of componentsOf(shape, held, this.trump)) {
      // Any single or pair of the led group answers a single or pair lead; check bigger shapes.
      if (shapeCardCount(shape) <= 2 || this.isLegal(component.cards)) plays.push(component.cards);
    }
    return plays;
  }

  /** All-trump plays copying the lead's structure, one per choice of the key component (out of a led plain suit). */
  ruffs(costs: CostModel): Card[][] {
    if (this.held.length > 0 || this.ledGroup === "trump") return [];
    const trumps = this.others.filter((card) => isTrump(this.trump, card));
    if (trumps.length < this.count) return [];
    if (this.leadComponents.length === 0) return [];
    const key = this.leadComponents[0];
    const plays: Card[][] = [];
    for (const option of componentsOf(key.shape, trumps, this.trump)) {
      const play = this.completeRuff(option.cards, trumps, this.leadComponents.slice(1), costs);
      if (play !== null) plays.push(play);
    }
    return plays;
  }

  private completeRuff(start: readonly Card[], trumps: readonly Card[], rest: readonly Component[], costs: CostModel): Card[] | null {
    let pool = without(trumps, start);
    const play = start.slice();
    for (const component of rest) {
      if (component.shape.type === "single") continue;
      const options = componentsOf(component.shape, pool, this.trump).map((c) => c.cards);
      const pick = cheapestFirst(options, costs)[0];
      if (pick === undefined) return null;
      play.push(...pick);
      pool = without(pool, pick);
    }
    play.push(...cheapest(pool, this.count - play.length, costs));
    return play.length === this.count ? play : null;
  }

  /** A legal follow built straight from the rules with no cost function: the safety net. */
  fallback(): Card[] {
    const { held, others, count } = this;
    if (held.length <= count) return [...held, ...others.slice(0, count - held.length)];
    if (count <= 1) return held.slice(0, 1);
    let pool = held.slice();
    const play: Card[] = [];
    let found: Card[][] = [];
    const lengths = this.requirement.tractorLengths.slice().sort((a, b) => b - a);
    searchTractors(pool, lengths, 0, this.trump, [], (_, chosen) => {
      found = chosen.slice();
      return true;
    });
    for (const tractor of found) {
      play.push(...tractor);
      pool = without(pool, tractor);
    }
    let pairs = sum(lengths);
    for (const pair of pairsIn(pool, this.trump)) {
      if (pairs >= this.requirement.totalPairs) continue;
      play.push(...pair);
      pool = without(pool, pair);
      pairs += 1;
    }
    play.push(...pool.slice(0, Math.max(0, count - play.length)));
    return play;
  }

  // MARK: Tractor choice

  /** The cheapest set of disjoint tractors with the given lengths (bounded search). */
  private cheapestTractors(cards: readonly Card[], lengths: readonly number[], costs: CostModel): Card[][] | null {
    const search: TractorSearch = { best: null, budget: 300 };
    this.searchTractors(cards, lengths, 0, [], 0, costs, search);
    if (search.best !== null) return search.best.tractors;
    // Budget ran out before a full set was found: take the first set the rules engine finds.
    let first: Card[][] | null = null;
    searchTractors(cards, lengths, 0, this.trump, [], (_, chosen) => {
      first = chosen.slice();
      return true;
    });
    return first;
  }

  private searchTractors(
    cards: readonly Card[],
    lengths: readonly number[],
    index: number,
    chosen: Card[][],
    cost: number,
    costs: CostModel,
    search: TractorSearch,
  ): void {
    if (search.budget <= 0) return;
    search.budget -= 1;
    if (index >= lengths.length) {
      if (search.best !== null && search.best.cost <= cost) return;
      search.best = { cost, tractors: chosen };
      return;
    }
    for (const tractor of tractorsIn(cards, lengths[index], this.trump)) {
      this.searchTractors(without(cards, tractor), lengths, index + 1, [...chosen, tractor], cost + costs.pair(tractor), costs, search);
    }
  }
}
