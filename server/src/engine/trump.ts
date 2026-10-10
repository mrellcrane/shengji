// Trump context, suit groups and card strength. Port of Engine/Trump.swift.

import {
  ALL_RANKS,
  ALL_SUITS,
  BIG_JOKER_FACE,
  SMALL_JOKER_FACE,
  faceOf,
  isRedSuit,
  rankLabel,
  rankOf,
  regularFace,
  suitName,
  suitOf,
  suitSymbol,
} from "./cards.ts";
import type { Card, Face, Rank, Suit } from "./cards.ts";

/**
 * Which "suit" a card belongs to for following suit: "trump" (jokers, trump-rank cards and the
 * trump suit) or the plain suit's raw value.
 */
export type SuitGroup = "trump" | Suit;

/**
 * The trump context for a round: the trump rank (the declaring team's level) and the trump suit
 * (null when the round has no trump suit; then only jokers and trump-rank cards are trumps).
 *
 * Ordering (highest first), with trump suit hearts and rank 2:
 *   big joker > small joker > 2♥ > 2♠ = 2♣ = 2♦ > A♥ > K♥ > ... > 3♥
 * Plain suits rank A high down to 2, skipping the trump rank.
 */
export interface Trump {
  rank: Rank;
  suit: Suit | null;
}

/** Highest strength a non-rank card can have (an ace when the rank isn't an ace). */
export const TOP_PLAIN_STRENGTH = 11;
export const OFF_SUIT_RANK_STRENGTH = 12;
export const TRUMP_SUIT_RANK_STRENGTH = 13;
export const SMALL_JOKER_STRENGTH = 14;
export const BIG_JOKER_STRENGTH = 15;

export function isTrumpGroup(group: SuitGroup): group is "trump" {
  return group === "trump";
}

/** e.g. "trumps", "spades". */
export function groupName(group: SuitGroup): string {
  return group === "trump" ? "trumps" : suitName(group).toLowerCase();
}

/** "Trump" or the suit symbol. */
export function groupSymbol(group: SuitGroup): string {
  return group === "trump" ? "Trump" : suitSymbol(group);
}

/** True if the card (or face) is a trump. */
export function isTrump(trump: Trump, card: Card | Face): boolean {
  const face = faceOf(card);
  if (face === SMALL_JOKER_FACE || face === BIG_JOKER_FACE) return true;
  return rankOf(face) === trump.rank || suitOf(face) === trump.suit;
}

export function groupOf(trump: Trump, card: Card | Face): SuitGroup {
  if (isTrump(trump, card)) return "trump";
  return suitOf(card) as Suit;
}

/**
 * Strength of a card inside its own group. Higher beats lower; equal strength means the cards tie
 * (the one played first wins). Within a group, consecutive values are adjacent for tractors.
 *  - Non-rank cards (plain suits and the trump suit): 0...11, skipping the trump rank.
 *  - Trump-rank cards not of the trump suit: 12 (13 in a no-trump round).
 *  - Trump-rank card of the trump suit: 13.
 *  - Small joker: 14. Big joker: 15.
 */
export function strength(trump: Trump, card: Card | Face): number {
  const face = faceOf(card);
  if (face === SMALL_JOKER_FACE) return SMALL_JOKER_STRENGTH;
  if (face === BIG_JOKER_FACE) return BIG_JOKER_STRENGTH;
  const rank = rankOf(face) as Rank;
  const suit = suitOf(face) as Suit;
  if (rank === trump.rank) {
    if (trump.suit === null || suit === trump.suit) return TRUMP_SUIT_RANK_STRENGTH;
    return OFF_SUIT_RANK_STRENGTH;
  }
  const base = rank - 2;
  return rank > trump.rank ? base - 1 : base;
}

/** Plain suits in display order: colours alternate where possible, trump suit excluded. */
export function plainSuitOrder(trump: Trump): Suit[] {
  const suits = ALL_SUITS.filter((s) => s !== trump.suit);
  const blacks = suits.filter((s) => !isRedSuit(s));
  const reds = suits.filter((s) => isRedSuit(s));
  const first = blacks.length >= reds.length ? blacks : reds;
  const second = blacks.length >= reds.length ? reds : blacks;
  const out: Suit[] = [];
  while (first.length > 0 || second.length > 0) {
    const a = first.shift();
    if (a !== undefined) out.push(a);
    const b = second.shift();
    if (b !== undefined) out.push(b);
  }
  return out;
}

/**
 * Sort key for showing a hand left to right: plain suits (alternating colours), then trumps on the
 * right; low to high within each group.
 */
export function sortKey(trump: Trump, card: Card | Face): number {
  const group = groupOf(trump, card);
  let groupIndex: number;
  if (group === "trump") {
    groupIndex = 4;
  } else {
    const index = plainSuitOrder(trump).indexOf(group);
    groupIndex = index < 0 ? 0 : index;
  }
  const suit = suitOf(card);
  const tiebreak = suit === null ? 0 : 3 - suit;
  return groupIndex * 1000 + strength(trump, card) * 10 + tiebreak;
}

/** Cards in display order (sort key, then id). Returns a new array. */
export function sortCards(trump: Trump, cards: readonly Card[]): Card[] {
  const keyed = cards.map((card) => ({ card, key: sortKey(trump, card) }));
  keyed.sort((a, b) => (a.key !== b.key ? a.key - b.key : a.card - b.card));
  return keyed.map((k) => k.card);
}

/** Compares two cards of the same group (positive if `a` is stronger). Null if the groups differ. */
export function compareWithinGroup(trump: Trump, a: Card | Face, b: Card | Face): number | null {
  if (groupOf(trump, a) !== groupOf(trump, b)) return null;
  return strength(trump, a) - strength(trump, b);
}

/** e.g. "5♥" (rank 5, hearts trump) or "5 · no trump suit". */
export function trumpDescription(trump: Trump): string {
  if (trump.suit !== null) return rankLabel(trump.rank) + suitSymbol(trump.suit);
  return `${rankLabel(trump.rank)} · no trump suit`;
}

/** Plain-English summary used by the coach, e.g. "Trump suit ♥, trump rank 5". */
export function trumpSummary(trump: Trump): string {
  const label = rankLabel(trump.rank);
  if (trump.suit !== null) return `Trump suit ${suitSymbol(trump.suit)}, trump rank ${label}`;
  return `No trump suit, trump rank ${label} (only jokers and ${label}s are trump)`;
}

/** All faces that are trump this round, highest first (ties grouped together, in suit order). */
export function trumpFacesHighToLow(trump: Trump): Face[] {
  const faces: Face[] = [BIG_JOKER_FACE, SMALL_JOKER_FACE];
  for (const suit of ALL_SUITS) faces.push(regularFace(trump.rank, suit));
  if (trump.suit !== null) {
    for (let i = ALL_RANKS.length - 1; i >= 0; i--) {
      const rank = ALL_RANKS[i];
      if (rank !== trump.rank) faces.push(regularFace(rank, trump.suit));
    }
  }
  // Array.prototype.sort is stable, like the Swift standard library sort.
  return faces.sort((a, b) => strength(trump, b) - strength(trump, a));
}
