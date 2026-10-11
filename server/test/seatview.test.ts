// The parts of the wire view and game summaries with no Swift producer: the online bidding state
// (views.json covers everything else), the viewer-relative GameSummary, and the event lines.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, Rank, Suit } from "../src/engine/index.ts";
import { eventText, summarize } from "../src/game/summary.ts";
import type { GameEvent, GameSnapshot } from "../src/game/summary.ts";
import { buildDeck } from "./support.ts";

const c = (rank: Rank, suit: Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
const players: E.SeatPlayer[] = [
  { name: "Mei", isBot: false, userID: "u_mei" },
  { name: "Tiger Bot", isBot: true, userID: null },
  { name: "Lin", isBot: false, userID: "u_lin" },
  { name: "Sam", isBot: false, userID: "u_sam" },
];

test("while bidding, every seat sees the rotated history and turn; only the bidder gets options", () => {
  // Rank 2. Seat 1 holds 2♥ 2♥, seat 3 holds both big jokers.
  const deck = buildDeck([[], [c(2, 1), c(2, 1, 1)], [], [E.bigJoker(0), E.bigJoker(1)]], [], 0, 8);
  const game = E.newGame({ startRank: 2, targetRank: 14 });
  const round = E.startOnlineRound(game, deck, 0);
  assert.equal(E.bid(round, 0, "pass"), null);
  const hearts = E.availableBids(round, 1).find((d) => d.strength === 2 && d.suit === 1)!;
  assert.equal(E.bid(round, 1, hearts), null);
  assert.equal(E.bid(round, 2, "pass"), null);
  // Seat 3 to bid.
  for (let viewer = 0; viewer < 4; viewer++) {
    const view = E.toSeatView(game, round, viewer, players);
    const rel = (s: number) => (s - viewer + 4) % 4;
    assert.equal(view.phase, "bidding");
    assert.equal(view.turn, null, "turn is for playing and burying; bidding has its own");
    assert.equal(view.dealer, null, "round 1: the dealer is not known yet");
    assert.equal(view.kitty, null);
    assert.deepEqual(view.trump, { rank: 2, suit: 1 }, "the current declaration sets the trump suit for now");
    assert.deepEqual(view.bidding?.history, [
      { player: rel(0), declaration: null },
      { player: rel(1), declaration: { ...hearts, player: rel(1) } },
      { player: rel(2), declaration: null },
    ]);
    assert.equal(view.bidding?.turn, rel(3));
    assert.deepEqual(view.declaration, { ...hearts, player: rel(1) });
    assert.deepEqual(view.players.map((p) => p.name), [0, 1, 2, 3].map((i) => players[(i + viewer) % 4].name));
    if (viewer === 3) {
      assert.deepEqual(view.bidding?.available.map((d) => [d.player, d.suit, d.strength]), [[0, null, 4]]);
    } else {
      assert.deepEqual(view.bidding?.available, []);
    }
    assert.equal(view.handCounts.reduce((a, b) => a + b, 0), 100);
  }
  // After bidding closes (big jokers, then three passes), the bidding object is gone.
  const jokers = E.availableBids(round, 3)[0];
  assert.equal(E.bid(round, 3, jokers), null);
  for (const seat of [0, 1, 2]) assert.equal(E.bid(round, seat, "pass"), null);
  const view = E.toSeatView(game, round, 1, players);
  assert.equal(view.phase, "burying");
  assert.equal(view.bidding, null);
  assert.equal(view.dealer, 2, "seat 3 declared and deals (seat 2 from seat 1)");
  assert.equal(view.turn, 2, "the dealer must bury");
  assert.equal(E.toSeatView(game, round, 3, players).kitty?.length, 8, "the dealer sees the kitty");
});

const snapshot: GameSnapshot = {
  id: "g_1",
  clubId: "c_1",
  createdBy: "u_mei",
  createdAt: "2026-01-01T00:00:00.000Z",
  updatedAt: "2026-01-01T00:00:01.000Z",
  status: "active",
  version: 7,
  players,
  levels: [5, 3],
  targetRank: 14,
  roundNumber: 2,
  phase: "playing",
  turn: 3,
  winner: null,
  lastEvent: { type: "play", seat: 2, cards: [c(13, 0), c(13, 0, 1)], lead: true, failedThrow: false },
};

test("summaries are viewer-relative, and someone not seated sees seat order from seat 0", () => {
  const sam = summarize(snapshot, 3);
  assert.deepEqual(sam.players.map((p) => p.name), ["Sam", "Mei", "Tiger Bot", "Lin"]);
  assert.deepEqual(sam.teamLevels, [3, 5]);
  assert.equal(sam.turn, 0);
  assert.equal(sam.yourTurn, true);
  assert.equal(sam.lastEvent, "Lin led K♠ K♠");
  const lin = summarize(snapshot, 2);
  assert.deepEqual(lin.teamLevels, [5, 3]);
  assert.equal(lin.turn, 1);
  assert.equal(lin.yourTurn, false);
  assert.equal(lin.lastEvent, "You led K♠ K♠");
  const outsider = summarize(snapshot, null);
  assert.deepEqual(outsider.players, players);
  assert.equal(outsider.turn, 3);
  assert.equal(outsider.yourTurn, false);
  assert.equal(outsider.lastEvent, "Lin led K♠ K♠");
  const finished = summarize({ ...snapshot, status: "finished", turn: null, winner: 1 }, 1);
  assert.deepEqual([finished.winnerTeam, finished.yourTurn, finished.turn], [0, false, null]);
  assert.deepEqual(Object.keys(sam).sort(), [
    "clubId", "createdAt", "id", "lastEvent", "phase", "players", "roundNumber", "startedByYou", "status", "targetRank",
    "teamLevels", "turn", "updatedAt", "winnerTeam", "yourTurn",
  ]);
});

test("only the player who started a game is told so (only they can end it)", () => {
  const creator = players.findIndex((p) => p.userID === snapshot.createdBy);
  assert.ok(creator >= 0);
  for (const seat of [0, 1, 2, 3]) assert.equal(summarize(snapshot, seat).startedByYou, seat === creator, `seat ${seat}`);
  assert.equal(summarize(snapshot, null).startedByYou, false);
});

test("event lines name people (\"You\" for the viewer) and never more than the event shows", () => {
  const lines = (event: GameEvent) => [0, 1, 2, 3, null].map((v) => eventText(event, players, v));
  assert.deepEqual(lines({ type: "started", seat: 0 }), ["You started the game", "Mei started the game", "Mei started the game", "Mei started the game", "Mei started the game"]);
  assert.equal(eventText({ type: "pass", seat: 1 }, players, 0), "Tiger Bot passed");
  assert.equal(eventText({ type: "bury", seat: 3 }, players, 3), "You buried the kitty");
  assert.equal(
    eventText({ type: "bid", seat: 2, declaration: { player: 2, cards: [c(2, 1), c(2, 1, 1)], suit: 1, strength: 2 } }, players, 0),
    "Lin declared ♥ (pair of 2♥)",
  );
  assert.equal(
    eventText({ type: "bid", seat: 0, declaration: { player: 0, cards: [E.bigJoker(), E.bigJoker(1)], suit: null, strength: 4 } }, players, 0),
    "You declared no trump (pair of big jokers)",
  );
  assert.equal(eventText({ type: "play", seat: 3, cards: [c(10, 3)], lead: false, failedThrow: false }, players, 0), "Sam played 10♦");
  assert.equal(eventText({ type: "play", seat: 0, cards: [c(9, 0)], lead: true, failedThrow: true }, players, 0), "You tried a throw that failed and led 9♠");
  const round = (team: number, tookOver: boolean, levelsGained: number, gameWinner: number | null): GameEvent => ({
    type: "round", round: 3, team, tookOver, levelsGained, newLevel: 7, gameWinner,
  });
  assert.deepEqual(lines(round(0, true, 0, null)), [
    "Round 3: your team took over the deal",
    "Round 3: Mei and Lin took over the deal",
    "Round 3: your team took over the deal",
    "Round 3: Mei and Lin took over the deal",
    "Round 3: Mei and Lin took over the deal",
  ]);
  assert.equal(eventText(round(1, false, 2, null), players, 1), "Round 3: your team kept the deal and went up 2 levels to 7");
  assert.equal(eventText(round(1, false, 1, null), players, 0), "Round 3: Tiger Bot and Sam kept the deal and went up 1 level to 7");
  assert.equal(eventText(round(1, false, 0, 1), players, 3), "Round 3: your team won the game");
  assert.equal(eventText(round(1, false, 0, 1), players, 2), "Round 3: Tiger Bot and Sam won the game");
  for (const line of [...lines(round(0, true, 3, null)), ...lines({ type: "pass", seat: 2 })]) {
    assert.ok(!line.includes(String.fromCharCode(0x2014)), "no em dashes in learner-facing text");
  }
});

test("tables of 6 and 8: summaries rotate every seat, teams are named in full, bids of three or four cards", () => {
  const six: E.SeatPlayer[] = ["Mei", "Panda Bot", "Lin", "Crane Bot", "Sam", "Koi Bot"].map((name, seat) => ({
    name,
    isBot: seat % 2 === 1,
    userID: seat % 2 === 1 ? null : `u_${name.toLowerCase()}`,
  }));
  const sixGame: GameSnapshot = { ...snapshot, players: six, turn: 5, lastEvent: { type: "pass", seat: 4 } };
  const lin = summarize(sixGame, 2);
  assert.deepEqual(lin.players.map((p) => p.name), ["Lin", "Crane Bot", "Sam", "Koi Bot", "Mei", "Panda Bot"]);
  assert.deepEqual([lin.turn, lin.yourTurn, lin.teamLevels], [3, false, [5, 3]]);
  assert.equal(lin.lastEvent, "Sam passed");
  const koi = summarize(sixGame, 5);
  assert.deepEqual([koi.turn, koi.yourTurn, koi.teamLevels], [0, true, [3, 5]]);
  assert.deepEqual(summarize(sixGame, null).players, six);

  const round = (team: number, gameWinner: number | null): GameEvent => ({
    type: "round", round: 2, team, tookOver: true, levelsGained: 1, newLevel: 3, gameWinner,
  });
  assert.equal(eventText(round(0, null), six, 1), "Round 2: Mei, Lin and Sam took over the deal and went up 1 level to 3");
  assert.equal(eventText(round(1, null), six, null), "Round 2: Panda Bot, Crane Bot and Koi Bot took over the deal and went up 1 level to 3");
  assert.equal(eventText(round(0, 0), six, 4), "Round 2: your team won the game");
  const eight = [...six, { name: "Jo", isBot: false, userID: "u_jo" }, { name: "Yak Bot", isBot: true, userID: null }];
  assert.equal(eventText(round(1, null), eight, 0), "Round 2: Panda Bot, Crane Bot, Koi Bot and Yak Bot took over the deal and went up 1 level to 3");
  assert.equal(eventText(round(0, null), eight, null), "Round 2: Mei, Lin, Sam and Jo took over the deal and went up 1 level to 3");

  const three = [0, 1, 2].map((copy) => c(2, 0, copy));
  assert.equal(eventText({ type: "bid", seat: 6, declaration: { player: 6, cards: three, suit: 0, strength: 5 } }, eight, 0),
    "Jo declared ♠ (three 2♠)");
  const jokers = [0, 1, 2, 3].map((copy) => E.smallJoker(copy));
  assert.equal(eventText({ type: "bid", seat: 6, declaration: { player: 6, cards: jokers, suit: null, strength: 9 } }, eight, 6),
    "You declared no trump (four small jokers)");
});

test("tables of 6 and 8: bidding views rotate every seat; the dealer of 6 sees a kitty of 6", () => {
  const table = E.tableSize(6);
  const game = E.newGame({ startRank: 2, targetRank: 14, table });
  const seats: E.SeatPlayer[] = E.allSeats(6).map((seat) => ({ name: `P${seat}`, isBot: false, userID: `u_${seat}` }));
  const round = E.startOnlineRound(game, E.deckCards(3), 4);
  assert.equal(E.bid(round, 4, "pass"), null);
  for (let viewer = 0; viewer < 6; viewer++) {
    const view = E.toSeatView(game, round, viewer, seats);
    const rel = (s: number) => (s - viewer + 6) % 6;
    assert.deepEqual(view.handCounts, [26, 26, 26, 26, 26, 26]);
    assert.deepEqual(view.players.map((p) => p.name), E.allSeats(6).map((i) => `P${(i + viewer) % 6}`));
    assert.equal(view.bidding?.turn, rel(5));
    assert.deepEqual(view.bidding?.history, [{ player: rel(4), declaration: null }]);
    assert.equal(view.bidding?.available.length === 0, viewer !== 5);
  }
  // Everyone passes: the kitty flip sets trump and the first bidder (seat 4) deals.
  for (const seat of [5, 0, 1, 2, 3]) assert.equal(E.bid(round, seat, "pass"), null);
  assert.equal(round.phase, "burying");
  const dealerView = E.toSeatView(game, round, 4, seats);
  assert.deepEqual([dealerView.dealer, dealerView.turn, dealerView.kitty?.length, dealerView.hand.length], [0, 0, 6, 32]);
  assert.equal(E.toSeatView(game, round, 1, seats).kitty, null);
});
