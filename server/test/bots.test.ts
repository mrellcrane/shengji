// The server's bots (src/game/bots.ts over the port of the Swift bots in src/bots): every decision is
// made from the seat's own view, is legal, and is deterministic; the rules-built safe moves are
// legal; and a refused choice falls back to a safe move and is reported. That the port chooses
// exactly what the Swift bots choose is bots.parity.test.ts.

import assert from "node:assert/strict";
import { test } from "node:test";
import { botDiagnostics, friendCalls } from "../src/bots/index.ts";
import * as E from "../src/engine/index.ts";
import type { Card, Rank, Round, SeatPlayer } from "../src/engine/index.ts";
import { chooseBotAction, safeActions } from "../src/game/bots.ts";
import type { BotAction, BotLevel } from "../src/game/bots.ts";
import { applyBotTurn } from "../src/game/online.ts";
import { buildDeck, seededRandom } from "./support.ts";

/** Bots in every seat of a table of `players`. */
function botPlayers(players: number): SeatPlayer[] {
  return E.allSeats(players).map((seat) => ({ name: `Bot ${seat}`, isBot: true, userID: null }));
}

const PLAYERS = botPlayers(4);

/** The seat that must act (bid, bury or play), or null. */
function toAct(round: Round): number | null {
  return E.biddingTurn(round) ?? (round.phase === "burying" ? round.dealer : E.turn(round));
}

