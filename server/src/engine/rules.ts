// Leading, following, throws and trick winners. Port of Engine/Rules.swift.

import { containsAll, suitSingularName, without } from "./cards.ts";
import type { Card } from "./cards.ts";
import {
  cardsInGroup,
  decompose,
  groupOfCards,
  isPair,
  longestRun,
  pairCount,
  pairsIn,
  shapeCardCount,
  tractorsIn,
} from "./combos.ts";
import type { Component } from "./combos.ts";
import { BIG_JOKER_STRENGTH, groupName, groupOf, sortKey, strength } from "./trump.ts";
import type { SuitGroup, Trump } from "./trump.ts";

// MARK: Seats

/**
 * Seats: 0 = South (the human offline), 1 = East, 2 = North (partner), 3 = West. Play goes
 * 0 -> 1 -> 2 -> 3 -> 0. Partners sit opposite; team = seat % 2.
 */
export const HUMAN_SEAT = 0;
export const ALL_SEATS: readonly number[] = [0, 1, 2, 3];

export function teamOf(seat: number): number {
  return seat % 2;
}

export function partnerOf(seat: number): number {
  return (seat + 2) % 4;
}

export function nextSeat(seat: number): number {
  return (seat + 1) % 4;
}

/**
 * Display name of `seat` as seen from `viewer` (default seat 0, as in Swift `Seats.name`):
 * "You", "East", "Partner", "West". Online, each player sees the table rotated so they are "You".
 */
export function seatName(seat: number, viewer = HUMAN_SEAT): string {
  // Seen from seat 0 this is exactly the Swift switch (anything but 0, 1, 2 is "West").
  const relative = viewer === HUMAN_SEAT ? seat : (((seat - viewer) % 4) + 4) % 4;
  switch (relative) {
    case 0:
      return "You";
    case 1:
      return "East";
    case 2:
      return "Partner";
    default:
      return "West";
  }
}

/** One player's contribution to a trick. */
export interface Play {
  player: number;
  cards: Card[];
}

// MARK: Violations

/** Why a lead is illegal. */
export type LeadViolation = "empty" | "cardsNotInHand" | "mixedSuits";

/** One or two plain-English sentences for the coach. */
export function leadViolationExplanation(violation: LeadViolation): string {
  switch (violation) {
    case "empty":
      return "Choose at least one card to lead.";
    case "cardsNotInHand":
      return "You can only play cards that are in your hand.";
    case "mixedSuits":
      return (
        "A lead must be all one suit, or all trumps. " +
        "Jokers and trump-rank cards count as trumps, not as their printed suit."
      );
  }
}

/** Why a follow is illegal. The explanation is shown to learners, so it must teach the rule. */
export type FollowViolation =
  | { case: "wrongCount"; expected: number }
  | { case: "cardsNotInHand" }
  /** The player still holds cards of the led group that they didn't play. */
  | { case: "mustFollowSuit"; group: SuitGroup }
  /** The player holds a tractor of the needed length in the led group but didn't play one. */
  | { case: "mustPlayTractor"; length: number }
  /** The player had to play at least `required` pairs from the led group. */
  | { case: "mustPlayPairs"; required: number };

export function followViolationExplanation(violation: FollowViolation): string {
  switch (violation.case) {
    case "wrongCount": {
      const cards = violation.expected === 1 ? "1 card" : `${violation.expected} cards`;
      return `Play exactly ${cards}, the same number as the lead.`;
    }
    case "cardsNotInHand":
      return "You can only play cards that are in your hand.";
    case "mustFollowSuit": {
      const group = violation.group;
      const name = groupName(group);
      const capitalized = name.slice(0, 1).toUpperCase() + name.slice(1);
      // Learners often take a trump-rank card (2♠ when 2s are trump) for a card of its printed
      // suit, so say where those cards belong.
      const reminder =
        group === "trump"
          ? "Jokers and trump-rank cards of every suit are trumps too."
          : `A ${suitSingularName(group)} of the trump rank counts as a trump, not a ${suitSingularName(group)}.`;
      return (
        `${capitalized} were led and you still have ${name}, so you must play ${name}. ${reminder} ` +
        `If you have too few ${name}, play them all and fill up with other cards.`
      );
    }
    case "mustPlayTractor": {
      const tractor = violation.length > 2 ? `a tractor of ${violation.length} pairs` : "a tractor";
      return `A tractor was led and you hold ${tractor} in that suit, so you must play it.`;
    }
    case "mustPlayPairs":
      if (violation.required <= 1) {
        return (
          "The lead contains a pair and you have a pair in that suit, so you must play a pair " +
          "(two identical cards)."
        );
      }
      return `The lead contains pairs and you have pairs in that suit, so you must play at least ${violation.required} pairs.`;
  }
}

