// Online turn-based bidding (round.ts startBidding / availableBids / bid / biddingTurn). There is
// no Swift reference for it, so every rule is tested here directly.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, Declaration, Rank, Round, Suit } from "../src/engine/index.ts";
import { buildDeck, seededRandom } from "./support.ts";

const S: Suit = 0;
const H: Suit = 1;
const C: Suit = 2;
const D: Suit = 3;
const c = (rank: Rank, suit: Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
const SJ0 = E.smallJoker(0);
const SJ1 = E.smallJoker(1);
const BJ0 = E.bigJoker(0);
const BJ1 = E.bigJoker(1);

/**
 * Rank 5. Seat 0: BJ BJ. Seat 1: 5♥ 5♥. Seat 2: 5♠ 5♣. Seat 3: SJ SJ 5♦. Kitty: the other 5s.
 * (The same layout as the Swift RoundTests declaration round.)
 */
function declarationRound(dealer: number | null = null): Round {
  const deck = buildDeck(
    [[BJ0, BJ1], [c(5, H), c(5, H, 1)], [c(5, S), c(5, C)], [SJ0, SJ1, c(5, D)]],
    [c(5, S, 1), c(5, C, 1), c(5, D, 1)],
    dealer ?? 0,
    11,
  );
  return E.newRound(5, dealer, deck);
}

function labels(declarations: readonly Declaration[]): string[] {
  return declarations.map((d) => `${d.suit === null ? "NT" : E.suitSymbol(d.suit)}${d.strength}`);
}

function option(round: Round, seat: number, label: string): Declaration {
  const found = E.availableBids(round, seat).find((d) => labels([d])[0] === label);
  assert.ok(found, `seat ${seat} cannot bid ${label}; options: ${labels(E.availableBids(round, seat)).join(", ")}`);
  return found;
}

function ok(error: E.RoundError | null): void {
  assert.equal(error, null, error === null ? "" : E.roundErrorExplanation(error));
}

/** Asserts that `action` returns `expected` and leaves the round exactly as it was. */
function rejected(round: Round, expected: E.RoundError, action: () => E.RoundError | null): void {
  const before = JSON.stringify(round);
  assert.deepEqual(action(), expected);
  assert.equal(JSON.stringify(round), before, "a rejected bid must not change the round");
}

test("startBidding deals every card at once and opens bidding at the first bidder", () => {
  const round = declarationRound();
  ok(E.startBidding(round, 2));
  assert.deepEqual(round.hands.map((h) => h.length), [25, 25, 25, 25]);
  assert.equal(round.undealt.length, 0);
  assert.equal(round.phase, "dealing");
  assert.deepEqual(round.bidding, { firstBidder: 2, turn: 2, passes: 0, bids: [] });
  assert.equal(E.biddingTurn(round), 2);
  assert.equal(E.dealNext(round), null);
  // Same cards as dealing one by one would give.
  const offline = declarationRound();
  E.dealAll(offline);
  assert.deepEqual(round.hands, offline.hands);
});

test("startBidding is refused unless the round is still dealing with no declaration", () => {
  const twice = declarationRound();
  ok(E.startBidding(twice, 0));
  rejected(twice, { case: "wrongPhase" }, () => E.startBidding(twice, 1));

  const declared = declarationRound();
  E.dealAll(declared);
  ok(E.declare(declared, E.availableDeclarations(declared, 1)[0]));
  rejected(declared, { case: "wrongPhase" }, () => E.startBidding(declared, 1));

  const burying = declarationRound(0);
  E.dealAll(burying);
  E.finishDealing(burying);
  assert.equal(burying.phase, "burying");
  rejected(burying, { case: "wrongPhase" }, () => E.startBidding(burying, 0));

  for (const bad of [-1, 4, 1.5, Number.NaN]) {
    assert.throws(() => E.startBidding(declarationRound(), bad), RangeError);
  }
});

test("turns go round from the first bidder; only the seat to act has bids", () => {
  const round = declarationRound();
  ok(E.startBidding(round, 3));
  const order: number[] = [];
  for (let i = 0; i < 3; i++) {
    const seat = E.biddingTurn(round) as number;
    order.push(seat);
    for (const other of [0, 1, 2, 3]) {
      if (other === seat) assert.deepEqual(E.availableBids(round, other), E.availableDeclarations(round, other));
      else assert.deepEqual(E.availableBids(round, other), []);
    }
    ok(E.bid(round, seat, "pass"));
  }
  assert.deepEqual(order, [3, 0, 1]);
  assert.equal(E.biddingTurn(round), 2);
});

test("bids out of turn, invalid declarations and impostor declarations are rejected without changes", () => {
  const round = declarationRound();
  ok(E.startBidding(round, 1));
  rejected(round, { case: "notYourTurn" }, () => E.bid(round, 0, "pass"));
  rejected(round, { case: "notYourTurn" }, () => E.bid(round, 3, E.availableDeclarations(round, 3)[0]));
  // Not their cards / wrong cards / wrong strength / someone else's declaration.
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 1, { player: 1, cards: [c(5, S)], suit: S, strength: 1 }));
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 1, { player: 1, cards: [c(5, H)], suit: H, strength: 2 }));
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 1, { player: 1, cards: [c(5, H), c(5, H, 1)], suit: S, strength: 2 }));
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 1, { player: 1, cards: [c(5, H), c(5, H, 1)], suit: null, strength: 3 }));
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 1, { player: 0, cards: [BJ0, BJ1], suit: null, strength: 4 }));
  // The offline entry points are closed while bidding.
  rejected(round, { case: "wrongPhase" }, () => E.declare(round, option(round, 1, "♥1")));
  const before = JSON.stringify(round);
  E.finishDealing(round);
  assert.equal(JSON.stringify(round), before, "finishDealing must not close online bidding");
  assert.equal(E.biddingTurn(round), 1);
});

