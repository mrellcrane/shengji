// Leading, following, throws and trick winners. Port of Engine/Rules.swift and Engine/RulesSets.swift
// (triples, four of a kind and tractors of them, with three or more decks).

import { containsAll, suitSingularName, without } from "./cards.ts";
import type { Card } from "./cards.ts";
import {
  PAIR,
  allSetsIn,
  cardsInGroup,
  decompose,
  groupOfCards,
  isPair,
  isTractorShape,
  longestRun,
  longestSetRun,
  makeShape,
  maxCopies,
  pairCount,
  pairsIn,
  setTractorShape,
  setTractorsIn,
  setsIn,
  shapeCardCount,
  shapeLength,
  shapeName,
  shapeWidth,
  shapesEqual,
  tractorShape,
  tractorsIn,
  unitsOf,
} from "./combos.ts";
import type { ComboShape, Component } from "./combos.ts";
import { BIG_JOKER_STRENGTH, groupName, groupOf, sortKey, strength } from "./trump.ts";
import type { SuitGroup, Trump } from "./trump.ts";

// MARK: Seats

/**
 * Seats: 0 = South (the human offline), 1 = East, 2 = North (partner), 3 = West. Play goes
 * 0 -> 1 -> 2 -> 3 -> 0. Partners sit opposite; team = seat % 2. Bigger tables (6 or 8 players) go
 * on round the same way: teams alternate, so a team is every even or every odd seat. Functions
 * without `players` are for the classic 4-player table.
 */
export const HUMAN_SEAT = 0;
export const ALL_SEATS: readonly number[] = [0, 1, 2, 3];

/** The seats of a table of `players`, in order. */
export function allSeats(players: number): number[] {
  return Array.from({ length: Math.max(players, 1) }, (_, seat) => seat);
}

export function teamOf(seat: number): number {
  return seat % 2;
}

export function partnerOf(seat: number): number {
  return (seat + 2) % 4;
}

/** `player` as a seat in 0..<players (Swift `Seats.normalized`). */
export function normalizeSeat(player: number, players: number): number {
  const n = Math.max(players, 1);
  return ((player % n) + n) % n;
}

export function nextSeat(seat: number, players = 4): number {
  return players === 4 ? (seat + 1) % 4 : normalizeSeat(seat + 1, players);
}

/** The other seats of `player`'s team, in play order after `player`. */
export function teammatesOf(player: number, players: number): number[] {
  const out: number[] = [];
  for (let step = 2; step < players; step += 2) out.push(normalizeSeat(player + step, players));
  return out;
}

/** The seats of the other team, in play order after `player`. */
export function opponentsOf(player: number, players: number): number[] {
  const out: number[] = [];
  for (let step = 1; step < players; step += 2) out.push(normalizeSeat(player + step, players));
  return out;
}

const COMPASS: Record<number, readonly string[]> = {
  4: ["South", "East", "North", "West"],
  6: ["South", "Southeast", "Northeast", "North", "Northwest", "Southwest"],
  8: ["South", "Southeast", "East", "Northeast", "North", "Northwest", "West", "Southwest"],
};

/**
 * Compass point of a seat when seat 0 is South: South, East, North, West with 4; South, Southeast,
 * Northeast, North, Northwest, Southwest with 6; the eight points with 8.
 */
export function compassName(player: number, players: number): string {
  const names = COMPASS[players] ?? COMPASS[4];
  return names[normalizeSeat(player, names.length)];
}

/**
 * Display name of `seat` as seen from `viewer` (default seat 0, as in Swift `Seats.name`) at a table
 * of `players`: "You", "East", "Partner", "West" with 4; "You" and compass names round the table
 * with 6 or 8 (Swift `Seats.name(_:players:)`). Online, each player sees the table rotated so they
 * are "You".
 */