/** What a follower is obliged to include when they have enough cards of the led group. */
export interface FollowRequirement {
  /** Tractor lengths (in pairs) that must appear, disjoint, in the play. */
  tractorLengths: number[];
  /** Minimum number of pairs (counting the pairs inside required tractors) the play must contain. */
  totalPairs: number;
}

/**
 * Result of checking a multi-component lead ("throw", 甩牌). On failure, `blocker` holds a higher
 * component of the same shape in that suit and the leader must play only `forced` (the
 * lowest-ranked beatable component).
 */
export type ThrowCheck = { type: "ok" } | { type: "fails"; forced: Component; blocker: number };

// MARK: Public rules

/** Lead legality: non-empty, from hand, one suit group. (Throw success is checked separately.) */
export function validateLead(cards: readonly Card[], hand: readonly Card[], trump: Trump): LeadViolation | null {
  if (cards.length === 0) return "empty";
  if (!containsAll(hand, cards)) return "cardsNotInHand";
  if (groupOfCards(cards, trump) === null) return "mixedSuits";
  return null;
}

/** True when the lead has more than one component (a throw). */
export function isThrow(cards: readonly Card[], trump: Trump): boolean {
  return decompose(cards, trump).length > 1;
}

interface Opponent {
  seat: number;
  cards: readonly Card[];
}

/**
 * Checks a throw against every other player's hand. For each component of the throw, another
 * player beats it if they hold, in the same group, a component of the same shape with higher
 * strength. Returns ok for non-throws.
 */
export function checkThrow(cards: readonly Card[], leader: number, hands: readonly (readonly Card[])[], trump: Trump): ThrowCheck {
  const leaderSeat = ((leader % 4) + 4) % 4;
  const opponents: Opponent[] = [];
  for (let step = 1; step < 4; step++) {
    const seat = (leaderSeat + step) % 4;
    if (seat < hands.length) opponents.push({ seat, cards: hands[seat] });
  }
  return throwCheck(cards, opponents, trump);
}

/**
 * Same as `checkThrow` but against a pool of possibly-held cards treated as one hand (bots use the
 * unseen cards). A failure carries blocker = -1.
 */
export function checkThrowAgainstPool(cards: readonly Card[], pool: readonly Card[], trump: Trump): ThrowCheck {
  return throwCheck(cards, [{ seat: -1, cards: pool }], trump);
}

/**
 * Structure the follower must match, given the lead and the follower's cards in the led group.
 * Walk the lead's components largest first; a tractor(k) requires a k-tractor if the follower has
 * a run >= k, otherwise as many pairs as they have (<= k); a pair requires a pair if available.
 */
export function followRequirement(lead: readonly Card[], suitCards: readonly Card[], trump: Trump): FollowRequirement {
  if (lead.length < 2) return { tractorLengths: [], totalPairs: 0 };
  const components = decompose(lead, trump);
  const walk = requirementWalk(components, 0, suitCards, trump);
  return { tractorLengths: walk.tractors, totalPairs: walk.pairs };
}

/**
 * Full follow legality. Returns null if legal.
 *  1. exactly lead.length cards, all from hand;
 *  2. must play min(n, held) cards of the led group;
 *  3. if the player holds >= n of the led group, the play must satisfy `followRequirement`.
 */
export function validateFollow(
  cards: readonly Card[],
  hand: readonly Card[],
  lead: readonly Card[],
  trump: Trump,
): FollowViolation | null {
  const n = lead.length;
  if (cards.length !== n) return { case: "wrongCount", expected: n };
  if (!containsAll(hand, cards)) return { case: "cardsNotInHand" };
  if (lead.length === 0) return null;

  const ledGroup = groupOfCards(lead, trump) ?? groupOf(trump, lead[0]);
  const held = cardsInGroup(hand, ledGroup, trump);
  const playedInGroup = cardsInGroup(cards, ledGroup, trump);
  if (playedInGroup.length < Math.min(n, held.length)) return { case: "mustFollowSuit", group: ledGroup };
  // Short in the led group: everything they had is in the play, the rest can be anything.
  if (held.length < n) return null;

  const requirement = followRequirement(lead, held, trump);
  const lengths = requirement.tractorLengths;
  if (lengths.length > 0 && !containsDisjointTractors(cards, lengths, trump)) {
    let missing = lengths[0];
    for (let count = 1; count <= lengths.length; count++) {
      if (!containsDisjointTractors(cards, lengths.slice(0, count), trump)) {
        missing = lengths[count - 1];
        break;
      }
    }
    return { case: "mustPlayTractor", length: missing };
  }
  if (pairCount(cards) < requirement.totalPairs) {
    return { case: "mustPlayPairs", required: requirement.totalPairs };
  }
  return null;
}

