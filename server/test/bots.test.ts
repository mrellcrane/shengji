// The placeholder bots: every decision is legal (the engine accepts it), deterministic, and
// follows the documented rules for bidding and burying.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, Rank, Suit } from "../src/engine/index.ts";
import { chooseBid, chooseBotAction, chooseBury, chooseFollow, chooseLead, followCandidates } from "../src/game/bots.ts";
import type { BotLevel } from "../src/game/bots.ts";
import { buildDeck, seededRandom } from "./support.ts";

/** The seat that must act (bid, bury or play), or null. */
function toAct(round: E.Round): number | null {
  return E.biddingTurn(round) ?? (round.phase === "burying" ? round.dealer : E.turn(round));
}

function isOver(round: E.Round): boolean {
  return round.phase === "finished";
}

test("bots play hundreds of whole rounds without a single refused move", () => {
  let rounds = 0;
  let declared = 0;
  let wins = 0;
  for (let seed = 0; seed < 150; seed++) {
    const rng = seededRandom(seed);
    const rank = rng.pick(E.ALL_RANKS as Rank[]);
    const round = E.newRound(rank, rng.chance(30) ? null : rng.below(4), rng.shuffle(E.doubleDeck()));
    assert.equal(E.startBidding(round, round.dealer ?? rng.below(4)), null);
    const levels: BotLevel[] = [0, 1, 2, 3].map(() => (rng.chance(50) ? "standard" : "beginner"));
    for (let step = 0; !isOver(round); step++) {
      assert.ok(step < 400, "a round never ended");
      const seat = toAct(round);
      assert.ok(seat !== null);
      const action = chooseBotAction(round, seat, levels[seat]);
      assert.ok(action !== null, `no action for seat ${seat} in ${round.phase}`);
      // Same state, same choice.
      assert.deepEqual(chooseBotAction(E.cloneRound(round), seat, levels[seat]), action);
      switch (action.type) {
        case "bid":
          declared++;
          assert.equal(E.bid(round, seat, action.declaration), null);
          break;
        case "pass":
          assert.equal(E.bid(round, seat, "pass"), null);
          break;
        case "bury":
          assert.equal(E.bury(round, action.cards, seat), null);
          break;
        case "play": {
          const before = round.currentTrick.length;
          const result = E.play(round, action.cards, seat);
          assert.ok(result.ok, result.ok ? "" : E.roundErrorExplanation(result.error));
          if (before > 0) assert.equal(result.outcome.type, "played");
          break;
        }
      }
      // Nobody but the seat to act gets an action.
      for (let other = 0; other < 4; other++) {
        if (other !== toAct(round) && !isOver(round)) assert.equal(chooseBotAction(round, other, "standard"), null);
      }
    }
    rounds++;
    if (round.result !== null && round.result.outcome.declarersHold) wins++;
  }
  assert.equal(rounds, 150);
  assert.ok(declared > 10, `bots declared only ${declared} times`);
  assert.ok(wins > 0 && wins < 150);
});