/** The bot's action at absolute `seat`, from that seat's view (a bid's declaration made absolute). */
function botAction(game: E.GameState, round: Round, seat: number, level: BotLevel): BotAction | null {
  const action = chooseBotAction(E.toSeatView(game, round, seat, botPlayers(round.hands.length)), level);
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
      return E.bury(round, action.cards, seat, action.calls ?? []);
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

test("tables of 6 and 8: bots play whole rounds from their views, with sets, and the safe moves are legal", () => {
  const fallbacks = botDiagnostics.fallbacks;
  const seen = { setLeads: 0, setDeclarations: 0, safeChecked: 0 };
  for (let seed = 0; seed < 30; seed++) {
    const rng = seededRandom(6800 + seed);
    const table = E.tableSize(seed % 2 === 0 ? 6 : 8);
    const rank = rng.pick(E.ALL_RANKS as Rank[]);
    const round = E.newRound(rank, rng.chance(30) ? null : rng.below(table.players), rng.shuffle(E.deckCards(table.decks)), table);
    const game = E.newGame({ startRank: rank, targetRank: 14, table });
    assert.equal(E.startBidding(round, round.dealer ?? rng.below(table.players)), null);
    const levels: BotLevel[] = E.allSeats(table.players).map(() => (rng.chance(50) ? "standard" : "beginner"));
    for (let step = 0; round.phase !== "finished"; step++) {
      assert.ok(step < 800, "a round never ended");
      const seat = toAct(round) as number;
      for (let other = 0; other < table.players; other++) {
        if (other !== seat) assert.deepEqual(safeActions(round, other), [], `seat ${other} has a safe move out of turn`);
      }
      const safe = safeActions(round, seat);
      assert.equal(safe.length, 1);
      assert.equal(apply(E.cloneRound(round), seat, safe[0]), null, `${round.phase}: the safe move was refused`);
      seen.safeChecked++;
      const action = botAction(game, round, seat, levels[seat]);
      assert.ok(action !== null, `no action for seat ${seat} in ${round.phase}`);
      if (action.type === "bid" && action.declaration.cards.length >= 3) seen.setDeclarations++;
      if (action.type === "play" && round.currentTrick.length === 0 && E.maxCopies(action.cards) >= 3) seen.setLeads++;
      if (action.type === "play") {
        const result = E.play(round, action.cards, seat);
        assert.ok(result.ok, result.ok ? "" : E.roundErrorExplanation(result.error));
        assert.equal(result.outcome.type, "played", "bots only throw when the throw is sure to stand");
      } else {
        const error = apply(round, seat, action);
        assert.equal(error, null, error === null ? "" : E.roundErrorExplanation(error));
      }
    }
    assert.equal(round.result?.kitty.length, E.kittySizeOf(round));
  }
  assert.ok(seen.setLeads > 0 && seen.setDeclarations > 0, JSON.stringify(seen));
  assert.equal(botDiagnostics.fallbacks, fallbacks, "the bots needed their rules-built safety net");
});

test("tables of 5, 7 and 9: bot dealers call friends, friends are found, and whole games run", () => {
  const fallbacks = botDiagnostics.fallbacks;
  for (const players of [5, 7, 9]) {
    const table = E.tableSize(players);
    const rng = seededRandom(5700 + players);
    let game = E.newGame({ startRank: 2, targetRank: 14, table });
    let calls = 0;
    let found = 0;
    let rounds = 0;
    let safeChecked = 0;
    while (game.winner === null && rounds < 4) {
      const round = E.startOnlineRound(game, rng.shuffle(E.deckCards(table.decks)), rng.below(players));
      const levels: BotLevel[] = E.allSeats(players).map(() => (rng.chance(50) ? "standard" : "beginner"));
      for (let step = 0; round.phase !== "finished"; step++) {
        assert.ok(step < 900, "a round never ended");
        const seat = toAct(round) as number;
        const safe = safeActions(round, seat);
        assert.equal(safe.length, 1);
        assert.equal(apply(E.cloneRound(round), seat, safe[0]), null, `${round.phase}: the safe move was refused`);
        safeChecked++;
        const action = botAction(game, round, seat, levels[seat]);
        assert.ok(action !== null, `no action for seat ${seat} in ${round.phase}`);
        if (action.type === "bury") {
          // The dealer calls exactly the friends the table needs, all legal.
          assert.equal(action.calls?.length, E.tableFriendCount(table));
          assert.equal(E.friendCallProblem(action.calls ?? [], table, round.trumpRank), null);
        }
        if (action.type === "play") {
          const result = E.play(round, action.cards, seat);
          assert.ok(result.ok, result.ok ? "" : E.roundErrorExplanation(result.error));
          assert.equal(result.outcome.type, "played", "bots only throw when the throw is sure to stand");
        } else {
          const error = apply(round, seat, action);
          assert.equal(error, null, error === null ? "" : E.roundErrorExplanation(error));
        }
      }
      const result = round.result as E.RoundResult;
      assert.equal(result.friendCalls?.length, E.tableFriendCount(table));
      assert.equal(result.declarers?.[0], result.dealer, "the dealer comes first on the dealer's side");
      const allPoints = round.tricks.reduce((sum, t) => sum + t.points, 0) + E.totalPoints(round.kitty);
      assert.equal(allPoints, E.tableTotalPoints(table));
      calls += result.friendCalls?.length ?? 0;
      found += (result.friendCalls ?? []).filter((call) => call.friend !== null).length;
      const summary = E.recordRound(game, result);
      assert.match(summary.explanation, new RegExp(String(E.takeoverThreshold(table.decks))));
      assert.equal(game.levels.length, players, "one level per seat");
      game = JSON.parse(JSON.stringify(game)) as E.GameState;
      rounds++;
    }
    assert.ok(rounds > 0 && safeChecked > 0);
    assert.ok(found * 2 > calls, `${players} players: bots found only ${found} of ${calls} friends`);
  }
  assert.equal(botDiagnostics.fallbacks, fallbacks, "the bots needed their rules-built safety net");
});

test("a bot dealer calls the top card it holds no copy of, one suit per friend, shortest held suits first", () => {
  // Port of the Swift testBotCallsTopCardsItDoesNotHold: spades trump, nine players.
  const c = (rank: Rank, suit: E.Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
  const hand = [c(14, 1), c(3, 1), c(4, 2), c(9, 3), c(14, 3), c(13, 3)];
  const view: E.SeatView = {
    players: botPlayers(9), teamLevels: new Array(9).fill(2), targetRank: 14, roundNumber: 1, phase: "burying",
    trump: { rank: 2, suit: 0 }, trumpFromKitty: null, dealer: 0, hand, handCounts: [hand.length, ...new Array(8).fill(29)],
    declaration: null, declarationHistory: [], bidding: null, kitty: [], currentTrick: [], leader: 0, turn: 0, tricks: [],
    defenderTrickPoints: 0, result: null, lastRoundSummary: null, gameWinnerTeam: null, friendCalls: null,
  };
  // Clubs (1 card), hearts (2), diamonds (3): A♣, K♥, Q♦.
  const calls = friendCalls(view, []);
  assert.deepEqual(calls, [E.friendCall(E.regularFace(14, 2)), E.friendCall(E.regularFace(13, 1)), E.friendCall(E.regularFace(12, 3))]);
  assert.equal(E.friendCallList(calls), "the first A♣, the first K♥ and the first Q♦");
  assert.equal(E.friendCallProblem(calls, E.tableSize(9), 2), null);
  // At a table of fixed teams there is nobody to call.
  assert.deepEqual(friendCalls({ ...view, players: botPlayers(8), handCounts: new Array(8).fill(26), teamLevels: [2, 2] }, []), []);
});

test("Finding Friends has no partners while bidding: a bot overrides the seat that would be its partner at 6", () => {
  const c = (rank: Rank, suit: E.Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
  // Seat 0 holds a pair of 5♥ and many hearts; seat 2 three 5♠, every joker pair and many spades.
  const hearts = [3, 4, 6, 7, 8, 9, 11, 12, 13].map((r) => c(r as Rank, 1));
  const spades = [3, 4, 6, 7, 8, 9, 11, 12, 13].map((r) => c(r as Rank, 0));
  const strong = [c(5, 0), c(5, 0, 1), c(5, 0, 2), E.smallJoker(0), E.smallJoker(1), E.bigJoker(0), E.bigJoker(1), ...spades];
  for (const players of [5, 6]) {
    const table = E.tableSize(players);
    const deck = buildDeck([[c(5, 1), c(5, 1, 1), ...hearts], [], strong, [], []], [], 0, 4, players);
    const round = E.newRound(5, null, deck, table);
    const game = E.newGame({ startRank: 5, targetRank: 14, table });
    assert.equal(E.startBidding(round, 0), null);
    const pair = E.availableBids(round, 0).find((d) => d.suit === 1 && d.strength === 2);
    assert.ok(pair !== undefined);
    assert.equal(E.bid(round, 0, pair), null);
    assert.equal(E.bid(round, 1, "pass"), null);
    const choice = chooseBotAction(E.toSeatView(game, round, 2, botPlayers(players)), "standard");
    if (players === 6) {
      assert.deepEqual(choice, { type: "pass" }, "a partner is never overridden");
    } else {
      assert.equal(choice?.type, "bid", "at an odd table seat 0 is just another player");
      if (choice?.type === "bid") assert.ok(choice.declaration.strength > 2);
    }
  }
});