/**
 * Index into `plays` of the play currently winning the (possibly partial) trick. plays[0] is the
 * lead. A later play beats the current winner only if it is entirely in the led group or entirely
 * trump, matches the lead's structure, and its key component is stronger (trump beats non-trump).
 * Ties go to the earlier play.
 */
export function winningIndex(plays: readonly Play[], trump: Trump): number {
  if (plays.length === 0 || plays[0].cards.length === 0) return 0;
  const lead = plays[0].cards;
  const ledGroup = groupOfCards(lead, trump) ?? groupOf(trump, lead[0]);
  const format = leadFormat(lead, trump);
  let bestIndex = 0;
  let bestIsTrump = ledGroup === "trump";
  let bestKey = structureKeyForFormat(lead, format, trump) ?? format.largest?.topStrength ?? 0;

  for (let index = 1; index < plays.length; index++) {
    const cards = plays[index].cards;
    const group = groupOfCards(cards, trump);
    if (group === null || !(group === ledGroup || group === "trump")) continue;
    const key = structureKeyForFormat(cards, format, trump);
    if (key === null) continue;
    const groupIsTrump = group === "trump";
    if (groupIsTrump && !bestIsTrump) {
      bestIndex = index;
      bestIsTrump = true;
      bestKey = key;
    } else if (groupIsTrump === bestIsTrump && key > bestKey) {
      bestIndex = index;
      bestKey = key;
    }
  }
  return bestIndex;
}

/**
 * True if `cards` (played after `lead`) have the same component structure as the lead, all from
 * one group.
 */
export function matchesStructure(cards: readonly Card[], lead: readonly Card[], trump: Trump): boolean {
  return structureKey(cards, lead, trump) !== null;
}

/**
 * The comparison key of `cards` played to `lead`, or null if they don't match the lead's
 * structure: the top strength of the play's component matched to the lead's largest component,
 * maximised over every valid matching. For an all-singles lead it is the play's highest card.
 */
export function structureKey(cards: readonly Card[], lead: readonly Card[], trump: Trump): number | null {
  return structureKeyForFormat(cards, leadFormat(lead, trump), trump);
}

// MARK: Throws

function throwCheck(cards: readonly Card[], opponents: readonly Opponent[], trump: Trump): ThrowCheck {
  const components = decompose(cards, trump);
  if (components.length <= 1) return { type: "ok" };

  let forced: Component | null = null;
  for (const component of components) {
    if (!opponents.some((o) => canBeat(component, o.cards, trump))) continue;
    if (forced === null || ranksLower(component, forced, trump)) forced = component;
  }
  if (forced === null) return { type: "ok" };
  const lowest = forced;
  const blocker = opponents.find((o) => canBeat(lowest, o.cards, trump))?.seat ?? -1;
  return { type: "fails", forced: lowest, blocker };
}

/** True if `cards` hold a component of the same shape and group as `component` with a higher top. */
function canBeat(component: Component, cards: readonly Card[], trump: Trump): boolean {
  const own = cardsInGroup(cards, component.group, trump);
  switch (component.shape.type) {
    case "single":
      return own.some((card) => strength(trump, card) > component.topStrength);
    case "pair":
      return pairsIn(own, trump).some((pair) => strength(trump, pair[0]) > component.topStrength);
    case "tractor":
      return tractorsIn(own, component.shape.pairs, trump).some(
        (tractor) => topStrengthOf(tractor, trump) > component.topStrength,
      );
  }
}

/** Order used to pick the forced component of a failed throw: smaller shape first, then lower strength. */
function ranksLower(a: Component, b: Component, trump: Trump): boolean {
  const countA = shapeCardCount(a.shape);
  const countB = shapeCardCount(b.shape);
  if (countA !== countB) return countA < countB;
  if (a.topStrength !== b.topStrength) return a.topStrength < b.topStrength;
  const keyA = a.cards.length > 0 ? sortKey(trump, a.cards[0]) : 0;
  const keyB = b.cards.length > 0 ? sortKey(trump, b.cards[0]) : 0;
  return keyA < keyB;
}

function topStrengthOf(cards: readonly Card[], trump: Trump): number {
  let top = -1;
  for (const card of cards) top = Math.max(top, strength(trump, card));
  return top;
}

// MARK: Following

interface Walk {
  tractors: number[];
  pairs: number;
}

const EMPTY_WALK: Walk = { tractors: [], pairs: 0 };