test("declarations must be stronger, passes reset after each one, three passes end it (round 1: declarer deals)", () => {
  const round = declarationRound();
  ok(E.startBidding(round, 2));
  assert.deepEqual(labels(E.availableBids(round, 2)), ["♠1", "♣1"]);
  ok(E.bid(round, 2, option(round, 2, "♠1")));
  assert.equal(round.trump.suit, S);
  assert.equal(round.bidding?.passes, 0);

  // Seat 3: an equal-strength single can't override; only the joker pair is offered.
  assert.deepEqual(labels(E.availableBids(round, 3)), ["NT3"]);
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 3, { player: 3, cards: [c(5, D)], suit: D, strength: 1 }));
  ok(E.bid(round, 3, "pass"));
  ok(E.bid(round, 0, "pass"));
  assert.equal(round.bidding?.passes, 2);

  // Seat 1 overrides with a pair: the pass count starts again.
  ok(E.bid(round, 1, option(round, 1, "♥2")));
  assert.equal(round.bidding?.passes, 0);
  assert.equal(round.trump.suit, H);
  assert.deepEqual(E.availableBids(round, 2), [], "seat 2's singles can't beat a pair");
  ok(E.bid(round, 2, "pass"));
  ok(E.bid(round, 3, option(round, 3, "NT3")));
  assert.equal(round.trump.suit, null);
  ok(E.bid(round, 0, "pass"));
  ok(E.bid(round, 1, "pass"));
  assert.equal(E.biddingTurn(round), 2, "two passes are not enough");
  ok(E.bid(round, 2, "pass"));

  // Three passes since seat 3's declaration: bidding is over.
  assert.equal(E.biddingTurn(round), null);
  assert.equal(round.bidding?.turn, null);
  assert.equal(round.phase, "burying");
  assert.equal(round.dealer, 3, "round 1: the winning declarer deals");
  assert.equal(round.leader, 3);
  assert.equal(round.trump.suit, null);
  assert.equal(round.trumpFromKitty, null);
  assert.equal(round.hands[3].length, 33);
  assert.ok(round.kitty.every((card) => round.hands[3].includes(card)));
  assert.deepEqual(round.declarationHistory.map((d) => [d.player, d.strength]), [[2, 1], [1, 2], [3, 3]]);
  assert.deepEqual(
    round.bidding?.bids.map((b) => (b.declaration === null ? `${b.seat}:pass` : `${b.seat}:${labels([b.declaration])[0]}`)),
    ["2:♠1", "3:pass", "0:pass", "1:♥2", "2:pass", "3:NT3", "0:pass", "1:pass", "2:pass"],
  );
  // Nothing more can be bid; burying is next.
  assert.deepEqual([0, 1, 2, 3].map((seat) => E.availableBids(round, seat)), [[], [], [], []]);
  rejected(round, { case: "wrongPhase" }, () => E.bid(round, 3, "pass"));
  ok(E.bury(round, round.hands[3].slice(0, 8), 3));
  assert.equal(round.phase, "playing");
  assert.equal(E.turn(round), 3);
});

