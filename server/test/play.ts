// Random players for simulations: legal leads, and legal follows found by searching candidate
// plays with validateFollow (the candidates always include one built from the follow rules, so the
// search cannot come up empty).

import assert from "node:assert/strict";
import * as E from "../src/engine/index.ts";
import type { Card, Round, Trump } from "../src/engine/index.ts";
import type { Rng } from "./support.ts";

function groupsOf(hand: readonly Card[], trump: Trump): Card[][] {
  const groups = new Map<E.SuitGroup, Card[]>();
  for (const card of hand.slice().sort((a, b) => a - b)) {
    const group = E.groupOf(trump, card);
    const list = groups.get(group);
    if (list) list.push(card);
    else groups.set(group, [card]);
  }
  return Array.from(groups.values());
}

/** A random lead: singles, pairs, tractors, throws (which may fail) and whole short suits. */
export function randomLead(hand: readonly Card[], trump: Trump, rng: Rng): Card[] {
  const group = rng.pick(groupsOf(hand, trump));
  const roll = rng.below(100);
  if (roll < 15) {
    const longest = E.longestRun(group, trump);
    if (longest >= 2) {
      const tractors = E.tractorsIn(group, 2 + rng.below(longest - 1), trump);
      if (tractors.length > 0) return rng.pick(tractors);
    }
  }
  if (roll < 40) {
    const pairs = E.pairsIn(group, trump);
    if (pairs.length > 0) return rng.pick(pairs);
  }
  if (roll < 55 && group.length >= 2) return rng.sample(group, 2 + rng.below(Math.min(5, group.length - 1)));
  if (roll < 60 && group.length <= 6) return group.slice();
  return [rng.pick(group)];
}

/** Disjoint tractors of the given lengths in `cards`, or null. */
function disjointTractors(cards: readonly Card[], lengths: readonly number[], trump: Trump, rng: Rng): Card[][] | null {
  if (lengths.length === 0) return [];
  for (const tractor of rng.shuffle(E.tractorsIn(cards, lengths[0], trump))) {
    const more = disjointTractors(E.without(cards, tractor), lengths.slice(1), trump, rng);
    if (more !== null) return [tractor, ...more];
  }
  return null;
}

/** Candidate follows: random picks from the led group, structured picks, ruffs, anything. */
export function followCandidates(hand: readonly Card[], lead: readonly Card[], trump: Trump, rng: Rng): Card[][] {
  const n = lead.length;
  const ledGroup = E.groupOfCards(lead, trump) ?? E.groupOf(trump, lead[0]);
  const held = E.cardsInGroup(hand, ledGroup, trump);
  const others = hand.filter((card) => !held.includes(card));
  const candidates: Card[][] = [];
  for (let k = 0; k < 4; k++) {
    const fromGroup = rng.sample(held, Math.min(n, held.length));
    candidates.push([...fromGroup, ...rng.sample(others, n - fromGroup.length)]);
  }
  // Pairs and tractors of the led group first, then other led-group cards.
  const structured: Card[] = [];
  let pool = held.slice();
  for (let length = E.longestRun(pool, trump); length >= 2; length--) {
    for (const tractor of rng.shuffle(E.tractorsIn(pool, length, trump))) {
      if (structured.length + tractor.length <= n && E.containsAll(pool, tractor)) {
        structured.push(...tractor);
        pool = E.without(pool, tractor);
      }
    }
  }
  for (const pair of rng.shuffle(E.pairsIn(pool, trump))) {
    if (structured.length + 2 <= n) {
      structured.push(...pair);
      pool = E.without(pool, pair);
    }
  }
  structured.push(...rng.sample(pool, n - structured.length));
  structured.push(...rng.sample(others, n - structured.length));
  candidates.push(structured);
  // Built from the follow requirement: always legal.
  candidates.push(constructiveFollow(hand, lead, trump, rng));
  // A ruff with the lead's shapes when void.
  if (held.length === 0 && ledGroup !== "trump") {
    let trumps = E.cardsInGroup(hand, "trump", trump);
    const ruff: Card[] = [];
    for (const component of E.decompose(lead, trump)) {
      const options = E.componentsOf(component.shape, trumps, trump);
      if (options.length === 0) break;
      const chosen = rng.pick(options);
      ruff.push(...chosen.cards);
      trumps = E.without(trumps, chosen.cards);
    }
    if (ruff.length === n) candidates.push(ruff, ruff);
  }
  candidates.push(rng.sample(hand, n));
  return candidates;
}

