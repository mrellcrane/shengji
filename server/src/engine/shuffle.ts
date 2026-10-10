// Cryptographically random, unbiased shuffling for real games. Parity vectors carry explicit deck
// orders, so nothing here has to match the Swift SeededGenerator.

import { doubleDeck } from "./cards.ts";
import type { Card } from "./cards.ts";

/** Fills the array with random 32-bit values, like `crypto.getRandomValues`. */
export type RandomSource = (array: Uint32Array) => Uint32Array;

interface CryptoLike {
  getRandomValues(array: Uint32Array): Uint32Array;
}

/** `crypto.getRandomValues` from the runtime (Cloudflare Workers and Node 22 both provide it). */
export const cryptoRandomSource: RandomSource = (array) => {
  const crypto = (globalThis as { crypto?: CryptoLike }).crypto;
  if (!crypto || typeof crypto.getRandomValues !== "function") {
    throw new Error("crypto.getRandomValues is not available in this runtime");
  }
  return crypto.getRandomValues(array);
};

const TWO_TO_32 = 0x1_0000_0000;

/**
 * A uniformly random integer in 0..<bound (bound 1...2^32), by rejection sampling: values in the
 * incomplete top bucket are drawn again, so there is no modulo bias.
 */
export function randomInt(bound: number, source: RandomSource = cryptoRandomSource): number {
  if (!Number.isInteger(bound) || bound < 1 || bound > TWO_TO_32) {
    throw new RangeError(`bound must be an integer in 1...2^32, got ${bound}`);
  }
  if (bound === 1) return 0;
  const limit = TWO_TO_32 - (TWO_TO_32 % bound);
  const buffer = new Uint32Array(1);
  for (;;) {
    source(buffer);
    const value = buffer[0];
    if (value < limit) return value % bound;
  }
}

/** A uniformly random permutation of `items` (Fisher-Yates). Returns a new array. */
export function shuffle<T>(items: readonly T[], source: RandomSource = cryptoRandomSource): T[] {
  const out = items.slice();
  for (let i = out.length - 1; i > 0; i--) {
    const j = randomInt(i + 1, source);
    const tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/** All 108 cards in a uniformly random dealing order. */
export function shuffledDeck(source: RandomSource = cryptoRandomSource): Card[] {
  return shuffle(doubleDeck(), source);
}