test("three passes before any declaration do not end bidding; a later declaration still needs three passes", () => {
  const round = declarationRound();
  ok(E.startBidding(round, 1));
  ok(E.bid(round, 1, "pass"));
  ok(E.bid(round, 2, "pass"));
  ok(E.bid(round, 3, "pass"));
  assert.equal(E.biddingTurn(round), 0);
  assert.equal(round.bidding?.passes, 3);
  ok(E.bid(round, 0, option(round, 0, "NT4")));
  assert.equal(round.bidding?.passes, 0);
  ok(E.bid(round, 1, "pass"));
  ok(E.bid(round, 2, "pass"));
  assert.equal(round.phase, "dealing");
  ok(E.bid(round, 3, "pass"));
  assert.equal(round.phase, "burying");
  assert.equal(round.dealer, 0);
  assert.equal(round.declaration?.strength, 4);
});

test("everyone passing with no declaration flips the kitty; in round 1 the first bidder deals", () => {
  // Rank 5; kitty order K♦ 9♠ 5♣ ...: the first trump-rank card (5♣) fixes clubs.
  const deck = buildDeck([[], [], [], []], [c(13, D), c(9, S), c(5, C), c(7, H), c(3, S), c(2, D), c(8, C), c(6, H)], 0, 4);
  const round = E.newRound(5, null, deck);
  ok(E.startBidding(round, 1));
  for (const seat of [1, 2, 3]) ok(E.bid(round, seat, "pass"));
  assert.equal(round.phase, "dealing");
  ok(E.bid(round, 0, "pass"));
  assert.equal(round.phase, "burying");
  assert.equal(round.declaration, null);
  assert.equal(round.trump.suit, C);
  assert.equal(round.trumpFromKitty, c(5, C));
  assert.equal(round.dealer, 1, "nobody declared in round 1: the first bidder deals");
  assert.equal(round.leader, 1);
  assert.equal(round.hands[1].length, 33);

  // A joker turned up first means no trump suit.
  const jokerDeck = buildDeck([[], [], [], []], [c(9, S), SJ0, c(5, C)], 0, 5);
  const noTrump = E.newRound(5, 2, jokerDeck);
  ok(E.startBidding(noTrump, 2));
  for (const seat of [2, 3, 0, 1]) ok(E.bid(noTrump, seat, "pass"));
  assert.equal(noTrump.trump.suit, null);
  assert.equal(noTrump.trumpFromKitty, SJ0);
  assert.equal(noTrump.dealer, 2, "a known dealer keeps the deal");

  // No rank card or joker: the suit of the highest card (the first one if tied).
  const plainKitty = [c(9, S), c(14, H), c(3, C), c(14, D), c(7, S), c(2, C), c(10, D), c(4, H)];
  const plain = E.newRound(5, 3, buildDeck([[], [], [], []], plainKitty, 3, 6));
  ok(E.startBidding(plain, 3));
  for (const seat of [3, 0, 1, 2]) ok(E.bid(plain, seat, "pass"));
  assert.equal(plain.trump.suit, H);
  assert.equal(plain.trumpFromKitty, c(14, H));
  assert.equal(plain.dealer, 3);
});