test("bidding: a pair of trump-rank cards in the longest suit, else pass", () => {
  const c = (rank: Rank, suit: Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
  // Seat 0: hearts are longest (and 5♥ 5♥ is a pair); seat 1: a pair of 5♠ but clubs are longest.
  const hearts = [3, 4, 6, 7, 8, 9, 11].map((r) => c(r as Rank, 1));
  const clubs = [3, 4, 6, 7, 8, 9, 11].map((r) => c(r as Rank, 2));
  const deck = buildDeck([[c(5, 1), c(5, 1, 1), ...hearts], [c(5, 0), c(5, 0, 1), ...clubs], [], []], [], 0, 4);
  const round = E.newRound(5, null, deck);
  assert.equal(E.startBidding(round, 0), null);
  const bid = chooseBotAction(round, 0, "standard");
  assert.equal(bid?.type, "bid");
  assert.deepEqual(bid?.type === "bid" ? [bid.declaration.suit, bid.declaration.strength] : null, [1, 2]);
  assert.deepEqual(chooseBotAction(round, 0, "beginner"), { type: "pass" }, "beginners never declare");
  E.bid(round, 0, "pass");
  assert.deepEqual(chooseBotAction(round, 1, "standard"), { type: "pass" }, "the pair is not in the longest suit");
  assert.equal(chooseBid([], [c(5, 1), c(5, 1, 1)]), null);
});

test("burying keeps trumps and points when it can; leads and follows are legal and sensible", () => {
  const trump = { rank: 2 as Rank, suit: 1 as Suit };
  const c = (rank: Rank, suit: Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
  const hand = [c(14, 1), c(3, 1), c(2, 0), E.bigJoker(), c(10, 0), c(5, 2), c(13, 3), ...[3, 4, 6, 7, 8, 9, 11, 12].map((r) => c(r as Rank, 0)), c(3, 2), c(4, 2)];
  const buried = chooseBury(hand, trump);
  assert.equal(buried.length, 8);
  assert.ok(buried.every((card) => !E.isTrump(trump, card)), "no trumps buried while plain cards remain");
  assert.ok(buried.every((card) => E.cardPoints(card) === 0), "no points buried while other cards remain");

  // Leading: an ace of a plain suit if held, else a low non-point card.
  assert.deepEqual(chooseLead([c(14, 0), c(3, 0), c(14, 2)], trump).length, 1);
  assert.equal(E.strength(trump, chooseLead([c(14, 0), c(3, 0)], trump)[0]), E.TOP_PLAIN_STRENGTH);
  assert.deepEqual(chooseLead([c(14, 0), c(14, 0, 1), c(3, 0)], trump).sort(), [c(14, 0), c(14, 0, 1)].sort());
  assert.deepEqual(chooseLead([c(10, 0), c(5, 0), c(4, 0), c(9, 2)], trump), [c(4, 0)]);

  // Following: partner winning -> cheapest; opponent winning with points -> cheapest winner.
  const lead = [{ player: 1, cards: [c(10, 0)] }];
  const mine = [c(13, 0), c(14, 0), c(3, 0)];
  assert.deepEqual(chooseFollow({ hand: mine, trump, currentTrick: lead, seat: 2 }), [c(13, 0)], "wins the 10 cheaply with the king");
  assert.deepEqual(chooseFollow({ hand: mine, trump, currentTrick: [{ player: 0, cards: [c(3, 0, 1)] }], seat: 2 }), [c(3, 0)]);
  const partnerWins = [{ player: 0, cards: [c(14, 0, 1)] }, { player: 1, cards: [c(4, 0)] }];
  assert.deepEqual(chooseFollow({ hand: [c(10, 0, 1), c(6, 0)], trump, currentTrick: [...partnerWins, { player: 3, cards: [c(7, 0)] }], seat: 2 }), [c(10, 0, 1)], "last to play: give partner the points");
  // Void in the led suit: ruff when points are at stake.
  assert.deepEqual(chooseFollow({ hand: [c(3, 1), c(9, 2)], trump, currentTrick: lead, seat: 2 }), [c(3, 1)]);
  // Every candidate offered is legal.
  const rng = seededRandom(5);
  for (let i = 0; i < 300; i++) {
    const deck = rng.shuffle(E.doubleDeck());
    const t = { rank: rng.pick(E.ALL_RANKS as Rank[]), suit: rng.chance(20) ? null : (rng.below(4) as Suit) };
    const h = deck.slice(0, 1 + rng.below(25));
    const ledGroup = E.groupOf(t, deck[30]);
    const pool = deck.slice(30).filter((card) => E.groupOf(t, card) === ledGroup);
    const leadCards = pool.slice(0, Math.min(pool.length, 1 + rng.below(Math.min(4, h.length))));
    if (leadCards.length > h.length) continue;
    for (const cards of followCandidates(h, leadCards, t)) assert.equal(E.validateFollow(cards, h, leadCards, t), null);
    assert.equal(E.validateFollow(chooseFollow({ hand: h, trump: t, currentTrick: [{ player: 3, cards: leadCards }], seat: 0 }), h, leadCards, t), null);
  }
});