/**
 * The greedy walk of DESIGN.md (Following). When a tractor must be removed and several can be, or
 * pairs must be given up for a tractor the follower can't match, the choice that keeps the most
 * tractors for the remaining components is used.
 */
function requirementWalk(components: readonly Component[], index: number, remaining: readonly Card[], trump: Trump): Walk {
  if (index >= components.length) return { tractors: [], pairs: 0 };
  const component = components[index];
  const next = index + 1;
  const reachableTractors = (): number => {
    let count = 0;
    for (let i = next; i < components.length; i++) if (components[i].shape.type === "tractor") count++;
    return count;
  };

  switch (component.shape.type) {
    case "single":
      return requirementWalk(components, next, remaining, trump);

    case "pair": {
      const pairs = pairsIn(remaining, trump);
      if (pairs.length === 0) return requirementWalk(components, next, remaining, trump);
      const sub = requirementWalk(components, next, without(remaining, pairs[0]), trump);
      return { tractors: sub.tractors, pairs: sub.pairs + 1 };
    }

    case "tractor": {
      const length = component.shape.pairs;
      if (longestRun(remaining, trump) >= length) {
        const reachable = reachableTractors();
        let best: Walk | null = null;
        for (const tractor of tractorsIn(remaining, length, trump)) {
          const sub = requirementWalk(components, next, without(remaining, tractor), trump);
          if (best === null || isMoreStructure(sub.tractors, best.tractors)) best = sub;
          if (sub.tractors.length === reachable) break;
        }
        const chosen = best ?? EMPTY_WALK;
        return { tractors: [length, ...chosen.tractors], pairs: chosen.pairs + length };
      }
      // No run long enough: as many pairs as they have, up to `length`.
      const pairs = pairsIn(remaining, trump);
      const count = Math.min(pairs.length, length);
      const reachable = reachableTractors();
      // Pairs that sit next to no other pair can never be part of a tractor, so giving them up
      // first costs nothing. Only if more pairs are owed does the choice matter.
      const loose = pairs.filter((pair) => !isNextToAnotherPair(pair, pairs, trump));
      const linked = pairs.filter((pair) => isNextToAnotherPair(pair, pairs, trump));
      let base = remaining.slice();
      for (const pair of loose.slice(0, count)) base = without(base, pair);
      const stillOwed = count - Math.min(count, loose.length);
      if (stillOwed === 0 || reachable === 0) {
        for (const pair of linked.slice(0, stillOwed)) base = without(base, pair);
        const sub = requirementWalk(components, next, base, trump);
        return { tractors: sub.tractors, pairs: sub.pairs + count };
      }
      // Try every choice of linked pairs and keep the one that leaves the most structure.
      let best: Walk | null = null;
      forEachCombination(linked, 0, stillOwed, [], (chosenPairs) => {
        let left = base;
        for (const pair of chosenPairs) left = without(left, pair);
        const sub = requirementWalk(components, next, left, trump);
        if (best === null || isMoreStructure(sub.tractors, best.tractors)) best = sub;
        return sub.tractors.length === reachable;
      });
      const chosen: Walk = best ?? EMPTY_WALK;
      return { tractors: chosen.tractors, pairs: chosen.pairs + count };
    }
  }
}

/**
 * True if another pair in `pairs` is of the same group and one strength above or below `pair`,
 * so the two could be part of a tractor.
 */
function isNextToAnotherPair(pair: readonly Card[], pairs: readonly (readonly Card[])[], trump: Trump): boolean {
  if (pair.length === 0) return false;
  const card = pair[0];
  const group = groupOf(trump, card);
  const level = strength(trump, card);
  return pairs.some((other) => {
    if (other.length === 0 || groupOf(trump, other[0]) !== group) return false;
    return Math.abs(strength(trump, other[0]) - level) === 1;
  });
}

/**
 * Calls `visit` with every way to pick `size` of `items` from `start` on (in order). Returns true
 * if a visit returned true, which stops the enumeration.
 */
function forEachCombination<T>(
  items: readonly T[],
  start: number,
  size: number,
  chosen: readonly T[],
  visit: (chosen: T[]) => boolean,
): boolean {
  if (chosen.length === size) return visit(chosen.slice());
  if (items.length - start < size - chosen.length) return false;
  let rest = start;
  while (rest < items.length && items.length - rest >= size - chosen.length) {
    const item = items[rest];
    rest += 1;
    if (forEachCombination(items, rest, size, [...chosen, item], visit)) return true;
  }
  return false;
}