test("a known dealer keeps the deal whoever wins the bidding", () => {
  const round = declarationRound(2);
  ok(E.startBidding(round, 2));
  ok(E.bid(round, 2, option(round, 2, "♣1")));
  ok(E.bid(round, 3, option(round, 3, "NT3")));
  for (const seat of [0, 1, 2]) ok(E.bid(round, seat, "pass"));
  assert.equal(round.phase, "burying");
  assert.equal(round.dealer, 2);
  assert.equal(round.declaration?.player, 3);
  assert.equal(round.trump.suit, null);
  assert.equal(round.hands[2].length, 33);
});

test("partners may override each other, and an overridden player may come back with something stronger", () => {
  // Rank 2. Seat 0: 2♠. Seat 2 (partner): 2♥ 2♥. Seat 1: SJ SJ. Seat 3: nothing. Seat 0 also BJ BJ.
  const deck = buildDeck([[c(2, S), BJ0, BJ1], [SJ0, SJ1], [c(2, H), c(2, H, 1)], []], [], 0, 7);
  const round = E.newRound(2, null, deck);
  // The fill-in may have dealt seat 3 some rank cards; it only ever passes here.
  ok(E.startBidding(round, 0));
  ok(E.bid(round, 0, option(round, 0, "♠1")));
  ok(E.bid(round, 1, "pass"));
  ok(E.bid(round, 2, option(round, 2, "♥2")));
  assert.equal(round.declaration?.player, 2, "partner overrode");
  ok(E.bid(round, 3, "pass"));
  // Seat 0 was overridden: a stronger joker pair is allowed, a weaker or equal bid is not.
  assert.deepEqual(labels(E.availableBids(round, 0)), ["NT4"]);
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 0, { player: 0, cards: [c(2, S)], suit: S, strength: 1 }));
  ok(E.bid(round, 0, option(round, 0, "NT4")));
  ok(E.bid(round, 1, "pass"));
  assert.deepEqual(E.availableBids(round, 2), [], "nothing beats a pair of big jokers");
  ok(E.bid(round, 2, "pass"));
  ok(E.bid(round, 3, "pass"));
  assert.equal(round.dealer, 0);
  assert.equal(round.trump.suit, null);
});

test("reinforcement: the current declarer never gets a turn while holding the declaration", () => {
  // Seat 1 holds both 5♥. Offline they could declare one and reinforce later; online the holder's
  // turn never comes back while they hold it (three passes end the bidding first).
  const round = declarationRound();
  ok(E.startBidding(round, 1));
  ok(E.bid(round, 1, option(round, 1, "♥1")));
  // The offline rule still applies to the holder's options: only the reinforcement.
  assert.deepEqual(labels(E.availableDeclarations(round, 1)), ["♥2"]);
  // But it is not their turn, so they can't use it.
  assert.deepEqual(E.availableBids(round, 1), []);
  const pair = E.availableDeclarations(round, 1)[0];
  rejected(round, { case: "notYourTurn" }, () => E.bid(round, 1, pair));
  ok(E.bid(round, 2, "pass"));
  rejected(round, { case: "notYourTurn" }, () => E.bid(round, 1, pair));
  ok(E.bid(round, 3, "pass"));
  rejected(round, { case: "notYourTurn" }, () => E.bid(round, 1, pair));
  ok(E.bid(round, 0, "pass"));
  // The turn would have come back to the holder: bidding ended instead.
  assert.equal(E.biddingTurn(round), null);
  assert.equal(round.phase, "burying");
  assert.equal(round.declaration?.strength, 1);
  rejected(round, { case: "wrongPhase" }, () => E.bid(round, 1, pair));

  // A pair declared at once is the stronger bid: a single can be overridden by any pair.
  const other = declarationRound();
  ok(E.startBidding(other, 1));
  ok(E.bid(other, 1, option(other, 1, "♥1")));
  ok(E.bid(other, 2, "pass"));
  ok(E.bid(other, 3, "pass"));
  assert.deepEqual(labels(E.availableBids(other, 0)), ["NT4"]);
});