export function seatName(seat: number, viewer = HUMAN_SEAT, players = 4): string {
  if (players > 4) {
    const relative = normalizeSeat(seat - viewer, players);
    return relative === HUMAN_SEAT ? "You" : compassName(relative, players);
  }
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
  | { case: "mustPlayPairs"; required: number }
  /**
   * Three or more decks: the player holds a tractor of sets of `width` identical cards (a tractor of
   * triples) of the needed length in the led group but didn't play one.
   */
  | { case: "mustPlaySetTractor"; width: number; length: number }
  /**
   * Three or more decks: the player had to play at least `required` sets of `width` identical cards
   * (triples, four of a kind) from the led group.
   */
  | { case: "mustPlaySets"; width: number; required: number };

/** "two", "three", "four", or the digits (Swift `FollowViolation.count`). */
export function countWord(n: number): string {
  switch (n) {
    case 2:
      return "two";
    case 3:
      return "three";
    case 4:
      return "four";
    default:
      return String(n);
  }
}

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
    case "mustPlaySetTractor": {
      const name = shapeName(setTractorShape(violation.width, violation.length));
      return `A ${name} was led and you hold one in that suit, so you must play it.`;
    }
    case "mustPlaySets": {
      if (violation.required <= 1) {
        const one = violation.width === 3 ? "a triple (three identical cards)" : `${countWord(violation.width)} identical cards`;
        return `The lead calls for ${one}, and you hold that in the suit led, so you must play it.`;
      }
      const many = violation.width === 3 ? "triples" : `sets of ${countWord(violation.width)} identical cards`;
      return `The lead calls for ${violation.required} ${many}, and you hold that many in the suit led, so you must play them.`;
    }
  }
}

/** What a follower is obliged to include when they have enough cards of the led group. */
export interface FollowRequirement {
  /** Tractor lengths (in pairs) that must appear, disjoint, in the play. */
  tractorLengths: number[];
  /** Minimum number of pairs (counting the pairs inside required tractors) the play must contain. */
  totalPairs: number;
  /**
   * Every combination the play must contain, disjoint: the tractors, then the sets (each pair once).
   * With two decks these are the `tractorLengths` tractors and the pairs outside them; with more
   * decks they can include triples, four of a kind and tractors of them.
   */
  units: ComboShape[];
}

/** The requirement of tractors and pairs (Swift `FollowRequirement(tractorLengths:totalPairs:)`). */
export function classicRequirement(tractorLengths: readonly number[], totalPairs: number): FollowRequirement {
  const loose = Math.max(0, totalPairs - sum(tractorLengths));
  const units: ComboShape[] = tractorLengths.map((length) => tractorShape(length));
  for (let i = 0; i < loose; i++) units.push(PAIR);
  return { tractorLengths: tractorLengths.slice(), totalPairs, units };
}

/** The requirement of these combinations (Swift `FollowRequirement(units:)`). */
export function unitRequirement(units: readonly ComboShape[]): FollowRequirement {
  const tractorLengths: number[] = [];
  let totalPairs = 0;
  for (const unit of units) {
    if (shapeWidth(unit) !== 2) continue;
    if (isTractorShape(unit)) tractorLengths.push(shapeLength(unit));
    totalPairs += shapeLength(unit);
  }
  return { tractorLengths, totalPairs, units: units.slice() };
}

