// Per-seat views (view.ts): what each player may see (DESIGN.md, Privacy).

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, Round, SeatView } from "../src/engine/index.ts";
import { randomBidding, randomBury, randomPlay } from "./play.ts";
import { seededRandom } from "./support.ts";
import type { Rng } from "./support.ts";

/** Cards revealed by the rules: declarations, bids, the kitty flip card, and everything played. */
function publicCards(round: Round): Set<Card> {
  const cards = new Set<Card>();
  for (const d of round.declarationHistory) for (const card of d.cards) cards.add(card);
  for (const b of round.bidding?.bids ?? []) for (const card of b.declaration?.cards ?? []) cards.add(card);
  if (round.trumpFromKitty !== null) cards.add(round.trumpFromKitty);
  for (const card of E.playedCards(round)) cards.add(card);
  return cards;
}

/** Cards `seat` must not see: other hands, undealt cards, and the kitty unless allowed. */
function hiddenCards(round: Round, seat: number): Card[] {
  const revealed = publicCards(round);
  const hidden = new Set<Card>();
  round.hands.forEach((hand, s) => {
    if (s !== seat) for (const card of hand) hidden.add(card);
  });
  for (const card of round.undealt) hidden.add(card);
  if (!E.canSeeKitty(round, seat)) for (const card of round.kitty) hidden.add(card);
  // The seat's own cards are never hidden from it (the dealer's hand holds the kitty while burying).
  for (const card of round.hands[seat]) hidden.delete(card);
  for (const card of revealed) hidden.delete(card);
  return Array.from(hidden).sort((a, b) => a - b);
}

/** Every card id in the card-carrying fields of a view. */
function cardsInView(view: SeatView): Card[] {
  const cards: Card[] = [...view.hand, ...(view.kitty ?? [])];
  const add = (list: readonly Card[]): void => {
    cards.push(...list);
  };
  if (view.declaration) add(view.declaration.cards);
  for (const d of view.declarationHistory) add(d.cards);
  for (const b of view.bidding?.bids ?? []) add(b.declaration?.cards ?? []);
  for (const d of view.availableBids) add(d.cards);
  for (const p of view.currentTrick) add(p.cards);
  for (const t of view.tricks) for (const p of t.plays) add(p.cards);
  if (view.trumpFromKitty !== null) cards.push(view.trumpFromKitty);
  if (view.result) add(view.result.kitty);
  return cards;
}

/** Every number anywhere in a JSON value, with the path to it. */
function numbersIn(value: unknown, path = "", out: [string, number][] = []): [string, number][] {
  if (typeof value === "number") out.push([path, value]);
  else if (Array.isArray(value)) value.forEach((v, i) => numbersIn(v, `${path}[${i}]`, out));
  else if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) numbersIn(v, `${path}.${k}`, out);
  }
  return out;
}

/** The round with the hidden cards of `seat` swapped among themselves by a random permutation. */
function permuteHidden(round: Round, seat: number, rng: Rng): Round {
  const hidden = hiddenCards(round, seat);
  const image = rng.shuffle(hidden);
  const map = new Map<Card, Card>(hidden.map((card, i) => [card, image[i]]));
  const swap = (card: Card): Card => map.get(card) ?? card;
  const copy = E.cloneRound(round);
  copy.hands = copy.hands.map((hand) => hand.map(swap));
  copy.undealt = copy.undealt.map(swap);
  copy.kitty = copy.kitty.map(swap);
  return copy;
}