test("the holder's options after being overridden are those of any other player", () => {
  // Seat 1 declares ♥1, seat 3 overrides with SJ SJ; back at seat 1, ♥2 (strength 2) is too weak.
  const round = declarationRound();
  ok(E.startBidding(round, 1));
  ok(E.bid(round, 1, option(round, 1, "♥1")));
  ok(E.bid(round, 2, "pass"));
  ok(E.bid(round, 3, option(round, 3, "NT3")));
  ok(E.bid(round, 0, "pass"));
  assert.deepEqual(E.availableBids(round, 1), []);
  rejected(round, { case: "invalidDeclaration" }, () =>
    E.bid(round, 1, { player: 1, cards: [c(5, H), c(5, H, 1)], suit: H, strength: 2 }));
});

test("bidding state survives JSON storage at every step", () => {
  let round = declarationRound();
  ok(E.startBidding(round, 0));
  const find = (seat: number, label: string): Declaration =>
    E.availableDeclarations(round, seat).find((d) => labels([d])[0] === label) as Declaration;
  const script: (Declaration | "pass")[] = ["pass", find(1, "♥1"), "pass", find(3, "NT3"), "pass", "pass", "pass"];
  let seat = 0;
  for (const choice of script) {
    round = JSON.parse(JSON.stringify(round)) as Round;
    ok(E.bid(round, seat, choice === "pass" ? "pass" : { ...choice, player: seat }));
    seat = (seat + 1) % 4;
  }
  assert.equal(round.phase, "burying");
  assert.equal(round.dealer, 3);
});

test("random bidding: every rule holds over many deals", () => {
  const rng = seededRandom(20261010);
  let declarationsSeen = 0;
  let allPassed = 0;
  for (let n = 0; n < 600; n++) {
    const rank = E.ALL_RANKS[rng.below(13)];
    const dealer = rng.chance(30) ? null : rng.below(4);
    const round = E.newRound(rank, dealer, rng.shuffle(E.doubleDeck()));
    const firstBidder = dealer ?? rng.below(4);
    ok(E.startBidding(round, firstBidder));
    let expectedTurn = firstBidder;
    let passesSinceDeclaration = 0;
    let turns = 0;
    let lastDeclaration: Declaration | null = null;
    while (E.biddingTurn(round) !== null) {
      turns++;
      assert.ok(turns <= 40, "bidding must end");
      const seat = E.biddingTurn(round) as number;
      assert.equal(seat, expectedTurn, "turns go round in seat order");
      assert.notEqual(seat, round.declaration?.player, "the holder never gets a turn");
      const options = E.availableBids(round, seat);
      for (const o of options) {
        assert.ok(round.declaration === null || o.strength > round.declaration.strength, "bids must be stronger");
        assert.ok(o.cards.every((card) => round.hands[seat].includes(card)));
      }
      if (options.length > 0 && rng.chance(35)) {
        const choice = rng.pick(options);
        ok(E.bid(round, seat, choice));
        lastDeclaration = choice;
        passesSinceDeclaration = 0;
        declarationsSeen++;
        assert.equal(round.trump.suit, choice.suit);
      } else {
        ok(E.bid(round, seat, "pass"));
        passesSinceDeclaration++;
      }
      const shouldEnd: boolean = lastDeclaration === null ? passesSinceDeclaration === 4 : passesSinceDeclaration === 3;
      assert.equal(round.phase === "burying", shouldEnd, "bidding ends exactly on the third pass (fourth without a declaration)");
      expectedTurn = (seat + 1) % 4;
    }
    // After bidding: trump, dealer and kitty as specified.
    const winning = lastDeclaration as Declaration | null;
    if (winning === null) allPassed++;
    assert.equal(round.phase, "burying");
    const expectedDealer = dealer ?? winning?.player ?? firstBidder;
    assert.equal(round.dealer, expectedDealer);
    assert.equal(round.leader, expectedDealer);
    if (winning !== null) {
      assert.deepEqual(round.declaration, winning);
      assert.equal(round.trump.suit, winning.suit);
      assert.equal(round.trumpFromKitty, null);
    } else {
      const flip = E.kittyFlip(round.kitty, rank);
      assert.equal(round.trump.suit, flip.suit);
      assert.equal(round.trumpFromKitty, flip.card);
    }
    assert.deepEqual(
      round.hands.map((h) => h.length),
      [0, 1, 2, 3].map((s) => (s === expectedDealer ? 33 : 25)),
    );
    assert.equal(round.bidding?.bids.length, turns);
  }
  assert.ok(declarationsSeen > 300 && allPassed > 20, `declarations ${declarationsSeen}, all passed ${allPassed}`);
});

