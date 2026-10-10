// The server's bots (src/game/bots.ts over the port of the Swift bots in src/bots): every decision is
// made from the seat's own view, is legal, and is deterministic; the rules-built safe moves are
// legal; and a refused choice falls back to a safe move and is reported. That the port chooses
// exactly what the Swift bots choose is bots.parity.test.ts.

import assert from "node:assert/strict";
import { test } from "node:test";
import { botDiagnostics } from "../src/bots/index.ts";
import * as E from "../src/engine/index.ts";
import type { Card, Rank, Round, SeatPlayer } from "../src/engine/index.ts";
import { chooseBotAction, safeActions } from "../src/game/bots.ts";
import type { BotAction, BotLevel } from "../src/game/bots.ts";
import { applyBotTurn } from "../src/game/online.ts";
import { buildDeck, seededRandom } from "./support.ts";

const PLAYERS: SeatPlayer[] = [0, 1, 2, 3].map((seat) => ({ name: `Bot ${seat}`, isBot: true, userID: null }));

/** The seat that must act (bid, bury or play), or null. */
function toAct(round: Round): number | null {
  return E.biddingTurn(round) ?? (round.phase === "burying" ? round.dealer : E.turn(round));
}

/** The bot's action at absolute `seat`, from that seat's view (a bid's declaration made absolute). */
function botAction(game: E.GameState, round: Round, seat: number, level: BotLevel): BotAction | null {
  const action = chooseBotAction(E.toSeatView(game, round, seat, PLAYERS), level);
  if (action?.type !== "bid") return action;
  return { type: "bid", declaration: { ...action.declaration, player: seat } };
}

/** Applies an absolute action; null if the engine accepts it, else the error. */
function apply(round: Round, seat: number, action: BotAction): E.RoundError | null {
  switch (action.type) {
    case "bid":
      return E.bid(round, seat, action.declaration);
    case "pass":
      return E.bid(round, seat, "pass");
    case "bury":
      return E.bury(round, action.cards, seat);
    case "play": {
      const result = E.play(round, action.cards, seat);
      return result.ok ? null : result.error;
    }
  }
}

test("bots play hundreds of whole rounds from their views without a single refused move", () => {
  const fallbacks = botDiagnostics.fallbacks;
  let declared = 0;
  let held = 0;
  let noTrump = 0;
  for (let seed = 0; seed < 150; seed++) {
    const rng = seededRandom(seed);
    const rank = rng.pick(E.ALL_RANKS as Rank[]);
    const round = E.newRound(rank, rng.chance(30) ? null : rng.below(4), rng.shuffle(E.doubleDeck()));
    const game = E.newGame({ startRank: rank, targetRank: 14 });
    assert.equal(E.startBidding(round, round.dealer ?? rng.below(4)), null);
    const levels: BotLevel[] = [0, 1, 2, 3].map(() => (rng.chance(50) ? "standard" : "beginner"));
    for (let step = 0; round.phase !== "finished"; step++) {
      assert.ok(step < 400, "a round never ended");
      const seat = toAct(round);
      assert.ok(seat !== null);
      const action = botAction(game, round, seat, levels[seat]);
      assert.ok(action !== null, `no action for seat ${seat} in ${round.phase}`);
      // Same state, same choice.
      assert.deepEqual(botAction(game, E.cloneRound(round), seat, levels[seat]), action);
      // Nobody else has anything to do.
      for (let other = 0; other < 4; other++) {
        if (other !== seat) assert.equal(botAction(game, round, other, "standard"), null, `seat ${other} acts out of turn`);
      }
      if (action.type === "bid") declared++;
      if (round.phase === "burying" && round.trump.suit === null) noTrump++;
      if (action.type === "play") {
        const result = E.play(round, action.cards, seat);
        assert.ok(result.ok, result.ok ? "" : E.roundErrorExplanation(result.error));
        // Bots only throw when the throw is sure to stand.
        assert.equal(result.outcome.type, "played");
      } else {
        const error = apply(round, seat, action);
        assert.equal(error, null, error === null ? "" : E.roundErrorExplanation(error));
      }
    }
    if (round.result !== null && round.result.outcome.declarersHold) held++;
  }
  assert.ok(declared > 50, `bots declared only ${declared} times`);
  assert.ok(held > 0 && held < 150);
  assert.ok(noTrump > 0, "no round without a trump suit");
  assert.equal(botDiagnostics.fallbacks, fallbacks, "the bots needed their rules-built safety net");
});

