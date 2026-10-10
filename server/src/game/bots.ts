// Server bots: a deterministic placeholder until the Swift bots are ported (DESIGN.md, Bot
// strategy). The interface is deliberately narrow, `chooseBotAction(round, seat, level)`, and the
// bots only read what their seat may see: their own hand and public information (the trick in
// progress, the trump, the declarations they could make). The helpers below take exactly that,
// so they also work from a client's SeatView (scripts/smoke.ts drives humans with them).
//
//  - Bidding: pass, unless holding a pair of trump-rank cards in their longest suit.
//  - Burying: the lowest 8 non-trumps (non-point cards first), topped up with low trumps.
//  - Leading: a pair or single of the top plain card (an ace) if held, else a low non-point card.
//  - Following: a legal play from candidates checked with the engine's validateFollow; with
//    partner winning, the cheapest; with an opponent winning, the cheapest play that wins when
//    there are points at stake or it is the last play, otherwise the cheapest.

import { cardPoints, containsAll, without } from "../engine/cards.ts";
import type { Card, Suit } from "../engine/cards.ts";
import { cardsInGroup, decompose, componentsOf, groupOfCards, pairsIn, tractorsIn } from "../engine/combos.ts";
import { availableBids, biddingTurn, turn } from "../engine/round.ts";
import type { Declaration, Round } from "../engine/round.ts";
import { followRequirement, partnerOf, validateFollow, winningIndex } from "../engine/rules.ts";
import type { Play } from "../engine/rules.ts";
import { TOP_PLAIN_STRENGTH, groupOf, isTrump, sortKey, strength } from "../engine/trump.ts";
import type { Trump } from "../engine/trump.ts";

export type BotLevel = "standard" | "beginner";

export function isBotLevel(value: unknown): value is BotLevel {
  return value === "standard" || value === "beginner";
}

export type BotAction =
  | { type: "bid"; declaration: Declaration }
  | { type: "pass" }
  | { type: "bury"; cards: Card[] }
  | { type: "play"; cards: Card[] };

/** What one seat knows when it must play: its hand and the public table. */
export interface BotTable {
  hand: readonly Card[];
  trump: Trump;
  /** Plays of the trick in progress, in order; seats in the same frame as `seat`. */
  currentTrick: readonly Play[];
  /** The deciding seat (0 when working from a SeatView). */
  seat: number;
}

/** How much it hurts to give a card away: higher cards, trumps and points cost more. */
function cost(trump: Trump, card: Card): number {
  return strength(trump, card) + (isTrump(trump, card) ? 16 : 0) + cardPoints(card);
}

function totalCost(trump: Trump, cards: readonly Card[]): number {
  let sum = 0;
  for (const card of cards) sum += cost(trump, card);
  return sum;
}

/** Cards ordered cheapest first (ties by display order, so the choice is deterministic). */
function cheapestFirst(trump: Trump, cards: readonly Card[]): Card[] {
  return cards.slice().sort((a, b) => cost(trump, a) - cost(trump, b) || sortKey(trump, a) - sortKey(trump, b) || a - b);
}

function suitOfPlain(trump: Trump, card: Card): Suit | null {
  const group = groupOf(trump, card);
  return group === "trump" ? null : group;
}

// MARK: Bidding

/** A pair of trump-rank cards in the bot's longest suit, if it may declare one; else null (pass). */
export function chooseBid(options: readonly Declaration[], hand: readonly Card[]): Declaration | null {
  const counts = [0, 0, 0, 0];
  for (const card of hand) {
    const face = card % 54;
    if (face < 52) counts[Math.floor(face / 13)]++;
  }
  let longest = 0;
  for (let suit = 1; suit < 4; suit++) if (counts[suit] > counts[longest]) longest = suit;
  return options.find((d) => d.strength === 2 && d.suit === longest) ?? null;
}

// MARK: Burying

/** The 8 cards to bury from the dealer's 33: the lowest non-trumps, non-point cards first. */
export function chooseBury(hand: readonly Card[], trump: Trump): Card[] {
  const plain = hand.filter((card) => !isTrump(trump, card));
  const trumps = hand.filter((card) => isTrump(trump, card));
  const byLow = (cards: readonly Card[]): Card[] =>
    cards
      .slice()
      .sort(
        (a, b) =>
          (cardPoints(a) > 0 ? 1 : 0) - (cardPoints(b) > 0 ? 1 : 0) ||
          strength(trump, a) - strength(trump, b) ||
          sortKey(trump, a) - sortKey(trump, b) ||
          a - b,
      );
  return [...byLow(plain), ...byLow(trumps)].slice(0, 8);
}

