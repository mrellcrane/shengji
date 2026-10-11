// Finding Friends (tables of 5, 7 or 9): the engine port of Engine/Friends.swift and the odd-table
// parts of Round, GameState and the seat views, after the Swift FindingFriendsTests. The vectors
// (vectors.test.ts) prove the same behaviour on random rounds and games; these name the rules.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, FriendCall, Rank, Round, RoundResult, Suit } from "../src/engine/index.ts";
import { randomPlay } from "./play.ts";
import { buildDeck, seededRandom } from "./support.ts";

const S: Suit = 0;
const H: Suit = 1;
const C: Suit = 2;
const D: Suit = 3;
const c = (rank: Rank, suit: Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
const call = (rank: Rank, suit: Suit, ordinal = 1): FriendCall => E.friendCall(E.regularFace(rank, suit), ordinal);

// MARK: Calls

test("friend calls: exactly the table's friends, suited cards not of the trump rank, copies that exist, none twice", () => {
  const nine = E.tableSize(9);
  const five = E.tableSize(5);
  const good = [call(14, S), call(14, C), call(13, S, 2)];
  assert.equal(E.friendCallProblem(good, nine, 2), null);
  assert.equal(E.friendCallProblem(good.slice(0, 2), nine, 2), "Call exactly 3 friends (you called 2).");
  assert.equal(E.friendCallProblem([], five, 2), "Call exactly 1 friend (you called 0).");
  assert.equal(E.friendCallProblem([call(14, S)], five, 2), null);
  assert.equal(E.friendCallProblem([E.friendCall(E.BIG_JOKER_FACE)], five, 2), "Jokers can't be called: pick a suited card.");
  assert.equal(E.friendCallProblem([call(2, C)], five, 2), "Trump-rank cards (2) can't be called: pick another card.");
  assert.equal(E.friendCallProblem([call(14, C, 4)], five, 2),
    "With 3 decks there are only 3 copies of each card: call one of the first 3.");
  assert.equal(E.friendCallProblem([call(14, C, 3)], five, 2), null);
  assert.notEqual(E.friendCallProblem([call(14, C, 0)], five, 2), null);
  assert.equal(E.friendCallProblem([call(14, C), call(14, C)], E.tableSize(7), 2),
    "You called the first A♣ twice: pick a different card or copy.");
  assert.equal(E.friendCallProblem([call(14, C)], E.tableSize(4), 2), "Only a table with an odd number of players calls friends.");
  assert.equal(E.friendCallProblem([], E.tableSize(8), 2), null);
  assert.equal(E.friendCallDescription(call(13, H, 2)), "the second K♥");
  assert.equal(E.friendCallList([call(14, S), call(14, C)]), "the first A♠ and the first A♣");
  assert.equal(E.friendCallList([]), "no friends");
});

test("friend calls from a client: well-formed lists only, always unfound", () => {
  assert.deepEqual(E.parseFriendCalls([{ face: 12, ordinal: 2 }]), [{ face: 12, ordinal: 2, friend: null }]);
  assert.deepEqual(E.parseFriendCalls([{ face: 12, ordinal: 1, friend: 3 }]), [{ face: 12, ordinal: 1, friend: null }]);
  // Jokers and copies that don't exist are well formed: the engine explains why they can't be called.
  assert.deepEqual(E.parseFriendCalls([{ face: 53, ordinal: 9 }]), [{ face: 53, ordinal: 9, friend: null }]);
  for (const bad of [null, {}, "12", [12], [{ face: 54, ordinal: 1 }], [{ face: -1, ordinal: 1 }], [{ face: 1.5, ordinal: 1 }],
    [{ face: 12 }], [{ face: 12, ordinal: "1" }], [{ ordinal: 1 }]]) {
    assert.equal(E.parseFriendCalls(bad), null, JSON.stringify(bad));
  }
  assert.equal(E.parseFriendCalls(new Array(4).fill({ face: 1, ordinal: 1 }), 3), null, "too many");
});

test("counting copies finds the friend: the play that reaches the called copy", () => {
  const calls = [call(14, S, 2), call(13, C)];
  // One A♠ already played: the next one is the second.
  const first = E.notingFriends(calls, [c(14, S, 1)], 3, [c(14, S, 0)]);
  assert.deepEqual(first.map((x) => x.friend), [3, null]);
  assert.deepEqual(calls.map((x) => x.friend), [null, null], "the input is not changed");
  // A pair of A♠ led first: its second card reaches the call.
  assert.deepEqual(E.notingFriends(calls, [c(14, S, 0), c(14, S, 1)], 4, []).map((x) => x.friend), [4, null]);
  // A third A♠ is too late; a found call never changes.
  const late = E.notingFriends(first, [c(14, S, 2), c(13, C, 1)], 1, [c(14, S, 0), c(14, S, 1)]);
  assert.deepEqual(late.map((x) => x.friend), [3, 1]);
});

// MARK: A round

/**
 * Five players, hearts trump (rank 2), seat 0 deals and calls `calls` (the first K♣ by default). Seat
 * 2 holds A♠ and K♣, so it wins the first trick (10 points) before anyone knows it is the friend.
 */
function fivePlayerRound(calls: FriendCall[] = [call(13, C)]): Round {
  const hands = [
    [c(2, H), c(3, S), c(5, C)],
    [c(13, S), c(6, C)],
    [c(14, S), c(13, C)],
    [c(4, S), c(3, C)],
    [c(6, S), c(4, C)],
  ];
  const round = E.newRound(2, 0, buildDeck(hands, [], 0, 5, 5), E.tableSize(5));
  E.dealAll(round);
  assert.equal(E.declare(round, { player: 0, cards: [c(2, H)], suit: H, strength: 1 }), null);
  E.finishDealing(round);
  const keep = new Set([c(2, H), c(3, S), c(5, C)]);
  const bury = round.hands[0].filter((card) => !keep.has(card)).slice(0, E.kittySizeOf(round));
  assert.deepEqual(E.bury(round, bury), { case: "invalidBury", reason: "Call exactly 1 friend (you called 0)." });
  assert.equal(round.phase, "burying", "a refused burial changes nothing");
  assert.equal(E.bury(round, bury, 0, calls), null);
  return round;
}

function playAll(round: Round, plays: [number, Card][]): void {
  for (const [seat, card] of plays) {
    const result = E.play(round, [card], seat);
    assert.ok(result.ok, result.ok ? "" : E.roundErrorExplanation(result.error));
  }
}

function playOut(round: Round, seed: number): void {
  const rng = seededRandom(seed);
  for (let moves = 0; round.phase === "playing"; moves++) {
    assert.ok(moves < 600);
    randomPlay(round, rng);
  }
}

test("a friend is found when the called card is played: their tricks move to the dealer's side", () => {
  const round = fivePlayerRound();
  assert.ok(E.roundFindsFriends(round));
  assert.deepEqual(E.friendCallsOf(round), [call(13, C)]);
  assert.deepEqual([E.declarers(round), E.declarerTeam(round)], [[0], 0]);
  assert.deepEqual(E.toSeatView(E.newGame({ startRank: 2, targetRank: 14, table: E.tableSize(5) }), round, 2,
    E.allSeats(5).map((s) => ({ name: `P${s}`, isBot: false, userID: null }))).friendCalls, [call(13, C)]);

  playAll(round, [[0, c(3, S)], [1, c(13, S)], [2, c(14, S)], [3, c(4, S)], [4, c(6, S)]]);
  assert.equal(E.lastTrick(round)?.winner, 2);
  assert.ok(E.isDefender(round, 2), "a hidden friend counts as a defender");
  assert.equal(round.defenderTrickPoints, 10);

  playAll(round, [[2, c(13, C)]]);
  assert.equal(E.friendCallsOf(round)[0].friend, 2);
  assert.deepEqual(E.declarers(round), [0, 2]);
  assert.ok(E.isDeclarer(round, 2));
  assert.equal(round.defenderTrickPoints, 0, "the friend's trick moves to the dealer's side");
  playAll(round, [[3, c(3, C)], [4, c(4, C)], [0, c(5, C)], [1, c(6, C)]]);
  assert.equal(E.lastTrick(round)?.winner, 2);
  assert.equal(round.defenderTrickPoints, 0);

  // The view: friends are public, seats rotate.
  const game = E.newGame({ startRank: 2, targetRank: 14, table: E.tableSize(5) });
  const seats = E.allSeats(5).map((s) => ({ name: `P${s}`, isBot: false, userID: null }));
  const view = E.toSeatView(game, round, 2, seats);
  assert.equal(view.friendCalls?.[0].friend, 0);
  assert.equal(view.dealer, 3);
  assert.deepEqual([E.viewDeclarers(view), E.viewDeclarerTeam(view), E.viewFindsFriends(view)], [[3, 0], 0, true]);
  assert.equal(E.viewDeclarerTeam(E.toSeatView(game, round, 1, seats)), 1);
  assert.deepEqual(JSON.parse(JSON.stringify(round)), round, "the round survives JSON storage");

  playOut(round, 9);
  const result = round.result as RoundResult;
  assert.deepEqual(result.declarers, [0, 2]);
  assert.equal(result.friendCalls?.[0].friend, 2);
  assert.equal(result.declarerTeam, 0);
  assert.deepEqual(result.outcome, E.scoreOutcome(result.defenderPoints, 3), "a full side earns no bonus");
  const defenderTricks = round.tricks.filter((t) => t.winner !== 0 && t.winner !== 2).reduce((sum, t) => sum + t.points, 0);
  assert.equal(result.trickPoints, defenderTricks);
  // Seen from a defender, the dealer's side is the other team.
  assert.equal(E.rotateResult(result, 1, 5).declarerTeam, 1);
  assert.equal(E.rotateResult(result, 2, 5).declarerTeam, 0);
  assert.deepEqual(E.rotateResult(result, 2, 5).declarers, [3, 0]);
  assert.deepEqual(E.rotateResult(result, 2, 5).friendCalls?.[0].friend, 0);
});

test("the dealer can be their own friend: the side plays short-handed and earns a level more if it holds", () => {
  const round = fivePlayerRound([call(5, C)]);
  playAll(round, [[0, c(5, C)], [1, c(6, C)], [2, c(13, C)], [3, c(3, C)], [4, c(4, C)]]);
  assert.equal(E.friendCallsOf(round)[0].friend, 0);
  assert.deepEqual(E.declarers(round), [0]);
  playOut(round, 11);
  const result = round.result as RoundResult;
  assert.deepEqual(result.declarers, [0]);
  const plain = E.scoreOutcome(result.defenderPoints, 3);
  if (plain.declarersHold) {
    assert.equal(result.outcome.levels, plain.levels + 1, "short-handed bonus");
    assert.match(result.outcome.summary, /short-handed \(1 of 2\)/);
  } else {
    assert.deepEqual(result.outcome, plain);
  }
});

test("the short-handed bonus: one level more for a side that holds with fewer than it could have had", () => {
  const base = E.scoreOutcome(45, 5);
  assert.equal(base.levels, 2);
  const bonus = E.findingFriendsOutcome(base, 3, 4);
  assert.deepEqual(bonus, {
    declarersHold: true,
    levels: 3,
    summary: "Defenders scored 45 (under 100): the declarers keep the deal and go up 2 levels, plus 1 for playing " +
      "short-handed (3 of 4): 3 levels in all.",
  });
  assert.deepEqual(E.findingFriendsOutcome(base, 4, 4), base);
  const takeover = E.scoreOutcome(250, 5);
  assert.deepEqual(E.findingFriendsOutcome(takeover, 1, 4), takeover);
});

test("calls at a table of fixed teams are refused; a bury at an odd table keeps the calls unfound", () => {
  const four = E.newRound(2, 1, seededRandom(4).shuffle(E.doubleDeck()));
  E.dealAll(four);
  E.finishDealing(four);
  const cards = four.hands[1].slice(0, 8);
  assert.deepEqual(E.bury(four, cards, 1, [call(14, S)]),
    { case: "invalidBury", reason: "Only a table with an odd number of players calls friends." });
  assert.equal(E.bury(four, cards, 1, []), null);
  assert.equal(four.friendCalls, undefined, "no calls are kept at a table of fixed teams");
  assert.equal(E.declarerTeam(four), 1);

  const seven = E.newRound(3, 6, seededRandom(7).shuffle(E.deckCards(4)), E.tableSize(7));
  E.dealAll(seven);
  E.finishDealing(seven);
  assert.equal(seven.hands[6].length, 36);
  const buried = seven.hands[6].slice(0, 6);
  // Calls are checked before the cards, and a malformed one is refused without throwing.
  assert.deepEqual(E.bury(seven, buried.slice(1), 6, [call(14, S)]),
    { case: "invalidBury", reason: "Call exactly 2 friends (you called 1)." });
  assert.equal(E.bury(seven, buried, 6, [{ face: "A♠" }] as unknown as FriendCall[])?.case, "invalidBury");
  assert.equal(E.bury(seven, buried, 6, [{ ...call(14, S), friend: 4 }, call(13, D, 4)]), null);
  assert.deepEqual(E.friendCallsOf(seven), [call(14, S), call(13, D, 4)]);
});

// MARK: Games

function result(dealer: number, declarers: number[], points: number, players = 9): RoundResult {
  const table = E.tableSize(players);
  const outcome = E.findingFriendsOutcome(E.scoreOutcome(points, table.decks), declarers.length, E.tableTeamSize(table));
  return {
    dealer, declarerTeam: declarers.includes(0) ? 0 : 1, trump: { rank: 2, suit: S }, trickPoints: points,
    kittyPoints: 0, kittyMultiplier: 0, defenderPoints: points, outcome, kitty: [], lastTrickWinner: 1,
    declarers, friendCalls: [],
  };
}

const labels = (levels: readonly Rank[]): string[] => levels.map(E.rankLabel);

test("everyone keeps their own level: the winning side goes up, and the deal passes along the side", () => {
  const game = E.newGame({ startRank: 2, targetRank: 14, table: E.tableSize(9) });
  assert.equal(game.levels.length, 9);
  assert.ok(E.gameFindsFriends(game));
  // Dealer 4 with friends 6, 8 and 1 hold with 45 points (2 levels).
  const first = E.recordRound(game, result(4, [4, 6, 8, 1], 45));
  assert.deepEqual(labels(game.levels), ["2", "4", "2", "2", "4", "2", "4", "2", "4"]);
  assert.equal(first.nextDealer, 6, "the dealer's next friend deals");
  assert.equal(first.advancingTeam, 1, "seat 0 was a defender");
  assert.equal(first.levelsGained, 2);
  assert.equal(E.nextTrumpRank(game), 4);
  assert.match(first.explanation, /^North-northeast, Northwest, Southwest and Southeast played together/);
  assert.match(first.explanation, /200/);

  // Dealer 6 is taken over (300 points: +1 for the defenders): the next defender after 6 deals.
  const second = E.recordRound(game, result(6, [6, 7, 2, 4], 300));
  assert.equal(second.nextDealer, 8);
  assert.deepEqual(labels(game.levels), ["3", "5", "2", "3", "4", "3", "4", "2", "5"]);
  assert.equal(second.advancingTeam, 0, "seat 0 defended");
  assert.match(second.explanation, /You are now at level 3\./);
  assert.match(second.explanation, /The defenders go up 1 level\./);

  // Playing alone and holding: the dealer deals again, with the bonus level.
  const third = E.recordRound(game, result(8, [8], 100));
  assert.equal(third.nextDealer, 8);
  assert.equal(game.levels[8], 7);
  assert.match(third.explanation, /^Southwest played alone: no friend joined\./);
  assert.match(third.explanation, /Southwest goes up 2 levels \(1 of them for playing short-handed\)\./);
  assert.equal(E.levelOf(game, 8), 7);
  assert.deepEqual(JSON.parse(JSON.stringify(game)), game);
});

test("the dealer's side wins the game by holding at the target; the winners are that side", () => {
  const game = E.newGame({ startRank: 14, targetRank: 14, table: E.tableSize(5) });
  const summary = E.recordRound(game, result(3, [3, 0], 10, 5));
  assert.equal(summary.gameWinner, 0, "seat 0 was on the winning side");
  assert.equal(game.winner, 0);
  assert.deepEqual(E.gameWinners(game), [0, 3]);
  assert.match(summary.explanation, /so you win the game!/);
  const other = E.rotateSummary(summary, 1, 14, 5);
  assert.equal(other.gameWinner, 1);
  assert.match(other.explanation, /so they win the game\./);
  assert.equal(E.rotateSummary(summary, 3, 14, 5).gameWinner, 0);
  assert.equal(E.summaryExplanation(game, summary, 1), other.explanation);

  const lost = E.newGame({ startRank: 14, targetRank: 14, table: E.tableSize(5) });
  assert.equal(E.recordRound(lost, result(3, [3, 4], 10, 5)).gameWinner, 1);
  assert.deepEqual(E.gameWinners(lost), [3, 4]);
  // Seen by each seat, the winner is "your side" exactly for the winners.
  const seats = E.allSeats(5).map((s) => ({ name: `P${s}`, isBot: false, userID: null }));
  const round = E.newRound(14, 0, E.deckCards(3), E.tableSize(5));
  assert.deepEqual(E.allSeats(5).map((seat) => E.toSeatView(lost, round, seat, seats).gameWinnerTeam), [1, 1, 1, 0, 0]);
});

test("summaries rotate seats, levels and sides for each viewer (seat 0 is \"you\" inside a list)", () => {
  const game = E.newGame({ startRank: 2, targetRank: 14, table: E.tableSize(7) });
  const summary = E.recordRound(game, result(2, [2, 5, 6], 0, 7));
  const rotated = E.rotateSummary(summary, 5, 14, 7);
  assert.equal(rotated.result.dealer, 4);
  assert.deepEqual(rotated.result.declarers, [4, 0, 1]);
  assert.deepEqual(labels(rotated.levelsAfter), ["5", "5", "2", "2", "5", "2", "2"]);
  assert.equal(rotated.advancingTeam, 0);
  assert.equal(summary.advancingTeam, 1);
  assert.equal(rotated.nextDealer, 0, "seat 5 deals next: the viewer");
  assert.match(rotated.explanation, /You deal next/);
  assert.match(rotated.explanation, /^Northwest, you and Southeast played together/);
  // The seat view shows the same summary and one level per seat, the viewer's first.
  const seats = E.allSeats(7).map((s) => ({ name: `P${s}`, isBot: false, userID: null }));
  const round = E.makeRound(game, E.deckCards(4));
  const view = E.toSeatView(game, round, 5, seats);
  assert.deepEqual(view.lastRoundSummary, rotated);
  assert.deepEqual(view.teamLevels, rotated.levelsAfter);
  assert.equal(round.trumpRank, 5, "seat 5 deals at their own level");
  assert.deepEqual(round.friendCalls, [], "no calls before burying");
  assert.equal(view.friendCalls, null);
});