test("bidding: a declaration is one of view.bidding.available; partners are never overridden", () => {
  const c = (rank: Rank, suit: E.Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
  // Seat 0 holds a pair of 5♥ and many hearts; seat 2 (its partner) both joker pairs and many spades.
  const hearts = [3, 4, 6, 7, 8, 9, 11, 12, 13].map((r) => c(r as Rank, 1));
  const spades = [3, 4, 6, 7, 8, 9, 11, 12, 13].map((r) => c(r as Rank, 0));
  const jokers = [E.smallJoker(0), E.smallJoker(1), E.bigJoker(0), E.bigJoker(1)];
  const deck = buildDeck([[c(5, 1), c(5, 1, 1), ...hearts], [], [...jokers, ...spades], []], [], 0, 4);
  const round = E.newRound(5, null, deck);
  const game = E.newGame({ startRank: 5, targetRank: 14 });
  assert.equal(E.startBidding(round, 0), null);
  const view = E.toSeatView(game, round, 0, PLAYERS);
  const bid = chooseBotAction(view, "standard");
  assert.equal(bid?.type, "bid");
  if (bid?.type !== "bid") return;
  assert.ok(view.bidding?.available.some((d) => d.suit === bid.declaration.suit && d.strength === bid.declaration.strength));
  assert.equal(bid.declaration.player, 0);
  assert.deepEqual([bid.declaration.suit, bid.declaration.strength], [1, 2]);
  assert.equal(E.bid(round, 0, { ...bid.declaration, player: 0 }), null);
  assert.equal(E.bid(round, 1, "pass"), null);
  // The partner could override with its own pair, but never does.
  assert.ok(E.availableBids(round, 2).length > 0);
  assert.deepEqual(chooseBotAction(E.toSeatView(game, round, 2, PLAYERS), "standard"), { type: "pass" });
  assert.deepEqual(chooseBotAction(E.toSeatView(game, round, 2, PLAYERS), "beginner"), { type: "pass" });
});

test("safe moves are legal in every phase", () => {
  for (let seed = 0; seed < 40; seed++) {
    const rng = seededRandom(1000 + seed);
    const rank = rng.pick(E.ALL_RANKS as Rank[]);
    const round = E.newRound(rank, rng.below(4), rng.shuffle(E.doubleDeck()));
    const game = E.newGame({ startRank: rank, targetRank: 14 });
    assert.equal(E.startBidding(round, round.dealer ?? 0), null);
    while (round.phase !== "finished") {
      const seat = toAct(round) as number;
      const safe = safeActions(round, seat);
      assert.equal(safe.length, 1, `no safe move in ${round.phase}`);
      for (let other = 0; other < 4; other++) if (other !== seat) assert.deepEqual(safeActions(round, other), []);
      const copy = E.cloneRound(round);
      const error = apply(copy, seat, safe[0]);
      assert.equal(error, null, error === null ? "" : `${round.phase}: ${E.roundErrorExplanation(error)}`);
      // Move on with a bot's move (or the safe one now and then), so many positions are visited.
      const action = rng.chance(30) ? safe[0] : (botAction(game, round, seat, "standard") as BotAction);
      assert.equal(apply(round, seat, action), null);
    }
  }
});

test("a refused bot choice falls back to a safe move, and is reported", () => {
  const round = E.newRound(2, 0, E.doubleDeck());
  assert.equal(E.startBidding(round, 0), null);
  const notes: string[] = [];
  // A bid of cards seat 0 does not hold.
  const foreign = round.hands[1].slice(0, 2);
  const refused = applyBotTurn(round, 0, { type: "bid", declaration: { player: 0, cards: foreign, suit: 0, strength: 2 } }, "game g_test", (m) => notes.push(m));
  assert.deepEqual(refused?.action, { type: "pass" });
  assert.equal(E.biddingTurn(round), 1);
  assert.equal(notes.length, 2, notes.join("\n"));
  assert.match(notes[0], /^game g_test: the bot at seat 0 chose a bid of cards .*, which was refused: You can't declare that/);
  assert.match(notes[1], /safe move a pass for seat 0/);

  // An accepted choice is applied and nothing is reported.
  notes.length = 0;
  const accepted = applyBotTurn(round, 1, { type: "pass" }, "game g_test", (m) => notes.push(m));
  assert.deepEqual(accepted?.action, { type: "pass" });
  assert.equal(notes.length, 0, notes.join("\n"));

  // No choice at all (a bot with nothing to say) also falls back.
  const none = applyBotTurn(round, 2, null, "game g_test", (m) => notes.push(m));
  assert.deepEqual(none?.action, { type: "pass" });
  assert.match(notes[0], /had no move in phase dealing/);

  // Out of turn: nothing is safe, nothing changes.
  notes.length = 0;
  const before = JSON.stringify(round);
  assert.equal(applyBotTurn(round, 0, { type: "pass" }, "game g_test", (m) => notes.push(m)), null);
  assert.equal(JSON.stringify(round), before);
  assert.match(notes[notes.length - 1], /no safe move was accepted for seat 0; the game waits/);
});