// MARK: Leading

/** A lead: the top plain card (as a pair if both are held), else the cheapest non-point card. */
export function chooseLead(hand: readonly Card[], trump: Trump): Card[] {
  const plain = hand.filter((card) => !isTrump(trump, card));
  const tops = plain.filter((card) => strength(trump, card) === TOP_PLAIN_STRENGTH);
  if (tops.length > 0) {
    const pair = pairsIn(tops, trump)[0];
    return pair !== undefined ? pair.slice() : [cheapestFirst(trump, tops)[0]];
  }
  const nonPoint = plain.filter((card) => cardPoints(card) === 0);
  // Among the cheapest, prefer the shortest plain suit (voiding it lets us ruff later).
  const suitLength = (card: Card): number => {
    const suit = suitOfPlain(trump, card);
    return suit === null ? 99 : plain.filter((c) => suitOfPlain(trump, c) === suit).length;
  };
  const pick = (cards: readonly Card[]): Card =>
    cards
      .slice()
      .sort((a, b) => cost(trump, a) - cost(trump, b) || suitLength(a) - suitLength(b) || sortKey(trump, a) - sortKey(trump, b))[0];
  if (nonPoint.length > 0) return [pick(nonPoint)];
  if (plain.length > 0) return [pick(plain)];
  return [cheapestFirst(trump, hand)[0]];
}

// MARK: Following

/** Disjoint tractors of the given lengths in `cards` (tried in `order`), or null. */
function disjointTractors(
  cards: readonly Card[],
  lengths: readonly number[],
  trump: Trump,
  high: boolean,
): Card[][] | null {
  if (lengths.length === 0) return [];
  const options = tractorsIn(cards, lengths[0], trump).sort((a, b) => {
    const d = totalCost(trump, a) - totalCost(trump, b);
    return high ? -d : d;
  });
  for (const tractor of options) {
    const more = disjointTractors(without(cards, tractor), lengths.slice(1), trump, high);
    if (more !== null) return [tractor, ...more];
  }
  return null;
}

/**
 * A follow built from the follow rules: the required tractors, then pairs, then singles, all from
 * the led group when the hand holds enough of it (cheapest or most expensive first); else every
 * led-group card plus the cheapest others.
 */
function constructiveFollow(hand: readonly Card[], lead: readonly Card[], trump: Trump, high: boolean): Card[] {
  const n = lead.length;
  const ledGroup = groupOfCards(lead, trump) ?? groupOf(trump, lead[0]);
  const held = cardsInGroup(hand, ledGroup, trump);
  const others = cheapestFirst(trump, hand.filter((card) => !held.includes(card)));
  if (held.length <= n) return [...held, ...others.slice(0, n - held.length)];
  const requirement = followRequirement(lead, held, trump);
  let pool = held.slice();
  const play: Card[] = [];
  for (const tractor of disjointTractors(pool, requirement.tractorLengths, trump, high) ?? []) {
    play.push(...tractor);
    pool = without(pool, tractor);
  }
  let pairs = requirement.tractorLengths.reduce((a, b) => a + b, 0);
  const pairOptions = pairsIn(pool, trump).sort((a, b) => {
    const d = totalCost(trump, a) - totalCost(trump, b);
    return high ? -d : d;
  });
  for (const pair of pairOptions) {
    if (pairs >= requirement.totalPairs || play.length + 2 > n) break;
    if (!containsAll(pool, pair)) continue;
    play.push(...pair);
    pool = without(pool, pair);
    pairs++;
  }
  // Singles: prefer cards that do not break a pair still in the pool.
  const paired = new Set(pairsIn(pool, trump).flat());
  const singles = pool.slice().sort((a, b) => {
    const pa = paired.has(a) ? 1 : 0;
    const pb = paired.has(b) ? 1 : 0;
    if (pa !== pb) return pa - pb;
    const d = cost(trump, a) - cost(trump, b);
    return high ? -d : d;
  });
  play.push(...singles.slice(0, n - play.length));
  return play;
}

