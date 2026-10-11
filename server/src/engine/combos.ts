// Singles, pairs, tractors, sets (triples, four of a kind) and tractors of sets, and the decomposition
// of a play. Port of Engine/Combination.swift.

import { faceOf, shortText, suitOf } from "./cards.ts";
import type { Card, Face } from "./cards.ts";
import { groupOf, sortCards, sortKey, strength } from "./trump.ts";
import type { SuitGroup, Trump } from "./trump.ts";

/**
 * The basic building blocks of a play, in the parity vectors' encoding. Two decks give:
 *  - single `{type: "single", pairs: 0}`: one card
 *  - pair `{type: "pair", pairs: 1}`: two identical cards (same face; 2♠ + 2♣ is NOT a pair)
 *  - tractor `{type: "tractor", pairs: n}`: n >= 2 pairs of consecutive strength in the same suit
 *    group (拖拉机)
 * With three or more decks a face can appear three or four times, which adds:
 *  - set `{type: "set", width: n}`: n >= 3 identical cards (a triple; four of a kind)
 *  - setTractor `{type: "setTractor", width, length}`: `length` >= 2 sets of `width` >= 3 identical
 *    cards at consecutive strengths in one suit group (a tractor of triples)
 * Every shape is `width` identical cards at each of `length` consecutive strengths (`makeShape`).
 */
export type ComboShape =
  | { type: "single" | "pair" | "tractor"; pairs: number }
  | { type: "set"; width: number }
  | { type: "setTractor"; width: number; length: number };

export const SINGLE: ComboShape = Object.freeze({ type: "single", pairs: 0 }) as ComboShape;
export const PAIR: ComboShape = Object.freeze({ type: "pair", pairs: 1 }) as ComboShape;

export function tractorShape(pairs: number): ComboShape {
  return { type: "tractor", pairs };
}

export function setShape(width: number): ComboShape {
  return { type: "set", width };
}

export function setTractorShape(width: number, length: number): ComboShape {
  return { type: "setTractor", width, length };
}

/** The shape of `length` consecutive sets of `width` identical cards (width 1: a single). Swift `ComboShape.make`. */
export function makeShape(width: number, length: number): ComboShape {
  const w = Math.max(1, width);
  const l = Math.max(1, length);
  if (w === 1) return SINGLE;
  if (w === 2) return l === 1 ? PAIR : tractorShape(l);
  return l === 1 ? setShape(w) : setTractorShape(w, l);
}

/** Identical cards at each strength: 1 for a single, 2 for pairs and tractors, 3 for triples. */
export function shapeWidth(shape: ComboShape): number {
  switch (shape.type) {
    case "single":
      return 1;
    case "pair":
    case "tractor":
      return 2;
    case "set":
    case "setTractor":
      return shape.width;
  }
}

/** Consecutive strengths: 1 for a single, pair or set, the number of steps for a tractor. */
export function shapeLength(shape: ComboShape): number {
  switch (shape.type) {
    case "single":
    case "pair":
    case "set":
      return 1;
    case "tractor":
      return shape.pairs;
    case "setTractor":
      return shape.length;
  }
}

export function shapeCardCount(shape: ComboShape): number {
  return shapeWidth(shape) * shapeLength(shape);
}

/** Pairs the shape holds (a triple holds one, four of a kind two). */
export function shapePairCount(shape: ComboShape): number {
  return shapeLength(shape) * Math.floor(shapeWidth(shape) / 2);
}

/** True for tractors of pairs, triples or more. */
export function isTractorShape(shape: ComboShape): boolean {
  return shapeLength(shape) >= 2;
}

export function shapesEqual(a: ComboShape, b: ComboShape): boolean {
  return a.type === b.type && shapeWidth(a) === shapeWidth(b) && shapeLength(a) === shapeLength(b);
}

/** "triple", "four of a kind", "5 of a kind". */
function setName(width: number): string {
  switch (width) {
    case 3:
      return "triple";
    case 4:
      return "four of a kind";
    default:
      return `${width} of a kind`;
  }
}

/** "triples", "fours", "5s". */
function setsName(width: number): string {
  switch (width) {
    case 3:
      return "triples";
    case 4:
      return "fours";
    default:
      return `${width}s`;
  }
}

