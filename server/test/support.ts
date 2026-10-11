// Shared test helpers: vector loading, a compact structural diff, and a seeded RNG.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { isDeepStrictEqual } from "node:util";

const VECTORS = new URL("./vectors/", import.meta.url);

/** Parses one of the generated vector files in test/vectors. */
export function loadVectors<T>(name: string): T {
  return JSON.parse(readFileSync(new URL(name, VECTORS), "utf8")) as T;
}

function show(value: unknown): string {
  const text = JSON.stringify(value);
  if (text === undefined) return String(value);
  return text.length > 160 ? `${text.slice(0, 157)}...` : text;
}

/** Up to `limit` lines, one per differing path: "at .a[2].b: expected X, got Y". */
export function diffLines(actual: unknown, expected: unknown, limit = 6): string[] {
  const lines: string[] = [];
  const walk = (a: unknown, e: unknown, path: string): void => {
    if (lines.length >= limit || isDeepStrictEqual(a, e)) return;
    if (Array.isArray(a) && Array.isArray(e)) {
      if (a.length !== e.length) {
        lines.push(`at ${path || "."}: expected ${e.length} items ${show(e)}, got ${a.length} items ${show(a)}`);
        return;
      }
      for (let i = 0; i < e.length; i++) walk(a[i], e[i], `${path}[${i}]`);
      return;
    }
    if (a && e && typeof a === "object" && typeof e === "object" && !Array.isArray(a) && !Array.isArray(e)) {
      const keys = new Set([...Object.keys(a), ...Object.keys(e)]);
      for (const key of keys) {
        walk((a as Record<string, unknown>)[key], (e as Record<string, unknown>)[key], `${path}.${key}`);
      }
      return;
    }
    lines.push(`at ${path || "."}: expected ${show(e)}, got ${show(a)}`);
  };
  walk(actual, expected, "");
  return lines;
}

/**
 * Collects mismatches against the Swift engine and fails once with a compact report (the first
 * few cases, each with the differing paths) instead of stopping at the first one.
 */
export function parity(name: string): {
  equal: (context: string, actual: unknown, expected: unknown) => boolean;
  count: () => number;
  finish: () => void;
} {
  const failures: string[] = [];
  let checks = 0;
  let failed = 0;
  return {
    equal(context, actual, expected) {
      checks++;
      if (isDeepStrictEqual(actual, expected)) return true;
      failed++;
      if (failures.length < 12) {
        failures.push(`  ${context}\n${diffLines(actual, expected).map((l) => `    ${l}`).join("\n")}`);
      }
      return false;
    },
    count: () => checks,
    finish() {
      if (failed > 0) {
        assert.fail(
          `${name}: ${failed} of ${checks} checks differ from the Swift engine (first ${failures.length}):\n` +
            failures.join("\n"),
        );
      }
    },
  };
}

/** Small seedable RNG (mulberry32) for reproducible random tests. */
export function seededRandom(seed: number): {
  next: () => number;
  below: (n: number) => number;
  pick: <T>(items: readonly T[]) => T;
  shuffle: <T>(items: readonly T[]) => T[];
  sample: <T>(items: readonly T[], count: number) => T[];
  chance: (percent: number) => boolean;
} {
  let state = seed >>> 0;
  const next = (): number => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const below = (n: number): number => Math.floor(next() * n);
  const shuffle = <T>(items: readonly T[]): T[] => {
    const out = items.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j = below(i + 1);
      [out[i], out[j]] = [out[j], out[i]];
    }
    return out;
  };
  return {
    next,
    below,
    pick: <T>(items: readonly T[]): T => items[below(items.length)],
    shuffle,
    sample: <T>(items: readonly T[], count: number): T[] => shuffle(items).slice(0, Math.max(0, count)),
    chance: (percent: number): boolean => next() * 100 < percent,
  };
}

export type Rng = ReturnType<typeof seededRandom>;

/**
 * A deck in dealing order (like the Swift tests' EngineTestSupport.deck): `hands[seat]` lists cards
 * that seat must receive (dealt first, in order), `kitty` lists kitty cards, and the rest are filled
 * in from a seeded shuffle. Cards are dealt one at a time from `firstSeat`. `players` picks the
 * table: 4 (108 cards, 25 each, a kitty of 8), 5 (162, 31 each, 7), 6 (162, 26 each, 6), 7 (216, 30
 * each, 6), 8 (216, 26 each, 8) or 9 (270, 29 each, 9).
 */
export function buildDeck(
  hands: readonly (readonly number[])[] = [[], [], [], []],
  kitty: readonly number[] = [],
  firstSeat = 0,
  seed = 1,
  players = 4,
): number[] {
  // Half a deck per player, rounded up; the kitty is what is left over (at least 5 cards).
  const decks = Math.floor((players + 1) / 2);
  let kittySize = (54 * decks) % players;
  if (kittySize === 0) kittySize = players;
  if (kittySize < 5) kittySize += players;
  const handSize = (54 * decks - kittySize) / players;
  const seats = Array.from({ length: players }, (_, seat) => seat);
  const spec = seats.map((seat) => (hands[seat] ?? []).slice());
  const used = new Set<number>([...spec.flat(), ...kitty]);
  assert.equal(used.size, spec.flat().length + kitty.length, "duplicate cards in deck spec");
  const rng = seededRandom(seed);
  const rest = rng.shuffle(Array.from({ length: 54 * decks }, (_, id) => id).filter((id) => !used.has(id)));
  for (const hand of spec) {
    while (hand.length < handSize) hand.push(rest.pop() as number);
  }
  const fullKitty = kitty.slice();
  while (fullKitty.length < kittySize) fullKitty.push(rest.pop() as number);
  assert.equal(rest.length, 0);
  assert.ok(spec.every((hand) => hand.length === handSize), `a hand spec has more than ${handSize} cards`);
  const deck: number[] = [];
  for (let index = 0; index < players * handSize; index++) {
    deck.push(spec[(firstSeat + index) % players][Math.floor(index / players)]);
  }
  return [...deck, ...fullKitty];
}