/** When void in a plain led suit: trumps with the lead's component shapes (cheapest), if held. */
function ruff(hand: readonly Card[], lead: readonly Card[], trump: Trump): Card[] | null {
  const ledGroup = groupOfCards(lead, trump) ?? groupOf(trump, lead[0]);
  if (ledGroup === "trump" || cardsInGroup(hand, ledGroup, trump).length > 0) return null;
  let trumps = cardsInGroup(hand, "trump", trump);
  const play: Card[] = [];
  for (const component of decompose(lead, trump)) {
    const options = componentsOf(component.shape, trumps, trump).sort(
      (a, b) => totalCost(trump, a.cards) - totalCost(trump, b.cards),
    );
    if (options.length === 0) return null;
    play.push(...options[0].cards);
    trumps = without(trumps, options[0].cards);
  }
  return play.length === lead.length ? play : null;
}

/** Legal follows worth considering (each checked with validateFollow), cheapest first. */
export function followCandidates(hand: readonly Card[], lead: readonly Card[], trump: Trump): Card[][] {
  const candidates: Card[][] = [constructiveFollow(hand, lead, trump, false), constructiveFollow(hand, lead, trump, true)];
  const ruffing = ruff(hand, lead, trump);
  if (ruffing !== null) candidates.push(ruffing);
  // A single lead: every card is a candidate (the legal ones survive the check below).
  if (lead.length === 1) {
    for (const card of hand) candidates.push([card]);
  }
  const seen = new Set<string>();
  const legal: Card[][] = [];
  for (const cards of candidates) {
    const key = cards.slice().sort((a, b) => a - b).join(",");
    if (seen.has(key)) continue;
    seen.add(key);
    if (cards.length === lead.length && validateFollow(cards, hand, lead, trump) === null) legal.push(cards);
  }
  return legal.sort((a, b) => totalCost(trump, a) - totalCost(trump, b));
}

/** The follow a bot (or the smoke test's stand-in for a person) plays. */
export function chooseFollow(table: BotTable, level: BotLevel = "standard"): Card[] {
  const { hand, trump, currentTrick, seat } = table;
  const lead = currentTrick[0].cards;
  const legal = followCandidates(hand, lead, trump);
  if (legal.length === 0) {
    // Cannot happen (the constructive follow is legal by the rules); never stall a game.
    return constructiveFollow(hand, lead, trump, false);
  }
  if (level === "beginner") return legal[0];
  const winner = currentTrick[winningIndex(currentTrick, trump)].player;
  const partnerWinning = winner === partnerOf(seat);
  const last = currentTrick.length === 3;
  const points = currentTrick.reduce((sum, p) => sum + p.cards.reduce((s, c) => s + cardPoints(c), 0), 0);
  const wins = (cards: Card[]): boolean =>
    winningIndex([...currentTrick, { player: seat, cards }], trump) === currentTrick.length;
  if (partnerWinning) {
    if (last) {
      // Partner takes the trick: give them points, as cheaply as possible otherwise.
      const pointsOf = (cards: Card[]): number => cards.reduce((s, c) => s + cardPoints(c), 0);
      return legal.slice().sort((a, b) => pointsOf(b) - pointsOf(a) || totalCost(trump, a) - totalCost(trump, b))[0];
    }
    return legal[0];
  }
  // Winning keeps our own point cards, so they make a win cheaper rather than dearer.
  const winCost = (cards: Card[]): number => totalCost(trump, cards) - 2 * cards.reduce((s, c) => s + cardPoints(c), 0);
  const winning = legal.filter(wins).sort((a, b) => winCost(a) - winCost(b));
  if (winning.length > 0 && (points > 0 || last)) return winning[0];
  return legal.filter((cards) => !wins(cards))[0] ?? legal[0];
}

// MARK: The bot

/** What the bot at `seat` does now, or null if it is not that seat's turn. */
export function chooseBotAction(round: Round, seat: number, level: BotLevel): BotAction | null {
  if (biddingTurn(round) === seat) {
    const declaration = level === "beginner" ? null : chooseBid(availableBids(round, seat), round.hands[seat]);
    return declaration === null ? { type: "pass" } : { type: "bid", declaration };
  }
  if (round.phase === "burying" && round.dealer === seat) {
    return { type: "bury", cards: chooseBury(round.hands[seat], round.trump) };
  }
  if (turn(round) === seat) {
    const hand = round.hands[seat];
    if (round.currentTrick.length === 0) return { type: "play", cards: chooseLead(hand, round.trump) };
    return { type: "play", cards: chooseFollow({ hand, trump: round.trump, currentTrick: round.currentTrick, seat }, level) };
  }
  return null;
}
