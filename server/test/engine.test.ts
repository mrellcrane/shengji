// Unit tests for the parts of the engine the vectors do not reach: the crypto shuffle, input
// validation, JSON helpers and viewer-relative wording for online play.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, Rank, RoundResult } from "../src/engine/index.ts";
import { buildDeck, seededRandom } from "./support.ts";

// MARK: Shuffle

test("shuffledDeck is a permutation of the 108 cards and leaves its input alone", () => {
  for (let n = 0; n < 50; n++) {
    const deck = E.shuffledDeck();
    assert.ok(E.isFullDeck(deck));
    assert.deepEqual(deck.slice().sort((a, b) => a - b), E.doubleDeck());
  }
  const input = [1, 2, 3, 4, 5];
  const out = E.shuffle(input);
  assert.deepEqual(input, [1, 2, 3, 4, 5]);
  assert.notEqual(out, input);
  assert.deepEqual(E.shuffle([]), []);
  assert.deepEqual(E.shuffle([7]), [7]);
});

test("randomInt rejects the incomplete top bucket (no modulo bias)", () => {
  // bound 3: 2^32 % 3 = 1, so 0xFFFFFFFF (the one value of the incomplete bucket) is drawn again.
  const draws = [0xffffffff, 0xffffffff, 7];
  const source: E.RandomSource = (array) => {
    array[0] = draws.shift() as number;
    return array;
  };
  assert.equal(E.randomInt(3, source), 7 % 3);
  assert.equal(draws.length, 0);
  // bound 2^31 + 1: the accepted range is 0..<2^31 + 1, almost half of all values are drawn again.
  const big = 2 ** 31 + 1;
  const values = [2 ** 31 + 5, 2 ** 32 - 1, 2 ** 31 + 1, 2 ** 31];
  const bigSource: E.RandomSource = (array) => {
    array[0] = values.shift() as number;
    return array;
  };
  assert.equal(E.randomInt(big, bigSource), 2 ** 31);
  assert.equal(values.length, 0);
  assert.equal(E.randomInt(1, () => assert.fail("bound 1 needs no randomness")), 0);
  for (const bad of [0, -1, 1.5, 2 ** 32 + 1, Number.NaN]) assert.throws(() => E.randomInt(bad), RangeError);
  assert.equal(E.randomInt(2 ** 32, (a) => ((a[0] = 123), a)), 123);
});