/** Snapshots of random rounds at every stage: dealing (offline), bidding, burying, playing, finished. */
function randomStates(seed: number, count: number): Round[] {
  const rng = seededRandom(seed);
  const states: Round[] = [];
  for (let n = 0; n < count; n++) {
    const dealer = rng.chance(25) ? null : rng.below(4);
    const round = E.newRound(E.ALL_RANKS[rng.below(13)], dealer, rng.shuffle(E.doubleDeck()));
    if (rng.chance(15)) {
      // Offline-style dealing part way, with undealt cards.
      for (let k = rng.below(100); k > 0; k--) E.dealNext(round);
      const seat = rng.below(4);
      const options = E.availableDeclarations(round, seat);
      if (options.length > 0) assert.equal(E.declare(round, rng.pick(options)), null);
      states.push(E.cloneRound(round));
      continue;
    }
    const firstBidder = dealer ?? rng.below(4);
    assert.equal(E.startBidding(round, firstBidder), null);
    // Part way through bidding.
    for (let k = rng.below(6); k > 0 && E.biddingTurn(round) !== null; k--) {
      const seat = E.biddingTurn(round) as number;
      const options = E.availableBids(round, seat);
      assert.equal(E.bid(round, seat, options.length > 0 && rng.chance(40) ? rng.pick(options) : "pass"), null);
    }
    states.push(E.cloneRound(round));
    if (E.biddingTurn(round) !== null) {
      // Finish bidding from here with random choices.
      while (E.biddingTurn(round) !== null) {
        const seat = E.biddingTurn(round) as number;
        const options = E.availableBids(round, seat);
        assert.equal(E.bid(round, seat, options.length > 0 && rng.chance(30) ? rng.pick(options) : "pass"), null);
      }
    }
    states.push(E.cloneRound(round)); // burying
    randomBury(round, rng);
    const stop = rng.below(110);
    for (let k = 0; round.phase === "playing" && k < stop; k++) randomPlay(round, rng);
    states.push(E.cloneRound(round)); // playing (or finished)
    while (round.phase === "playing") randomPlay(round, rng);
    states.push(E.cloneRound(round)); // finished
  }
  return states;
}

test("a view holds the seat's own hand, counts and public information only", () => {
  const rng = seededRandom(1);
  const round = E.newRound(2, 0, rng.shuffle(E.doubleDeck()));
  randomBidding(round, 0, rng);
  const dealer = round.dealer as number;
  for (const seat of [0, 1, 2, 3]) {
    const view = E.viewFor(round, seat);
    assert.equal(view.seat, seat);
    assert.deepEqual(view.hand, E.sortCards(round.trump, round.hands[seat]));
    assert.deepEqual(view.handCounts, round.hands.map((h) => h.length));
    assert.equal(view.undealtCount, 0);
    assert.equal(view.kittyCount, 8);
    assert.deepEqual(view.declarers, [dealer, (dealer + 2) % 4]);
    assert.equal(view.declarerTeam, dealer % 2);
    for (const key of ["hands", "undealt"]) assert.ok(!(key in view), `view must not have ${key}`);
  }
});

test("the kitty is shown to the dealer while holding it and after burying it, to everyone once finished", () => {
  const rng = seededRandom(2);
  const round = E.newRound(7, 1, rng.shuffle(E.doubleDeck()));
  const original = round.kitty.slice();
  assert.equal(E.startBidding(round, 1), null);
  for (const seat of [0, 1, 2, 3]) assert.equal(E.viewFor(round, seat).kitty, null, "hidden while bidding");
  while (E.biddingTurn(round) !== null) assert.equal(E.bid(round, E.biddingTurn(round) as number, "pass"), null);
  assert.equal(round.phase, "burying");
  assert.deepEqual(E.viewFor(round, 1).kitty, original, "the dealer holds the kitty");
  for (const seat of [0, 2, 3]) assert.equal(E.viewFor(round, seat).kitty, null);

  const buried = rng.sample(round.hands[1], 8);
  assert.equal(E.bury(round, buried, 1), null);
  assert.deepEqual(E.viewFor(round, 1).kitty, buried, "the dealer knows what they buried");
  for (const seat of [0, 2, 3]) assert.equal(E.viewFor(round, seat).kitty, null);

  while ((round.phase as E.RoundPhase) === "playing") randomPlay(round, rng);
  for (const seat of [0, 1, 2, 3]) {
    const view = E.viewFor(round, seat);
    assert.deepEqual(view.kitty, buried, "revealed at the end");
    assert.deepEqual(view.result, round.result);
  }
});