/** True when only pairs and tractors of pairs are owed (always the case with two decks). */
export function isClassicRequirement(requirement: FollowRequirement): boolean {
  return requirement.units.every((unit) => shapeWidth(unit) <= 2);
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
 * Checks a throw against every other player's hand (`hands` lists every seat: 4, 6 or 8). For each
 * component of the throw, another player beats it if they hold, in the same group, a component of
 * the same shape with higher strength. Returns ok for non-throws.
 */
export function checkThrow(cards: readonly Card[], leader: number, hands: readonly (readonly Card[])[], trump: Trump): ThrowCheck {
  const seats = Math.max(4, hands.length);
  const leaderSeat = ((leader % seats) + seats) % seats;
  const opponents: Opponent[] = [];
  for (let step = 1; step < seats; step++) {
    const seat = (leaderSeat + step) % seats;
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
 * With three or more decks (a face held or led three or more times) the same walk runs over sets
 * of any width (`unitWalk`).
 */
export function followRequirement(lead: readonly Card[], suitCards: readonly Card[], trump: Trump): FollowRequirement {
  if (lead.length < 2) return classicRequirement([], 0);
  const components = decompose(lead, trump);
  if (maxCopies(lead) <= 2 && maxCopies(suitCards) <= 2) {
    const walk = requirementWalk(components, 0, suitCards, trump);
    return classicRequirement(walk.tractors, walk.pairs);
  }
  // Three or more decks: the same walk over sets of any width.
  const walk = unitWalk(components, 0, suitCards, trump);
  return unitRequirement([...walk.tractors, ...walk.sets]);
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
  if (!isClassicRequirement(requirement) || maxCopies(held) > 2) {
    return unitViolation(cards, requirement.units, trump);
  }
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
export function canBeat(component: Component, cards: readonly Card[], trump: Trump): boolean {
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
    case "set":
    case "setTractor":
      return unitsOf(component.shape, own, trump).some((unit) => topStrengthOf(unit, trump) > component.topStrength);
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
    case "set":
    case "setTractor":
      // Sets of three or more never reach this two-deck walk (see `unitWalk`).
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
export function searchTractors(
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
export interface LeadFormat {
  cardCount: number;
  /** The lead's largest component (the key component). */
  largest: Component | null;
  /** Tractor lengths, longest first. */
  tractorLengths: number[];
  /** Number of plain pair components. */
  pairs: number;
  /** Every component bigger than a single, widest first, then longest (three or more decks). */
  units: ComboShape[];
  /** True when the lead is only singles, pairs and tractors of pairs. */
  isClassic: boolean;
}

export function leadFormat(lead: readonly Card[], trump: Trump): LeadFormat {
  const components = decompose(lead, trump);
  const lengths: number[] = [];
  let pairs = 0;
  const units: ComboShape[] = [];
  for (const component of components) {
    if (component.shape.type === "tractor") lengths.push(component.shape.pairs);
    else if (component.shape.type === "pair") pairs += 1;
    if (component.shape.type !== "single") units.push(component.shape);
  }
  return {
    cardCount: lead.length,
    largest: components.length > 0 ? components[0] : null,
    tractorLengths: lengths.sort((a, b) => b - a),
    pairs,
    units: sortedUnits(units),
    isClassic: components.every((component) => shapeWidth(component.shape) <= 2),
  };
}

export function structureKeyForFormat(cards: readonly Card[], format: LeadFormat, trump: Trump): number | null {
  const largest = format.largest;
  if (cards.length === 0 || cards.length !== format.cardCount || largest === null) return null;
  if (groupOfCards(cards, trump) === null) return null;
  if (!format.isClassic || maxCopies(cards) > 2) return unitStructureKey(cards, format, largest.shape, trump);
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
    case "set":
    case "setTractor":
      return unitStructureKey(cards, format, largest.shape, trump);
  }
}

// MARK: Three or more decks: triples, four of a kind and tractors of them
//
// Port of Engine/RulesSets.swift. These rules extend the two-deck rules and agree with them whenever
// no face appears more than twice, so the classic code above is used there and these only run when
// a lead, hand or play holds three or more copies of a face.
//
// Following: walk the lead's components largest first, as with two decks. A set of `w` identical
// cards asks for the widest set you hold up to `w` (a triple led: your triple, else a pair). A
// tractor asks for the same tractor if you hold one, otherwise for each of its steps the widest set
// you hold up to its width (a tractor of pairs: as many pairs as you have, up to its length).
// Winning: a play competes only with the lead's exact structure (a triple beats a triple).

/** Required tractors (any width) and required sets (pairs, triples, ...), in the order found. */
interface UnitWalk {
  tractors: ComboShape[];
  sets: ComboShape[];
}

/**
 * `requirementWalk` over sets of any width. On cards with at most two copies of each face it gives
 * the same answer as `requirementWalk` (the tractors, then each pair once).
 */
function unitWalk(components: readonly Component[], index: number, remaining: readonly Card[], trump: Trump): UnitWalk {
  if (index >= components.length) return { tractors: [], sets: [] };
  const component = components[index];
  const next = index + 1;
  const shape = component.shape;
  const width = shapeWidth(shape);
  if (width < 2) return unitWalk(components, next, remaining, trump);

  if (!isTractorShape(shape)) {
    // A set: the widest set held, up to the lead's width.
    const take = Math.min(width, maxCopies(remaining));
    const set = take >= 2 ? setsIn(remaining, take, trump)[0] : undefined;
    if (set === undefined) return unitWalk(components, next, remaining, trump);
    const sub = unitWalk(components, next, without(remaining, set), trump);
    return { tractors: sub.tractors, sets: [makeShape(take, 1), ...sub.sets] };
  }

  const length = shapeLength(shape);
  const reachable = components.slice(next).filter((c) => isTractorShape(c.shape)).length;
  if (longestSetRun(remaining, width, trump) >= length) {
    let best: UnitWalk | null = null;
    for (const tractor of setTractorsIn(remaining, width, length, trump)) {
      const sub = unitWalk(components, next, without(remaining, tractor), trump);
      if (best === null || isMoreUnitStructure(sub.tractors, best.tractors)) best = sub;
      if (sub.tractors.length === reachable) break;
    }
    const chosen: UnitWalk = best ?? { tractors: [], sets: [] };
    return { tractors: [shape, ...chosen.tractors], sets: chosen.sets };
  }

  if (width === 2) return pairsForTractor(length, components, next, remaining, trump);

  // No tractor that long: for each of its steps, the widest set held up to its width. Sets that sit
  // next to no other set can never join a tractor, so they go first.
  let left = remaining.slice();
  const owed: ComboShape[] = [];
  for (let step = 0; step < length; step++) {
    const take = Math.min(width, maxCopies(left));
    if (take < 2) break;
    const options = allSetsIn(left, take, trump);
    const neighbours = pairsIn(left, trump);
    const pick = options.find((option) => !isNextToAnotherPair(option, neighbours, trump)) ?? options[0];
    if (pick === undefined) break;
    left = without(left, pick);
    owed.push(makeShape(take, 1));
  }
  const sub = unitWalk(components, next, left, trump);
  return { tractors: sub.tractors, sets: [...owed, ...sub.sets] };
}

/**
 * A tractor of pairs the follower can't match: as many pairs as they have, up to its length, chosen
 * as `requirementWalk` does (pairs next to no other pair first, then whichever leaves the most
 * structure). Four identical cards count as two pairs.
 */
function pairsForTractor(
  length: number,
  components: readonly Component[],
  next: number,
  remaining: readonly Card[],
  trump: Trump,
): UnitWalk {
  const pairs = allSetsIn(remaining, 2, trump);
  const count = Math.min(pairs.length, length);
  const owed: ComboShape[] = Array.from({ length: count }, () => PAIR);
  const reachable = components.slice(next).filter((c) => isTractorShape(c.shape)).length;
  const loose = pairs.filter((pair) => !isNextToAnotherPair(pair, pairs, trump));
  const linked = pairs.filter((pair) => isNextToAnotherPair(pair, pairs, trump));
  let base = remaining.slice();
  for (const pair of loose.slice(0, count)) base = without(base, pair);
  const stillOwed = count - Math.min(count, loose.length);
  if (stillOwed === 0 || reachable === 0) {
    for (const pair of linked.slice(0, stillOwed)) base = without(base, pair);
    const sub = unitWalk(components, next, base, trump);
    return { tractors: sub.tractors, sets: [...owed, ...sub.sets] };
  }
  let best: UnitWalk | null = null;
  forEachCombination(linked, 0, stillOwed, [], (chosenPairs) => {
    let left = base;
    for (const pair of chosenPairs) left = without(left, pair);
    const sub = unitWalk(components, next, left, trump);
    if (best === null || isMoreUnitStructure(sub.tractors, best.tractors)) best = sub;
    return sub.tractors.length === reachable;
  });
  const chosen: UnitWalk = best ?? { tractors: [], sets: [] };
  return { tractors: chosen.tractors, sets: [...owed, ...chosen.sets] };
}

/** `isMoreStructure` for tractors of any width: more tractors, then more cards in them, then the same tie-break. */
function isMoreUnitStructure(a: readonly ComboShape[], b: readonly ComboShape[]): boolean {
  if (a.length !== b.length) return a.length > b.length;
  const countsA = a.map(shapeCardCount);
  const countsB = b.map(shapeCardCount);
  const sumA = sum(countsA);
  const sumB = sum(countsB);
  if (sumA !== sumB) return sumA > sumB;
  return !lexicographicallyPrecedes(countsA, countsB) && !arraysEqual(countsA, countsB);
}

/** Shapes in search order: widest first, then longest (stable). Swift `Rules.sortedUnits`. */
export function sortedUnits(units: readonly ComboShape[]): ComboShape[] {
  return units
    .map((shape, offset) => ({ shape, offset }))
    .sort((a, b) => {
      const widthA = shapeWidth(a.shape);
      const widthB = shapeWidth(b.shape);
      if (widthA !== widthB) return widthB - widthA;
      const lengthA = shapeLength(a.shape);
      const lengthB = shapeLength(b.shape);
      if (lengthA !== lengthB) return lengthB - lengthA;
      return a.offset - b.offset;
    })
    .map((u) => u.shape);
}

/**
 * The violation for a play that doesn't contain every owed unit, or null if it does. Names the first
 * owed unit (in the requirement's order) that the play can't hold alongside those before it.
 */
function unitViolation(cards: readonly Card[], units: readonly ComboShape[], trump: Trump): FollowViolation | null {
  if (units.length === 0 || containsUnits(cards, units, trump)) return null;
  let missing = units[0];
  for (let count = 1; count <= units.length; count++) {
    if (!containsUnits(cards, units.slice(0, count), trump)) {
      missing = units[count - 1];
      break;
    }
  }
  const width = shapeWidth(missing);
  if (isTractorShape(missing)) {
    if (width === 2) return { case: "mustPlayTractor", length: shapeLength(missing) };
    return { case: "mustPlaySetTractor", width, length: shapeLength(missing) };
  }
  if (width === 2) {
    let required = 0;
    for (const unit of units) if (shapeWidth(unit) === 2) required += shapeLength(unit);
    return { case: "mustPlayPairs", required };
  }
  return { case: "mustPlaySets", width, required: units.filter((unit) => shapesEqual(unit, missing)).length };
}

/** True if `cards` hold disjoint combinations of all the given shapes. */
export function containsUnits(cards: readonly Card[], units: readonly ComboShape[], trump: Trump): boolean {
  return searchUnits(cards, sortedUnits(units), 0, trump, [], () => true);
}

/** A combination chosen by `searchUnits`. */
export interface ChosenUnit {
  shape: ComboShape;
  cards: Card[];
}

/**
 * Backtracking search over every way to take disjoint combinations of the given shapes (in that
 * order) out of `cards`. `visit` gets the leftover cards and the chosen combinations with their
 * shapes; returning true stops the search. Returns true if a visit stopped it. Swift `Rules.searchUnits`.
 */
export function searchUnits(
  cards: readonly Card[],
  shapes: readonly ComboShape[],
  index: number,
  trump: Trump,
  chosen: readonly ChosenUnit[],
  visit: (left: readonly Card[], chosen: readonly ChosenUnit[]) => boolean,
): boolean {
  if (index >= shapes.length) return visit(cards, chosen);
  const shape = shapes[index];
  // Combinations of the same shape are picked in increasing order of their lowest card id, so each
  // set of them is tried once instead of once per ordering.
  let floor: number | null = null;
  const previous = chosen.length > 0 ? chosen[chosen.length - 1] : null;
  if (previous !== null && shapesEqual(previous.shape, shape) && previous.cards.length > 0) {
    floor = Math.min(...previous.cards);
  }
  for (const unit of unitsOf(shape, cards, trump)) {
    const lowestId = unit.length > 0 ? Math.min(...unit) : 0;
    if (floor !== null && lowestId <= floor) continue;
    if (searchUnits(without(cards, unit), shapes, index + 1, trump, [...chosen, { shape, cards: unit }], visit)) {
      return true;
    }
  }
  return false;
}

/**
 * `structureKey` for leads or plays with sets of three or more: the play must hold every component
 * of the lead bigger than a single (singles are free); the key is the top strength of the play's
 * combination matched to the lead's largest component, maximised over every matching.
 */
function unitStructureKey(cards: readonly Card[], format: LeadFormat, keyShape: ComboShape, trump: Trump): number | null {
  if (keyShape.type === "single") return cards.length > 0 ? topStrengthOf(cards, trump) : null;
  let best: number | null = null;
  searchUnits(cards, format.units, 0, trump, [], (_, chosen) => {
    let key = -1;
    for (const unit of chosen) {
      if (shapesEqual(unit.shape, keyShape)) key = Math.max(key, topStrengthOf(unit.cards, trump));
    }
    best = Math.max(best ?? key, key);
    return key >= BIG_JOKER_STRENGTH;
  });
  return best;
}