/** "single", "pair", "tractor", "tractor of 3 pairs", "triple", "tractor of triples", "tractor of 3 fours". */
export function shapeName(shape: ComboShape): string {
  switch (shape.type) {
    case "single":
      return "single";
    case "pair":
      return "pair";
    case "tractor":
      return shape.pairs === 2 ? "tractor" : `tractor of ${shape.pairs} pairs`;
    case "set":
      return setName(shape.width);
    case "setTractor": {
      const sets = setsName(shape.width);
      return shape.length === 2 ? `tractor of ${sets}` : `tractor of ${shape.length} ${sets}`;
    }
  }
}

/** One component of a play: a single, a pair, a tractor or a set (or tractor of sets), all from one suit group. */
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

// MARK: Sets of identical cards (any width)

/**
 * The most copies of any one face among `cards` (0 when empty). Two decks give at most 2; with three
 * or more decks a face can appear three or four times (triples, four of a kind).
 */
export function maxCopies(cards: readonly Card[]): number {
  const counts = new Map<Face, number>();
  let best = 0;
  for (const card of cards) {
    const count = (counts.get(faceOf(card)) ?? 0) + 1;
    counts.set(faceOf(card), count);
    best = Math.max(best, count);
  }
  return best;
}

/** Card groups sorted by the sort key of their first card (unique per face). */
function bySortKey(groups: Card[][], trump: Trump): Card[][] {
  return groups
    .map((cards) => ({ cards, key: sortKey(trump, cards[0]) }))
    .sort((a, b) => a.key - b.key)
    .map((g) => g.cards);
}

/**
 * Every set of `width` identical cards in `cards`: the lowest-id `width` copies of each face held at
 * least that often, sorted by group then strength ascending (width 2: `pairsIn`). Swift `Combos.sets`.
 */
export function setsIn(cards: readonly Card[], width: number, trump: Trump): Card[][] {
  const w = Math.max(1, width);
  const sets: Card[][] = [];
  for (const bucket of byFace(cards).values()) {
    if (bucket.length >= w) sets.push(bucket.slice(0, w));
  }
  return bySortKey(sets, trump);
}

/**
 * Like `setsIn` but a face held twice as often gives two sets (four 7♠ are two pairs), lowest ids
 * first. Swift `Combos.allSets`.
 */
export function allSetsIn(cards: readonly Card[], width: number, trump: Trump): Card[][] {
  const w = Math.max(1, width);
  const out: Card[][] = [];
  for (const bucket of byFace(cards).values()) {
    for (let start = 0; start + w <= bucket.length; start += w) out.push(bucket.slice(start, start + w));
  }
  return out
    .map((cards) => ({ cards, key: sortKey(trump, cards[0]) }))
    .sort((a, b) => a.key - b.key || a.cards[0] - b.cards[0])
    .map((g) => g.cards);
}