/** Swift `Array.lexicographicallyPrecedes` for integer arrays. */
function lexicographicallyPrecedes(a: readonly number[], b: readonly number[]): boolean {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) {
    if (a[i] !== b[i]) return a[i] < b[i];
  }
  return a.length < b.length;
}

function arraysEqual(a: readonly number[], b: readonly number[]): boolean {
  return a.length === b.length && a.every((value, i) => value === b[i]);
}

function sum(values: readonly number[]): number {
  let total = 0;
  for (const value of values) total += value;
  return total;
}

function isMoreStructure(a: readonly number[], b: readonly number[]): boolean {
  if (a.length !== b.length) return a.length > b.length;
  const sumA = sum(a);
  const sumB = sum(b);
  if (sumA !== sumB) return sumA > sumB;
  return !lexicographicallyPrecedes(a, b) && !arraysEqual(a, b);
}

/** True if `cards` contain disjoint tractors of all the given lengths. */
export function containsDisjointTractors(cards: readonly Card[], lengths: readonly number[], trump: Trump): boolean {
  const sorted = lengths.slice().sort((a, b) => b - a);
  return searchTractors(cards, sorted, 0, trump, [], () => true);
}

/**
 * Backtracking search over every way to take disjoint tractors of the given lengths (sorted
 * longest first) out of `cards`. `visit` receives the leftover cards and the chosen tractors;
 * returning true stops the search. Returns true if a visit stopped it.
 */
function searchTractors(
  cards: readonly Card[],
  lengths: readonly number[],
  index: number,
  trump: Trump,
  chosen: readonly Card[][],
  visit: (left: readonly Card[], chosen: readonly Card[][]) => boolean,
): boolean {
  if (index >= lengths.length) return visit(cards, chosen);
  const length = lengths[index];
  // Tractors of equal length are picked in increasing order of their lowest card id, so each set
  // of tractors is tried once instead of once per ordering.
  let floor: number | null = null;
  const previous = chosen.length > 0 ? chosen[chosen.length - 1] : null;
  if (previous !== null && previous.length === 2 * length) floor = Math.min(...previous);
  for (const tractor of tractorsIn(cards, length, trump)) {
    const lowestId = tractor.length > 0 ? Math.min(...tractor) : 0;
    if (floor !== null && lowestId <= floor) continue;
    const left = without(cards, tractor);
    if (searchTractors(left, lengths, index + 1, trump, [...chosen, tractor], visit)) return true;
  }
  return false;
}

// MARK: Winning

/** The shapes making up a lead, computed once per trick. */
interface LeadFormat {
  cardCount: number;
  /** The lead's largest component (the key component). */
  largest: Component | null;
  /** Tractor lengths, longest first. */
  tractorLengths: number[];
  /** Number of plain pair components. */
  pairs: number;
}

function leadFormat(lead: readonly Card[], trump: Trump): LeadFormat {
  const components = decompose(lead, trump);
  const lengths: number[] = [];
  let pairs = 0;
  for (const component of components) {
    if (component.shape.type === "tractor") lengths.push(component.shape.pairs);
    else if (component.shape.type === "pair") pairs += 1;
  }
  return {
    cardCount: lead.length,
    largest: components.length > 0 ? components[0] : null,
    tractorLengths: lengths.sort((a, b) => b - a),
    pairs,
  };
}

function structureKeyForFormat(cards: readonly Card[], format: LeadFormat, trump: Trump): number | null {
  const largest = format.largest;
  if (cards.length === 0 || cards.length !== format.cardCount || largest === null) return null;
  if (groupOfCards(cards, trump) === null) return null;
  const pairsNeeded = format.pairs;

  switch (largest.shape.type) {
    case "single":
      return topStrengthOf(cards, trump);
    case "pair": {
      if (cards.length === 2) {
        // Fast path for the common pair lead.
        return isPair(cards) ? strength(trump, cards[0]) : null;
      }
      const pairs = pairsIn(cards, trump);
      if (pairs.length < pairsNeeded || pairs.length === 0) return null;
      let best = -Infinity;
      for (const pair of pairs) best = Math.max(best, strength(trump, pair[0]));
      return best;
    }
    case "tractor": {
      const keyLength = largest.shape.pairs;
      let best: number | null = null;
      searchTractors(cards, format.tractorLengths, 0, trump, [], (left, chosen) => {
        if (pairCount(left) < pairsNeeded) return false;
        let key = -1;
        for (const tractor of chosen) {
          if (tractor.length === 2 * keyLength) key = Math.max(key, topStrengthOf(tractor, trump));
        }
        best = Math.max(best ?? key, key);
        return key >= BIG_JOKER_STRENGTH;
      });
      return best;
    }
  }
}
