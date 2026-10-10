// Singles, pairs, tractors and the decomposition of a play. Port of Engine/Combination.swift.

import { faceOf, shortText, suitOf } from "./cards.ts";
import type { Card, Face } from "./cards.ts";
import { groupOf, sortCards, sortKey, strength } from "./trump.ts";
import type { SuitGroup, Trump } from "./trump.ts";

/**
 * The basic building blocks of a play, with `pairs` = number of pairs (single 0, pair 1,
 * tractor n >= 2). Same encoding as the parity vectors.
 *  - single: one card
 *  - pair: two identical cards (same face; 2♠ + 2♣ is NOT a pair)
 *  - tractor: n >= 2 pairs of consecutive strength in the same suit group (拖拉机)
 */
export interface ComboShape {
  type: "single" | "pair" | "tractor";
  pairs: number;
}

export const SINGLE: ComboShape = Object.freeze({ type: "single", pairs: 0 }) as ComboShape;
export const PAIR: ComboShape = Object.freeze({ type: "pair", pairs: 1 }) as ComboShape;

export function tractorShape(pairs: number): ComboShape {
  return { type: "tractor", pairs };
}

export function shapeCardCount(shape: ComboShape): number {
  switch (shape.type) {
    case "single":
      return 1;
    case "pair":
      return 2;
    case "tractor":
      return 2 * shape.pairs;
  }
}

export function shapePairCount(shape: ComboShape): number {
  return shape.type === "single" ? 0 : shape.type === "pair" ? 1 : shape.pairs;
}

export function shapesEqual(a: ComboShape, b: ComboShape): boolean {
  return a.type === b.type && (a.type !== "tractor" || a.pairs === b.pairs);
}

/** "single", "pair", "tractor", "tractor of 3 pairs". */
export function shapeName(shape: ComboShape): string {
  switch (shape.type) {
    case "single":
      return "single";
    case "pair":
      return "pair";
    case "tractor":
      return shape.pairs === 2 ? "tractor" : `tractor of ${shape.pairs} pairs`;
  }
}

/** One component of a play: a single, a pair, or a tractor, all from one suit group. */
export interface Component {
  shape: ComboShape;
  /** Cards sorted from lowest to highest strength. */
  cards: Card[];
  group: SuitGroup;
  /** Strength (see `strength`) of the highest card. */
  topStrength: number;
}

// MARK: Grouping helpers

/** The single suit group shared by all cards, or null if empty or mixed. */
export function groupOfCards(cards: readonly Card[], trump: Trump): SuitGroup | null {
  if (cards.length === 0) return null;
  const group = groupOf(trump, cards[0]);
  for (const card of cards) if (groupOf(trump, card) !== group) return null;
  return group;
}

/** Cards of `hand` in the given group (hand order kept). */
export function cardsInGroup(hand: readonly Card[], group: SuitGroup, trump: Trump): Card[] {
  return hand.filter((card) => groupOf(trump, card) === group);
}

/** Cards bucketed by face; each bucket sorted by id. */
function byFace(cards: readonly Card[]): Map<Face, Card[]> {
  const sorted = cards.slice().sort((a, b) => a - b);
  const map = new Map<Face, Card[]>();
  for (const card of sorted) {
    const face = faceOf(card);
    const bucket = map.get(face);
    if (bucket) bucket.push(card);
    else map.set(face, [card]);
  }
  return map;
}

// MARK: Pairs

export function isPair(cards: readonly Card[]): boolean {
  return cards.length === 2 && faceOf(cards[0]) === faceOf(cards[1]) && cards[0] !== cards[1];
}

/** Every pair in `cards` (each face appearing twice), sorted by group then strength ascending. */
export function pairsIn(cards: readonly Card[], trump: Trump): Card[][] {
  const pairs: Card[][] = [];
  for (const bucket of byFace(cards).values()) {
    if (bucket.length >= 2) pairs.push(bucket.slice(0, 2));
  }
  return pairs
    .map((pair) => ({ pair, key: sortKey(trump, pair[0]) }))
    .sort((a, b) => a.key - b.key)
    .map((p) => p.pair);
}

/** Number of distinct pairs available in `cards`. */
export function pairCount(cards: readonly Card[]): number {
  let count = 0;
  for (const bucket of byFace(cards).values()) if (bucket.length >= 2) count++;
  return count;
}

// MARK: Tractors

/** Pair faces of one group bucketed by strength level; faces at a level sorted by suit (jokers last). */
function pairLevels(cards: readonly Card[], group: SuitGroup, trump: Trump): Map<number, Face[]> {
  const levels = new Map<number, Face[]>();
  for (const [face, bucket] of byFace(cards)) {
    if (bucket.length < 2 || groupOf(trump, face) !== group) continue;
    const level = strength(trump, face);
    const list = levels.get(level);
    if (list) list.push(face);
    else levels.set(level, [face]);
  }
  for (const list of levels.values()) {
    list.sort((a, b) => (suitOf(a) ?? 9) - (suitOf(b) ?? 9));
  }
  return levels;
}

/** The groups present in `cards`, in display order. */
function groupsIn(cards: readonly Card[], trump: Trump): SuitGroup[] {
  const seen: SuitGroup[] = [];
  for (const card of sortCards(trump, cards)) {
    const group = groupOf(trump, card);
    if (!seen.includes(group)) seen.push(group);
  }
  return seen;
}

function ascending(keys: Iterable<number>): number[] {
  return Array.from(keys).sort((a, b) => a - b);
}

/**
 * Every tractor of exactly `length` pairs that can be formed from `cards` (sub-runs of longer
 * runs are included). Each result is 2 * length cards, low to high.
 */