/** Faces of one group held at least `width` times, bucketed by strength level (width 2: `pairLevels`). */
function setLevels(cards: readonly Card[], width: number, group: SuitGroup, trump: Trump): Map<number, Face[]> {
  const levels = new Map<number, Face[]>();
  for (const [face, bucket] of byFace(cards)) {
    if (bucket.length < width || groupOf(trump, face) !== group) continue;
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

/**
 * Every tractor of exactly `length` consecutive sets of `width` identical cards (width 2:
 * `tractorsIn`). Each result is width * length cards, low to high. Swift `Combos.setTractors`.
 */
export function setTractorsIn(cards: readonly Card[], width: number, length: number, trump: Trump): Card[][] {
  if (length < 2 || width < 2) return [];
  if (width === 2) return tractorsIn(cards, length, trump);
  const faceCards = byFace(cards);
  const results: Card[][] = [];
  for (const group of groupsIn(cards, trump)) {
    const levels = setLevels(cards, width, group, trump);
    for (const start of ascending(levels.keys())) {
      let complete = true;
      for (let level = start; level < start + length; level++) {
        if (!levels.has(level)) {
          complete = false;
          break;
        }
      }
      if (!complete) continue;
      let partials: Card[][] = [[]];
      for (let level = start; level < start + length; level++) {
        const next: Card[][] = [];
        for (const partial of partials) {
          for (const face of levels.get(level) as Face[]) {
            next.push(partial.concat((faceCards.get(face) as Card[]).slice(0, width)));
          }
        }
        partials = next;
      }
      results.push(...partials);
    }
  }
  return results;
}

/** Length of the longest run of sets of `width` identical cards: 0 = none, 1 = sets but no tractor. */
export function longestSetRun(cards: readonly Card[], width: number, trump: Trump): number {
  if (width === 2) return longestRun(cards, trump);
  let best = 0;
  for (const group of groupsIn(cards, trump)) {
    const keys = new Set(setLevels(cards, width, group, trump).keys());
    for (const key of keys) {
      if (keys.has(key - 1)) continue;
      let n = 0;
      while (keys.has(key + n)) n++;
      best = Math.max(best, n);
    }
  }
  return best;
}

/**
 * Every way to take one combination of `shape` out of `cards`, as card lists: one per face (or per
 * choice of faces along a tractor), using the lowest-id copies. Swift `Combos.units(of:in:trump:)`.
 */
export function unitsOf(shape: ComboShape, cards: readonly Card[], trump: Trump): Card[][] {
  switch (shape.type) {
    case "single": {
      const singles: Card[][] = [];
      for (const bucket of byFace(cards).values()) singles.push([bucket[0]]);
      return bySortKey(singles, trump);
    }
    case "pair":
      return pairsIn(cards, trump);
    case "tractor":
      return tractorsIn(cards, shape.pairs, trump);
    case "set":
      return setsIn(cards, shape.width, trump);
    case "setTractor":
      return setTractorsIn(cards, shape.width, shape.length, trump);
  }
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
 * "format" of a lead. With three or more decks, where a face can appear three or four times, the
 * widest sets are taken first: tractors of the widest sets, then those sets, then narrower ones
 * (777 888 99 is a tractor of triples and a pair).
 */
export function decompose(cards: readonly Card[], trump: Trump): Component[] {
  if (maxCopies(cards) > 2) return decomposeSets(cards, trump);
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

/** `decompose` for cards holding three or more copies of a face. Swift `Combos.decomposeSets`. */
function decomposeSets(cards: readonly Card[], trump: Trump): Component[] {
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
    let widest = 0;
    for (const [face, bucket] of remaining) {
      if (groupOf(trump, face) === group) widest = Math.max(widest, bucket.length);
    }
    for (let width = widest; width >= 2; width--) {
      // Tractors of this width: repeatedly take the longest run available (ties: the highest).
      for (;;) {
        const flat: Card[] = [];
        for (const bucket of remaining.values()) flat.push(...bucket);
        const levels = setLevels(flat, width, group, trump);
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
          tractorCards.push(...take((levels.get(level) as Face[])[0], width));
        }
        components.push({
          shape: makeShape(width, bestLength),
          cards: tractorCards,
          group,
          topStrength: bestStart + bestLength - 1,
        });
      }
      // Sets of this width.
      for (const [face, bucket] of Array.from(remaining.entries())) {
        if (bucket.length >= width && groupOf(trump, face) === group) {
          components.push({ shape: makeShape(width, 1), cards: take(face, width), group, topStrength: strength(trump, face) });
        }
      }
    }
  }
  for (const bucket of remaining.values()) {
    for (const card of bucket) {
      components.push({ shape: SINGLE, cards: [card], group: groupOf(trump, card), topStrength: strength(trump, card) });
    }
  }
  return components.sort((a, b) => {
    const countA = shapeCardCount(a.shape);
    const countB = shapeCardCount(b.shape);
    if (countA !== countB) return countB - countA;
    if (a.topStrength !== b.topStrength) return b.topStrength - a.topStrength;
    const widthA = shapeWidth(a.shape);
    const widthB = shapeWidth(b.shape);
    if (widthA !== widthB) return widthB - widthA;
    return sortKey(trump, b.cards[0]) - sortKey(trump, a.cards[0]);
  });
}

/** The shape if `cards` form exactly one component (single, pair, tractor, set or tractor of sets), else null. */
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
    case "set":
      return setsIn(cards, shape.width, trump).map((set) => ({
        shape: setShape(shape.width),
        cards: set,
        group: groupOf(trump, set[0]),
        topStrength: strength(trump, set[0]),
      }));
    case "setTractor":
      return setTractorsIn(cards, shape.width, shape.length, trump).map((tractor) => ({
        shape: setTractorShape(shape.width, shape.length),
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