/** A legal follow built from the rules: required tractors, then pairs, then random filler. */
export function constructiveFollow(hand: readonly Card[], lead: readonly Card[], trump: Trump, rng: Rng): Card[] {
  const n = lead.length;
  const ledGroup = E.groupOfCards(lead, trump) ?? E.groupOf(trump, lead[0]);
  const held = E.cardsInGroup(hand, ledGroup, trump);
  const others = hand.filter((card) => !held.includes(card));
  if (held.length <= n) return [...held, ...rng.sample(others, n - held.length)];
  const requirement = E.followRequirement(lead, held, trump);
  let pool = held.slice();
  const play: Card[] = [];
  for (const tractor of disjointTractors(pool, requirement.tractorLengths, trump, rng) ?? []) {
    play.push(...tractor);
    pool = E.without(pool, tractor);
  }
  let pairs = requirement.tractorLengths.reduce((a, b) => a + b, 0);
  const available = rng.shuffle(E.pairsIn(pool, trump));
  while (pairs < requirement.totalPairs && available.length > 0) {
    const pair = available.pop() as Card[];
    play.push(...pair);
    pool = E.without(pool, pair);
    pairs++;
  }
  play.push(...rng.sample(pool, n - play.length));
  return play;
}

/** A random legal follow: the candidates that validateFollow accepts, one picked at random. */
export function randomFollow(hand: readonly Card[], lead: readonly Card[], trump: Trump, rng: Rng): Card[] {
  const legal = followCandidates(hand, lead, trump, rng).filter(
    (cards) => E.validateFollow(cards, hand, lead, trump) === null,
  );
  assert.ok(legal.length > 0, `no legal follow to ${E.shortText(lead)} from ${E.shortText(hand)}`);
  return rng.pick(legal);
}

/** Starts online bidding and runs it to the end with random choices. */
export function randomBidding(round: Round, firstBidder: number, rng: Rng, declarePercent = 30): void {
  assert.equal(E.startBidding(round, firstBidder), null);
  finishBidding(round, rng, declarePercent);
}

/** Runs open bidding to the end with random choices (`declarePercent` of turns declare when possible). */
export function finishBidding(round: Round, rng: Rng, declarePercent = 30): void {
  for (let turns = 0; E.biddingTurn(round) !== null; turns++) {
    assert.ok(turns < 50, "bidding did not end");
    const seat = E.biddingTurn(round) as number;
    const options = E.availableBids(round, seat);
    const choice = options.length > 0 && rng.chance(declarePercent) ? rng.pick(options) : "pass";
    assert.equal(E.bid(round, seat, choice), null);
  }
}

/** The dealer buries 8 random cards. */
export function randomBury(round: Round, rng: Rng): void {
  const dealer = round.dealer as number;
  assert.equal(E.bury(round, rng.sample(round.hands[dealer], E.KITTY_SIZE), dealer), null);
}

/** One random legal play by the seat whose turn it is. */
export function randomPlay(round: Round, rng: Rng): { player: number; cards: Card[]; result: E.PlayResult } {
  const player = E.turn(round) as number;
  const hand = round.hands[player];
  const cards = round.currentTrick.length === 0
    ? randomLead(hand, round.trump, rng)
    : randomFollow(hand, E.currentLead(round), round.trump, rng);
  const result = E.play(round, cards, player);
  assert.ok(result.ok, `play rejected: ${result.ok ? "" : E.roundErrorExplanation(result.error)}`);
  return { player, cards, result };
}