test("shuffle is uniform: every ordering of 3 items and every deck position equally likely", () => {
  const counts = new Map<string, number>();
  const trials = 60000;
  for (let i = 0; i < trials; i++) {
    const key = E.shuffle(["a", "b", "c"]).join("");
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  assert.equal(counts.size, 6);
  // Chi-square with 5 degrees of freedom; 25 is far beyond the 0.999 quantile (20.5).
  const expected = trials / 6;
  let chi = 0;
  for (const count of counts.values()) chi += (count - expected) ** 2 / expected;
  assert.ok(chi < 25, `chi-square ${chi.toFixed(1)}`);

  // Where card 0 lands over many decks: 108 positions, 99 degrees of freedom (0.999 quantile ~149).
  const positions = new Array<number>(108).fill(0);
  const decks = 21600;
  for (let i = 0; i < decks; i++) positions[E.shuffledDeck().indexOf(0)]++;
  const per = decks / 108;
  const chiDeck = positions.reduce((sum, count) => sum + (count - per) ** 2 / per, 0);
  assert.ok(chiDeck < 170, `chi-square ${chiDeck.toFixed(1)}`);
});

test("cryptoRandomSource uses crypto.getRandomValues", () => {
  const array = new Uint32Array(4);
  assert.equal(E.cryptoRandomSource(array), array);
  assert.ok(array.some((v) => v !== 0));
});

// MARK: Cards and validation

test("card ids follow the wire format (face index + copy * 54)", () => {
  assert.equal(E.makeCard(2, E.SPADES), 0);
  assert.equal(E.makeCard(14, E.SPADES), 12);
  assert.equal(E.makeCard(2, E.HEARTS), 13);
  assert.equal(E.makeCard(14, E.DIAMONDS, 1), 105);
  assert.equal(E.smallJoker(), 52);
  assert.equal(E.bigJoker(1), 107);
  assert.equal(E.cardDescription(E.makeCard(10, E.HEARTS, 1)), "10♥");
  assert.equal(E.cardLongName(E.bigJoker()), "big joker");
  assert.equal(E.copyOf(53), 0);
  assert.equal(E.copyOf(54), 1);
  assert.deepEqual([E.isCard(0), E.isCard(107), E.isCard(108), E.isCard(-1), E.isCard(1.5), E.isCard("3")],
    [true, true, false, false, false, false]);
});

test("removeCards removes each card once, keeps order, and fails as a whole", () => {
  assert.deepEqual(E.removeCards([5, 1, 9, 1], [1, 9]), [5, 1]);
  assert.equal(E.removeCards([5, 1], [1, 1]), null);
  assert.equal(E.removeCards([5, 1], [2]), null);
  assert.deepEqual(E.without([5, 1], [2]), [5, 1]);
  assert.ok(E.containsAll([3, 3, 4], [3, 3]));
  assert.ok(!E.containsAll([3, 4], [3, 3]));
});

test("newRound accepts only a full 108-card deck and normalises the dealer", () => {
  const deck = E.doubleDeck();
  assert.throws(() => E.newRound(2, 0, deck.slice(1)), RangeError);
  assert.throws(() => E.newRound(2, 0, [...deck.slice(1), 1]), RangeError);
  assert.doesNotThrow(() => E.newRound(2, 0, [...deck.slice(1), 0]));
  assert.throws(() => E.newRound(2, 0, [...deck.slice(1), 1.5]), RangeError);
  assert.throws(() => E.newRound(2, 0, [...deck.slice(1), 108]), RangeError);
  assert.equal(E.newRound(2, 5, deck).dealer, 1);
  assert.equal(E.newRound(2, -1, deck).dealer, 3);
  assert.throws(() => E.newRound(2, 1.5, deck), RangeError);
  const round = E.newRound(2, null, deck);
  assert.equal(round.dealer, null);
  assert.equal(round.nextToReceive, 0);
  assert.equal(round.bidding, null);
  assert.deepEqual(JSON.parse(JSON.stringify(round)), round);
});

test("parseDeclaration accepts well-formed declarations only", () => {
  const good = { player: 1, cards: [13, 67], suit: 1, strength: 2 };
  assert.deepEqual(E.parseDeclaration(good), good);
  assert.notEqual(E.parseDeclaration(good)?.cards, good.cards, "copies the cards");
  assert.deepEqual(E.parseDeclaration({ player: 0, cards: [52, 106], suit: null, strength: 3 }),
    { player: 0, cards: [52, 106], suit: null, strength: 3 });
  for (const bad of [
    null, 3, "x", [], {},
    { ...good, player: "1" }, { ...good, player: 1.5 },
    { ...good, cards: [13, 67, 13] }, { ...good, cards: [13, 200] }, { ...good, cards: "13" },
    { ...good, suit: 4 }, { ...good, suit: "1" }, { ...good, strength: "2" },
  ]) {
    assert.equal(E.parseDeclaration(bad), null, JSON.stringify(bad));
  }
});

test("parseDeclaration reads a missing suit as no trump suit (how Swift's Codable sends nil)", () => {
  // The iOS app encodes Declaration with JSONEncoder, which leaves out a nil optional: a joker-pair
  // declaration arrives without a "suit" key.
  const fromSwift = JSON.parse('{"player":3,"cards":[52,106],"strength":3}') as unknown;
  assert.deepEqual(E.parseDeclaration(fromSwift), { player: 3, cards: [52, 106], suit: null, strength: 3 });
  assert.deepEqual(E.parseDeclaration({ player: 0, cards: [53, 107], suit: undefined, strength: 4 }),
    { player: 0, cards: [53, 107], suit: null, strength: 4 });

  // And such a bid is accepted: seat 2 holds both small jokers.
  const round = E.newRound(5, 1, buildDeck([[], [], [52, 106], []], [], 1, 3));
  assert.equal(E.startBidding(round, 1), null);
  assert.equal(E.bid(round, 1, "pass"), null);
  const parsed = E.parseDeclaration(JSON.parse('{"player":2,"cards":[52,106],"strength":3}')) as E.Declaration;
  assert.equal(E.bid(round, 2, parsed), null);
  assert.equal(round.declaration?.suit, null);
  assert.equal(round.declaration?.strength, 3);
});

test("bid and declare reject malformed declarations without throwing or changing the round", () => {
  const round = E.newRound(5, 0, E.doubleDeck());
  assert.equal(E.startBidding(round, 0), null);
  const seat = 0;
  const option = E.availableBids(round, seat)[0];
  assert.ok(option, "seat 0 has something to declare");
  const malformed: unknown[] = [
    null, undefined, 7, "pass!", [],
    { ...option, cards: undefined }, { ...option, cards: null }, { ...option, cards: "52" },
    { ...option, cards: [undefined] }, { ...option, suit: "x" }, { ...option, strength: undefined },
    { player: seat },
  ];
  for (const bad of malformed) {
    const before = JSON.stringify(round);
    assert.deepEqual(E.bid(round, seat, bad as E.Declaration), { case: "invalidDeclaration" }, JSON.stringify(bad));
    assert.equal(JSON.stringify(round), before);
  }
  const offline = E.newRound(5, 0, E.doubleDeck());
  E.dealAll(offline);
  for (const bad of malformed) {
    const before = JSON.stringify(offline);
    assert.deepEqual(E.declare(offline, bad as E.Declaration), { case: "invalidDeclaration" }, JSON.stringify(bad));
    assert.equal(JSON.stringify(offline), before);
  }
});

test("recordRound keeps its own copy of the result, like the Swift value type", () => {
  const rng = seededRandom(12);
  const game = E.newGame();
  const round = E.newRound(2, 0, rng.shuffle(E.doubleDeck()));
  E.dealAll(round);
  E.finishDealing(round);
  assert.equal(E.bury(round, round.hands[0].slice(0, 8)), null);
  while (round.phase === "playing") {
    const player = E.turn(round) as number;
    const lead = E.currentLead(round);
    const hand = round.hands[player];
    const cards = lead.length === 0
      ? [hand[0]]
      : (() => {
          const ledGroup = E.groupOfCards(lead, round.trump) ?? E.groupOf(round.trump, lead[0]);
          const held = E.cardsInGroup(hand, ledGroup, round.trump);
          return held.length > 0 ? [held[0]] : [hand[0]];
        })();
    assert.ok(E.play(round, cards, player).ok);
  }
  const result = round.result as RoundResult;
  const summary = E.recordRound(game, result);
  const stored = JSON.stringify(game);
  // The server rotates seats for each viewer: changing the round's result (or the returned summary's)
  // must not rewrite the game history.
  result.dealer = 3;
  result.kitty.push(999);
  result.outcome.summary = "changed";
  result.trump.suit = 2;
  assert.equal(JSON.stringify(game), stored);
  summary.result.dealer = 2;
  summary.levelsAfter[0] = 14;
  assert.equal(JSON.stringify(game), stored);
});

test("bury checks the burying seat when one is given", () => {
  const rng = seededRandom(1);
  const round = E.newRound(2, 2, rng.shuffle(E.doubleDeck()));
  E.dealAll(round);
  E.finishDealing(round);
  const cards = round.hands[2].slice(0, 8);
  assert.deepEqual(E.bury(round, cards, 1), { case: "notYourTurn" });
  assert.equal(round.phase, "burying");
  assert.equal(E.bury(round, cards, 2), null);
  assert.equal(round.phase, "playing");
});

test("startOnlineRound opens bidding at the creator's seat in round 1, then at the dealer", () => {
  const game = E.newGame({ startRank: 2, targetRank: 14 });
  const first = E.startOnlineRound(game, E.shuffledDeck(), 3);
  assert.equal(first.dealer, null);
  assert.equal(first.trumpRank, 2);
  assert.equal(E.biddingTurn(first), 3);
  assert.deepEqual(first.hands.map((h) => h.length), [25, 25, 25, 25]);
  game.nextDealer = 1;
  game.levels = [5, 9];
  const later = E.startOnlineRound(game, E.shuffledDeck(), 3);
  assert.equal(later.dealer, 1);
  assert.equal(later.trumpRank, 9, "the dealer team's level");
  assert.equal(E.biddingTurn(later), 1);
});

test("cloneRound makes an independent copy", () => {
  const round = E.newRound(2, 0, E.doubleDeck());
  E.dealAll(round);
  const copy = E.cloneRound(round);
  copy.hands[0].pop();
  copy.trump.suit = 1;
  assert.equal(round.hands[0].length, 25);
  assert.equal(round.trump.suit, null);
});

// MARK: Viewer-relative wording (online: each player is "You")

test("seatName and declarationDescription from any viewer", () => {
  assert.deepEqual([0, 1, 2, 3].map((s) => E.seatName(s)), ["You", "East", "Partner", "West"]);
  assert.deepEqual([0, 1, 2, 3].map((s) => E.seatName(s, 1)), ["West", "You", "East", "Partner"]);
  assert.deepEqual([0, 1, 2, 3].map((s) => E.seatName(s, 2)), ["Partner", "West", "You", "East"]);
  assert.deepEqual([0, 1, 2, 3].map((s) => E.seatName(s, 3)), ["East", "Partner", "West", "You"]);
  const d = { player: 1, cards: [E.makeCard(2, E.HEARTS)], suit: E.HEARTS, strength: 1 };
  assert.equal(E.declarationDescription(d), "East declares ♥ (one 2♥)");
  assert.equal(E.declarationDescription(d, 1), "You declare ♥ (one 2♥)");
  assert.equal(E.declarationDescription(d, 3), "Partner declares ♥ (one 2♥)");
  assert.equal(E.declarationDescription({ player: 0, cards: [53, 107], suit: null, strength: 4 }),
    "You declare no trump (pair of big jokers)");
});

/** The same round seen by seat `viewer` equals the rotated round seen by seat 0. */
test("explainRound from a viewer equals the seat-0 text of the rotated table", () => {
  const rng = seededRandom(3);
  const rotateSeat = (seat: number, viewer: number): number => (((seat - viewer) % 4) + 4) % 4;
  const rotateTeam = (team: number, viewer: number): number => (team + viewer) % 2;
  for (let n = 0; n < 400; n++) {
    const dealer = rng.below(4);
    const points = 5 * rng.below(60);
    const multiplier = rng.pick([0, 2, 4, 8]);
    const kittyPoints = 5 * rng.below(8);
    const result: RoundResult = {
      dealer,
      declarerTeam: dealer % 2,
      trump: { rank: 2, suit: null },
      trickPoints: points,
      kittyPoints,
      kittyMultiplier: multiplier,
      defenderPoints: points + kittyPoints * multiplier,
      outcome: E.scoreOutcome(points + kittyPoints * multiplier),
      kitty: [],
      lastTrickWinner: dealer,
    };
    const team = result.outcome.declarersHold ? dealer % 2 : 1 - (dealer % 2);
    const input: E.RoundExplanationInput = {
      result,
      team,
      nominal: result.outcome.levels,
      gained: Math.min(result.outcome.levels, rng.below(4)),
      newLevel: E.ALL_RANKS[rng.below(13)],
      gameWinner: rng.chance(10) && result.outcome.declarersHold ? dealer % 2 : null,
      target: 14 as Rank,
      nextDealer: rng.below(4),
      nextLevel: E.ALL_RANKS[rng.below(13)],
    };
    for (const viewer of [0, 1, 2, 3]) {
      const rotated: E.RoundExplanationInput = {
        ...input,
        result: { ...result, dealer: rotateSeat(dealer, viewer), declarerTeam: rotateSeat(dealer, viewer) % 2 },
        team: rotateTeam(team, viewer),
        gameWinner: input.gameWinner === null ? null : rotateTeam(input.gameWinner, viewer),
        nextDealer: rotateSeat(input.nextDealer, viewer),
      };
      assert.equal(E.explainRound(input, viewer), E.explainRound(rotated, 0));
    }
  }
});

test("no learner-facing text uses an em dash", () => {
  const texts: string[] = [];
  for (const v of ["empty", "cardsNotInHand", "mixedSuits"] as const) texts.push(E.leadViolationExplanation(v));
  for (const group of ["trump", 0, 1, 2, 3] as const) {
    texts.push(E.followViolationExplanation({ case: "mustFollowSuit", group }));
  }
  for (let n = 1; n < 6; n++) {
    texts.push(E.followViolationExplanation({ case: "wrongCount", expected: n }));
    texts.push(E.followViolationExplanation({ case: "mustPlayTractor", length: n + 1 }));
    texts.push(E.followViolationExplanation({ case: "mustPlayPairs", required: n }));
  }
  for (let p = 0; p <= 300; p += 5) texts.push(E.scoreOutcome(p).summary);
  for (const rank of E.ALL_RANKS) {
    texts.push(E.trumpSummary({ rank, suit: null }), E.trumpDescription({ rank, suit: 1 }));
  }
  texts.push(E.roundErrorExplanation({ case: "invalidDeclaration" }));
  for (const text of texts) assert.ok(!text.includes("\u2014") && !text.includes("\u2013"), text);
});

test("JSON state never loses information: a mid-round round trips exactly", () => {
  const rng = seededRandom(8);
  const round = E.newRound(9, 1, rng.shuffle(E.doubleDeck()));
  assert.equal(E.startBidding(round, 1), null);
  assert.deepEqual(JSON.parse(JSON.stringify(round)), round);
  const cards: Card[] = round.hands[1];
  assert.equal(cards.length, 25);
});
