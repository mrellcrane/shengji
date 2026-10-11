// Declaring trump: offline during the deal, online in turn-based bidding. Port of
// ShengjiCore/Sources/ShengjiCore/Bots/BotDeclaring.swift (`choose`), choices only. Deterministic:
// the same view and options always give the same choice.
//  - Never overrides a partner (Finding Friends has no partners while declaring: anyone else's
//    declaration is fair game); always reinforces its own declaration with more of the same card
//    when it can (a single becomes a pair; with three or more decks, the most copies held).
//  - Standard: strength = would-be trumps (that suit + every trump-rank card + jokers) as a share of
//    the cards received so far. Declares once at least 6 cards are in, when strength reaches a
//    threshold that eases from 0.30 to 0.25 as the deal ends. A joker pair (no trump) is used when
//    jokers and rank cards make up at least a fifth of the hand and no plain suit is long (under
//    0.30 of the hand, rank cards aside). An opponent's declaration is overridden only with a
//    clearly good suit (share at least 0.40 and 0.10 above theirs), or with a joker pair when no
//    trump suits us or their suit is poor for us.
//  - Beginner: declares only with a pair.

import { rankOf, suitOf, tableHandSize } from "../engine/cards.ts";
import type { Card, Rank, Suit } from "../engine/cards.ts";
import { HAND_SIZE, RANK_CARDS, declarationCardCount, declarationKind } from "../engine/round.ts";
import type { Declaration } from "../engine/round.ts";
import { teamOf } from "../engine/rules.ts";
import { viewFindsFriends, viewTable } from "../engine/seatview.ts";
import type { SeatView } from "../engine/seatview.ts";
import { isTrump } from "../engine/trump.ts";
import type { BotLevel } from "./bot.ts";
import { DEFAULT_TUNING } from "./table.ts";
import type { BotTuning } from "./table.ts";

export const MINIMUM_CARDS = 6;
/** Share of jokers and rank cards for a no-trump declaration. */
export const NO_TRUMP_THRESHOLD = 0.2;
/** A plain suit (rank cards aside) holding this share of the hand counts as long. */
export const LONG_SUIT_SHARE = 0.3;

/** Share of `hand` in its longest plain suit, not counting trump-rank cards or jokers. */
export function longestPlainShare(hand: readonly Card[], rank: Rank): number {
  if (hand.length === 0) return 0;
  const counts = [0, 0, 0, 0];
  for (const card of hand) {
    if (rankOf(card) === rank) continue;
    const suit = suitOf(card);
    if (suit !== null) counts[suit] += 1;
  }
  return Math.max(...counts) / hand.length;
}

/** Cards of `hand` that would be trump with this suit (null = no trump suit). */
export function trumpCount(hand: readonly Card[], rank: Rank, suit: Suit | null): number {
  const trump = { rank, suit };
  let count = 0;
  for (const card of hand) if (isTrump(trump, card)) count += 1;
  return count;
}

/** Share of `hand` that would be trump with this suit (null = no trump suit). */
export function trumpShare(hand: readonly Card[], rank: Rank, suit: Suit | null): number {
  if (hand.length === 0) return 0;
  return trumpCount(hand, rank, suit) / hand.length;
}

/** Threshold for declaring a suit after receiving `received` of `handSize` cards. */
export function threshold(
  received: number,
  complete: boolean,
  handSize = HAND_SIZE,
  tuning: Readonly<BotTuning> = DEFAULT_TUNING,
): number {
  const span = handSize - MINIMUM_CARDS;
  const progress = complete ? 1.0 : Math.min(1.0, Math.max(0.0, (received - MINIMUM_CARDS) / span));
  return tuning.declareEarly - (tuning.declareEarly - tuning.declareLate) * progress;
}

/** Every card is dealt: online bidding, or offline once every hand is full (100 cards with 4 players). */
export function isDealComplete(view: SeatView): boolean {
  const table = viewTable(view);
  return view.phase === "bidding" || view.handCounts.reduce((a, b) => a + b, 0) >= table.players * tableHandSize(table);
}

function withPlayerZero(d: Declaration): Declaration {
  return { player: 0, cards: d.cards.slice(), suit: d.suit, strength: d.strength };
}