export function tractorsIn(cards: readonly Card[], length: number, trump: Trump): Card[][] {
  if (length < 2) return [];
  const faceCards = byFace(cards);
  const results: Card[][] = [];
  for (const group of groupsIn(cards, trump)) {
    const levels = pairLevels(cards, group, trump);
    for (const start of ascending(levels.keys())) {
      let complete = true;
      for (let level = start; level < start + length; level++) {
        if (!levels.has(level)) {
          complete = false;
          break;
        }
      }
      if (!complete) continue;
      // Cartesian product over face choices at each level.
      let partials: Card[][] = [[]];
      for (let level = start; level < start + length; level++) {
        const next: Card[][] = [];
        for (const partial of partials) {
          for (const face of levels.get(level) as Face[]) {
            next.push(partial.concat((faceCards.get(face) as Card[]).slice(0, 2)));
          }
        }
        partials = next;
      }
      results.push(...partials);
    }
  }
  return results;
}

/** Length (in pairs) of the longest run in `cards`: 0 = no pairs, 1 = pairs but no tractor. */
export function longestRun(cards: readonly Card[], trump: Trump): number {
  let best = 0;
  for (const group of groupsIn(cards, trump)) {
    const keys = new Set(pairLevels(cards, group, trump).keys());
    for (const key of keys) {
      if (keys.has(key - 1)) continue;
      let n = 0;
      while (keys.has(key + n)) n++;
      best = Math.max(best, n);
    }
  }
  return best;
}

// MARK: Decomposition

function compareComponents(a: Component, b: Component, trump: Trump): number {
  const countA = shapeCardCount(a.shape);
  const countB = shapeCardCount(b.shape);
  if (countA !== countB) return countB - countA;
  if (a.topStrength !== b.topStrength) return b.topStrength - a.topStrength;
  return sortKey(trump, b.cards[0]) - sortKey(trump, a.cards[0]);
}

/**
 * Splits cards into components: tractors first (longest runs greedily), then pairs, then singles.
 * Sorted largest first (by card count), then by strength descending. This is the canonical
 * "format" of a lead.
 */
export function decompose(cards: readonly Card[], trump: Trump): Component[] {
  const remaining = byFace(cards);
  const components: Component[] = [];

  const take = (face: Face, n: number): Card[] => {
    const bucket = remaining.get(face) as Card[];
    const taken = bucket.slice(0, n);
    const left = bucket.slice(n);
    if (left.length === 0) remaining.delete(face);
    else remaining.set(face, left);
    return taken;
  };

  for (const group of groupsIn(cards, trump)) {
    // Tractors: repeatedly take the longest run available.
    for (;;) {
      const flat: Card[] = [];
      for (const bucket of remaining.values()) flat.push(...bucket);
      const levels = pairLevels(flat, group, trump);
      const keys = new Set(levels.keys());
      let bestStart: number | null = null;
      let bestLength = 1;
      for (const key of ascending(keys).reverse()) {
        if (keys.has(key - 1)) continue;
        let n = 0;
        while (keys.has(key + n)) n++;
        if (n > bestLength) {
          bestLength = n;
          bestStart = key;
        }
      }
      if (bestStart === null) break;
      const tractorCards: Card[] = [];
      for (let level = bestStart; level < bestStart + bestLength; level++) {
        tractorCards.push(...take((levels.get(level) as Face[])[0], 2));
      }
      components.push({
        shape: tractorShape(bestLength),
        cards: tractorCards,
        group,
        topStrength: bestStart + bestLength - 1,
      });
    }
    // Pairs.
    for (const [face, bucket] of Array.from(remaining.entries())) {
      if (bucket.length >= 2 && groupOf(trump, face) === group) {
        const pairCards = take(face, 2);
        components.push({ shape: PAIR, cards: pairCards, group, topStrength: strength(trump, face) });
      }
    }
  }
  // Singles.
  for (const bucket of remaining.values()) {
    for (const card of bucket) {
      components.push({ shape: SINGLE, cards: [card], group: groupOf(trump, card), topStrength: strength(trump, card) });
    }
  }
  return components.sort((a, b) => compareComponents(a, b, trump));
}

/** The shape if `cards` form exactly one component (single, pair or tractor), else null. */
export function shapeOf(cards: readonly Card[], trump: Trump): ComboShape | null {
  if (groupOfCards(cards, trump) === null) return null;
  const components = decompose(cards, trump);
  return components.length === 1 ? components[0].shape : null;
}

/** All possible components of `shape` within `cards` (singles: one per distinct face). */
export function componentsOf(shape: ComboShape, cards: readonly Card[], trump: Trump): Component[] {
  switch (shape.type) {
    case "single": {
      const singles: Component[] = [];
      for (const bucket of byFace(cards).values()) {
        const card = bucket[0];
        singles.push({ shape: SINGLE, cards: [card], group: groupOf(trump, card), topStrength: strength(trump, card) });
      }
      return singles
        .map((c) => ({ c, key: sortKey(trump, c.cards[0]) }))
        .sort((a, b) => a.key - b.key)
        .map((k) => k.c);
    }
    case "pair":
      return pairsIn(cards, trump).map((pair) => ({
        shape: PAIR,
        cards: pair,
        group: groupOf(trump, pair[0]),
        topStrength: strength(trump, pair[0]),
      }));
    case "tractor":
      return tractorsIn(cards, shape.pairs, trump).map((tractor) => ({
        shape: tractorShape(shape.pairs),
        cards: tractor,
        group: groupOf(trump, tractor[0]),
        topStrength: Math.max(...tractor.map((card) => strength(trump, card))),
      }));
  }
}

/** e.g. "pair 7♠ 7♠". */
export function componentDescription(component: Component): string {
  return `${shapeName(component.shape)} ${shortText(component.cards)}`;
}