test("only the seat to bid gets bids in its view", () => {
  const rng = seededRandom(3);
  for (let n = 0; n < 50; n++) {
    const round = E.newRound(E.ALL_RANKS[rng.below(13)], null, rng.shuffle(E.doubleDeck()));
    assert.equal(E.startBidding(round, rng.below(4)), null);
    const turn = E.biddingTurn(round) as number;
    for (const seat of [0, 1, 2, 3]) {
      const view = E.viewFor(round, seat);
      assert.equal(view.bidding?.turn, turn);
      assert.deepEqual(view.availableBids, seat === turn ? E.availableDeclarations(round, seat) : []);
    }
  }
});

test("privacy: no hidden card ever appears in another seat's view (random states, every stage)", () => {
  const states = randomStates(4, 120);
  const phases = new Set(states.map((s) => s.phase));
  assert.deepEqual([...phases].sort(), ["burying", "dealing", "finished", "playing"]);
  let checked = 0;
  for (const round of states) {
    for (const seat of [0, 1, 2, 3]) {
      const view = E.viewFor(round, seat);
      const hidden = new Set(hiddenCards(round, seat));
      for (const card of cardsInView(view)) {
        assert.ok(!hidden.has(card), `seat ${seat} sees hidden card ${E.cardDescription(card)} in phase ${round.phase}`);
      }
      // Belt and braces: the only numbers that look like hidden cards sit in non-card fields.
      for (const [path, value] of numbersIn(view)) {
        if (!hidden.has(value)) continue;
        assert.match(path, /^\.(seat|trumpRank|dealer|declarerTeam|declarers\[\d\]|handCounts\[\d\]|undealtCount|kittyCount|turn|leader|defenderPoints|trump\.(rank|suit)|.*\.(player|seat|suit|strength|winner|points|firstBidder|turn|passes|rank|dealer|declarerTeam|trickPoints|kittyPoints|kittyMultiplier|defenderPoints|levels|lastTrickWinner))$/,
          `seat ${seat}: hidden card id ${value} at ${path}`);
      }
      checked++;
    }
  }
  assert.ok(checked >= 1500);
});

test("privacy: a view is unchanged when the hidden cards are shuffled among the hidden places", () => {
  const rng = seededRandom(5);
  const states = randomStates(6, 100);
  let informative = 0;
  for (const round of states) {
    for (const seat of [0, 1, 2, 3]) {
      if (hiddenCards(round, seat).length >= 2) informative++;
      const view = E.viewFor(round, seat);
      for (let k = 0; k < 3; k++) {
        const other = permuteHidden(round, seat, rng);
        assert.deepEqual(E.viewFor(other, seat), view, `seat ${seat}, phase ${round.phase}: the view depends on hidden cards`);
      }
    }
  }
  assert.ok(informative > 1000);
  // Control: the same permutation does change other seats' views (the test can see a leak).
  const round = states.find((s) => s.phase === "playing") as Round;
  const other = permuteHidden(round, 0, rng);
  assert.notDeepEqual(E.viewFor(other, 1), E.viewFor(round, 1));
});

test("views are JSON data and share nothing with the round", () => {
  for (const round of randomStates(7, 20)) {
    for (const seat of [0, 1, 2, 3]) {
      const view = E.viewFor(round, seat);
      assert.deepEqual(JSON.parse(JSON.stringify(view)), view);
      const before = JSON.stringify(round);
      view.hand.push(999);
      view.handCounts[0] = -1;
      view.trump.rank = 14;
      view.declarationHistory.forEach((d) => d.cards.push(999));
      view.tricks.forEach((t) => t.plays.forEach((p) => p.cards.push(999)));
      view.currentTrick.forEach((p) => p.cards.push(999));
      view.kitty?.push(999);
      if (view.result) view.result.kitty.push(999);
      view.bidding?.bids.forEach((b) => b.declaration?.cards.push(999));
      assert.equal(JSON.stringify(round), before);
    }
  }
});

test("viewFor rejects a seat outside 0...3", () => {
  const round = E.newRound(2, 0, E.doubleDeck());
  for (const seat of [-1, 4, 0.5]) assert.throws(() => E.viewFor(round, seat), RangeError);
});