/** Swift `lexicographicallyPrecedes` for card ids. */
function precedes(a: readonly Card[], b: readonly Card[]): boolean {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) return a[i] < b[i];
  return a.length < b.length;
}

/**
 * The available declarations as the viewer's (player 0), in the engine's order: weakest first,
 * then by suit, no trump suit last.
 */
export function canonical(available: readonly Declaration[]): Declaration[] {
  return available.map(withPlayerZero).sort((a, b) => {
    if (a.strength !== b.strength) return a.strength - b.strength;
    const first = a.suit ?? 9;
    const second = b.suit ?? 9;
    if (first !== second) return first - second;
    return precedes(a.cards, b.cards) ? -1 : precedes(b.cards, a.cards) ? 1 : 0;
  });
}

/**
 * The declaration of the viewer of `view` among `available` (seats viewer-relative: the viewer is
 * 0, the partners the even seats): one of `available` with player 0, or null to pass. Swift
 * `BotDeclaring.choose(for:view:available:).declaration`.
 */
export function chooseDeclaration(
  view: SeatView,
  available: readonly Declaration[],
  level: BotLevel,
  tuning: Readonly<BotTuning> = DEFAULT_TUNING,
): Declaration | null {
  if (view.phase !== "dealing" && view.phase !== "bidding") return null;
  const options = canonical(available);
  // Who holds the declaration comes first.
  const current = view.declaration;
  if (current !== null) {
    if (current.player !== 0 && !viewFindsFriends(view) && teamOf(current.player) === teamOf(0)) return null;
    if (current.player === 0) {
      // Reinforce with more of the same card: a single becomes a pair (with three or more decks,
      // the most copies held).
      const kind = declarationKind(current.strength);
      const shown = declarationCardCount(current.strength);
      let more: Declaration | null = null;
      for (const option of options) {
        if (
          declarationKind(option.strength) === kind &&
          option.suit === current.suit &&
          declarationCardCount(option.strength) > shown &&
          (option.suit !== null || kind !== RANK_CARDS)
        ) {
          more = option;
        }
      }
      return more;
    }
  }
  if (options.length === 0) return null;
  if (level === "beginner") return options.find((o) => o.strength >= 2) ?? null;
  return standard(options, view, tuning);
}

function standard(options: readonly Declaration[], view: SeatView, tuning: Readonly<BotTuning>): Declaration | null {
  const hand = view.hand;
  if (hand.length < MINIMUM_CARDS) return null;
  const rank = view.trump.rank;
  const bar = threshold(hand.length, isDealComplete(view), tableHandSize(viewTable(view)), tuning);

  // Best suit option: highest share, then the stronger declaration (a pair is harder to override).
  let bestSuit: { option: Declaration; share: number } | null = null;
  for (const option of options) {
    if (option.suit === null) continue;
    const share = trumpShare(hand, rank, option.suit);
    if (bestSuit !== null) {
      if (share < bestSuit.share) continue;
      if (share === bestSuit.share && option.strength <= bestSuit.option.strength) continue;
    }
    bestSuit = { option, share };
  }
  let noTrump: Declaration | null = null;
  for (const option of options) if (option.suit === null) noTrump = option;
  // Jokers and trump-rank cards are trumps whatever the suit; no trump suit suits a hand rich in
  // them with no long plain suit to make trumps of.
  const noTrumpShare = trumpShare(hand, rank, null);
  const wantsNoTrump = noTrumpShare >= NO_TRUMP_THRESHOLD && longestPlainShare(hand, rank) < LONG_SUIT_SHARE;

  const current = view.declaration;
  if (current === null) {
    if (noTrump !== null && wantsNoTrump) return noTrump;
    if (bestSuit !== null && bestSuit.share >= bar) return bestSuit.option;
    return null;
  }
  // An opponent holds the declaration: only override with a clearly better suit for us.
  const theirs = trumpShare(hand, rank, current.suit);
  if (bestSuit !== null && bestSuit.share >= Math.max(tuning.overrideShare, theirs + 0.1)) return bestSuit.option;
  // A joker pair also blocks their suit: worth it when that suit does little for us.
  const poorForUs = theirs < bar || (wantsNoTrump && theirs < tuning.overrideShare);
  if (noTrump !== null && noTrumpShare >= NO_TRUMP_THRESHOLD && poorForUs) return noTrump;
  return null;
}