test("tables of 5 to 9: every other player must pass after a declaration, everyone without one", () => {
  const rng = seededRandom(68);
  const seen = { declarations: 0, allPassed: 0, sets: 0 };
  for (let n = 0; n < 300; n++) {
    const table = E.tableSize([6, 8, 5, 7, 9][n % 5]);
    const players = table.players;
    const rank = E.ALL_RANKS[rng.below(13)];
    const dealer = rng.chance(30) ? null : rng.below(players);
    const round = E.newRound(rank, dealer, rng.shuffle(E.deckCards(table.decks)), table);
    const firstBidder = dealer ?? rng.below(players);
    ok(E.startBidding(round, firstBidder));
    // Every card but the kitty is dealt: 26 each with 6 or 8 (a kitty of 6 or 8), 31 with 5 (7), 30
    // with 7 (6), 29 with 9 (9).
    const handSize = E.handSizeOf(round);
    assert.equal(handSize, { 5: 31, 6: 26, 7: 30, 8: 26, 9: 29 }[players]);
    assert.deepEqual(round.hands.map((h) => h.length), new Array(players).fill(handSize));
    assert.equal(round.kitty.length, E.kittySizeOf(round));
    let expectedTurn = firstBidder;
    let passes = 0;
    let winning: Declaration | null = null;
    while (E.biddingTurn(round) !== null) {
      const seat = E.biddingTurn(round) as number;
      assert.equal(seat, expectedTurn, "turns go round the whole table");
      assert.notEqual(seat, round.declaration?.player, "the holder never gets a turn");
      const options = E.availableBids(round, seat);
      for (const o of options) assert.ok(winning === null || o.strength > winning.strength, "bids must be stronger");
      if (options.length > 0 && rng.chance(30)) {
        // Often the strongest: three or four of a card where the hand has them.
        const choice = rng.chance(50) ? options[options.length - 1] : rng.pick(options);
        ok(E.bid(round, seat, choice));
        winning = choice;
        passes = 0;
        seen.declarations++;
        if (choice.cards.length >= 3) seen.sets++;
      } else {
        ok(E.bid(round, seat, "pass"));
        passes++;
      }
      const shouldEnd: boolean = winning === null ? passes === players : passes === players - 1;
      assert.equal(round.phase === "burying", shouldEnd, `bidding ends after ${players - 1} passes (${players} without a declaration)`);
      expectedTurn = (seat + 1) % players;
    }
    const declared = winning as Declaration | null;
    if (declared === null) seen.allPassed++;
    const expectedDealer = dealer ?? declared?.player ?? firstBidder;
    assert.equal(round.dealer, expectedDealer);
    assert.deepEqual(round.hands.map((h) => h.length),
      E.allSeats(players).map((s) => (s === expectedDealer ? handSize + E.kittySizeOf(round) : handSize)));
  }
  assert.ok(seen.declarations > 150 && seen.allPassed > 10 && seen.sets > 5, JSON.stringify(seen));
});
