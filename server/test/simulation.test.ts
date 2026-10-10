// Whole random games played through the online flow (bidding, burying, random legal plays found
// by searching candidates with validateFollow), checking the invariants of every round.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, GameSettings, Round } from "../src/engine/index.ts";
import { finishBidding, followCandidates, randomBidding, randomBury, randomPlay } from "./play.ts";
import { seededRandom } from "./support.ts";
import type { Rng } from "./support.ts";

const ALL = E.doubleDeck();

function sorted(cards: readonly Card[]): Card[] {
  return cards.slice().sort((a, b) => a - b);
}

/** Every card is in exactly one place. */
function assertConservation(round: Round, where: string): void {
  const places: Card[] = [...round.hands.flat(), ...round.undealt, ...E.playedCards(round)];
  // While burying, the kitty is in the dealer's hand; afterwards it is set aside.
  if (round.phase === "dealing" || round.phase === "playing" || round.phase === "finished") places.push(...round.kitty);
  assert.deepEqual(sorted(places), ALL, `${where}: cards are lost or duplicated`);
}

interface RoundStats {
  tricks: number;
  throwsFailed: number;
  illegalChecked: number;
}

/** Plays one round of the online flow to the end, checking invariants after every action. */
/** Plays a round to the end; bidding is opened at `firstBidder` unless it is already open. */
function playRound(round: Round, firstBidder: number, rng: Rng): RoundStats {
  const stats: RoundStats = { tricks: 0, throwsFailed: 0, illegalChecked: 0 };
  if (round.bidding === null) randomBidding(round, firstBidder, rng);
  else finishBidding(round, rng);
  assertConservation(round, "after bidding");
  const dealer = round.dealer as number;
  assert.equal(round.phase as string, "burying");
  assert.deepEqual(round.hands.map((h) => h.length), [0, 1, 2, 3].map((s) => (s === dealer ? 33 : 25)));
  randomBury(round, rng);
  assertConservation(round, "after burying");
  assert.ok(round.hands.every((h) => h.length === 25));

  const cardsPlayed = [0, 0, 0, 0];
  let guard = 0;
  while (round.phase === "playing") {
    assert.ok(guard++ < 200, "the round must finish");
    const player = E.turn(round) as number;
    const lead = E.currentLead(round);
    // Every candidate the search rejects is rejected by play() with the same violation.
    if (lead.length > 0) {
      for (const cards of followCandidates(round.hands[player], lead, round.trump, rng)) {
        const violation = E.validateFollow(cards, round.hands[player], lead, round.trump);
        if (violation === null) continue;
        const before = JSON.stringify(round);
        const result = E.play(round, cards, player);
        assert.deepEqual(result, { ok: false, error: { case: "illegalFollow", violation } });
        assert.equal(JSON.stringify(round), before, "a rejected play must not change the round");
        stats.illegalChecked++;
      }
    }
    const tricksBefore = round.tricks.length;
    const handBefore = round.hands[player].length;
    const { cards, result } = randomPlay(round, rng);
    assert.ok(result.ok);
    const played = result.outcome.type === "throwFailed" ? result.outcome.forced : cards;
    if (result.outcome.type === "throwFailed") {
      stats.throwsFailed++;
      assert.ok(E.isThrow(cards, round.trump));
      assert.ok(result.outcome.forced.every((card) => cards.includes(card)));
      assert.notEqual(result.outcome.blocker, player);
    }
    cardsPlayed[player] += played.length;
    assert.equal(round.hands[player].length, handBefore - played.length);
    assertConservation(round, `trick ${round.tricks.length + 1}`);
    if (round.tricks.length > tricksBefore) {
      const trick = round.tricks[round.tricks.length - 1];
      assert.equal(trick.plays.length, 4);
      assert.ok(trick.plays.every((p) => p.cards.length === trick.plays[0].cards.length), "equal-size plays");
      assert.deepEqual(trick.plays.map((p) => p.player), [0, 1, 2, 3].map((k) => (E.trickLeader(trick) + k) % 4));
      assert.equal(trick.points, E.totalPoints(trick.plays.flatMap((p) => p.cards)));
      assert.equal(trick.winner, trick.plays[E.winningIndex(trick.plays, round.trump)].player);
      if (round.phase === "playing") assert.equal(round.leader, trick.winner, "the winner leads next");
    }
  }
  stats.tricks = round.tricks.length;

  // Every player played all 25 cards.
  assert.deepEqual(cardsPlayed, [25, 25, 25, 25]);
  assert.equal(round.phase, "finished");
  const result = round.result as E.RoundResult;
  // 200 points in all: tricks plus kitty.
  assert.equal(round.tricks.reduce((sum, t) => sum + t.points, 0) + E.totalPoints(round.kitty), E.TOTAL_POINTS);
  // Defenders' trick points are the points of the tricks they won.
  const defenderTricks = round.tricks.filter((t) => E.isDefender(round, t.winner));
  assert.equal(result.trickPoints, defenderTricks.reduce((sum, t) => sum + t.points, 0));
  assert.equal(result.trickPoints, round.defenderTrickPoints);
  const last = round.tricks[round.tricks.length - 1];
  assert.equal(result.lastTrickWinner, last.winner);
  assert.equal(result.kittyMultiplier, E.isDefender(round, last.winner) ? E.kittyMultiplier(last.plays[0].cards, round.trump) : 0);
  assert.equal(result.kittyPoints, E.totalPoints(round.kitty));
  assert.equal(result.defenderPoints, result.trickPoints + result.kittyPoints * result.kittyMultiplier);
  assert.deepEqual(result.outcome, E.scoreOutcome(result.defenderPoints));
  assert.equal(result.dealer, dealer);
  assert.equal(result.declarerTeam, dealer % 2);
  assert.deepEqual(result.kitty, round.kitty);
  assert.ok(stats.tricks >= 1 && stats.tricks <= 25);
  // Nothing more can be played.
  assert.deepEqual(E.play(round, [], round.leader), { ok: false, error: { case: "wrongPhase" } });
  return stats;
}

function playGame(settings: GameSettings, creator: number, rng: Rng, maxRounds: number): {
  game: E.GameState;
  stats: RoundStats[];
} {
  let game = E.newGame(settings);
  const stats: RoundStats[] = [];
  while (game.winner === null && game.roundsPlayed < maxRounds) {
    const before = game.levels.slice();
    const dealerBefore = game.nextDealer;
    // Seeded decks (not shuffledDeck) so a failure can be replayed from the seed.
    let round = E.startOnlineRound(game, rng.shuffle(ALL), creator);
    assert.equal(E.biddingTurn(round), dealerBefore ?? creator);
    assert.equal(round.trumpRank, E.nextTrumpRank(game));
    assert.equal(round.dealer, dealerBefore);
    // Stored as JSON between every step, as the Durable Object does.
    round = JSON.parse(JSON.stringify(round)) as Round;
    stats.push(playRound(round, dealerBefore ?? creator, rng));
    const result = (JSON.parse(JSON.stringify(round)) as Round).result as E.RoundResult;
    if (dealerBefore !== null) assert.equal(result.dealer, dealerBefore, "the dealer keeps the deal after round 1");
    const summary = E.recordRound(game, result);
    game = JSON.parse(JSON.stringify(game)) as E.GameState;
    // Levels only go up, by what the summary says, never past the target.
    const team = summary.advancingTeam;
    for (const t of [0, 1]) {
      const gain = t === team ? summary.levelsGained : 0;
      assert.equal(game.levels[t], before[t] + gain);
      assert.ok(game.levels[t] <= Math.max(settings.targetRank, settings.startRank));
    }
    const declarers = result.dealer % 2;
    assert.equal(game.nextDealer, result.outcome.declarersHold ? (result.dealer + 2) % 4 : (result.dealer + 1) % 4);
    if (summary.gameWinner !== null) {
      assert.equal(summary.gameWinner, declarers);
      assert.ok(result.outcome.declarersHold);
      assert.equal(before[declarers], settings.targetRank);
    }
    assert.ok(summary.explanation.length > 0 && !summary.explanation.includes("\u2014"));
  }
  return { game, stats };
}

test("random games to the end (short targets), every round checked", () => {
  const rng = seededRandom(99);
  let rounds = 0;
  let throwsFailed = 0;
  let illegal = 0;
  const settingsList: GameSettings[] = [
    { startRank: 2, targetRank: 4 },
    { startRank: 10, targetRank: 13 },
    { startRank: 12, targetRank: 14 },
    { startRank: 2, targetRank: 6 },
    { startRank: 14, targetRank: 14 },
  ];
  for (let g = 0; g < 10; g++) {
    const settings = settingsList[g % settingsList.length];
    const { game, stats } = playGame(settings, g % 4, rng, 60);
    assert.notEqual(game.winner, null, `game ${g} did not finish in 60 rounds`);
    assert.equal(game.history.length, game.roundsPlayed);
    rounds += stats.length;
    for (const s of stats) {
      throwsFailed += s.throwsFailed;
      illegal += s.illegalChecked;
    }
  }
  assert.ok(rounds >= 20, `only ${rounds} rounds`);
  assert.ok(throwsFailed > 20, `only ${throwsFailed} failed throws`);
  assert.ok(illegal > 500, `only ${illegal} illegal candidates checked`);
});

test("a full game from 2 to A reaches a winner", () => {
  const rng = seededRandom(2026);
  const { game } = playGame({ startRank: 2, targetRank: 14 }, 0, rng, 300);
  assert.notEqual(game.winner, null);
  assert.equal(game.levels[game.winner as number], 14);
});

test("many single rounds with every trump rank and both a known and an unknown dealer", () => {
  const rng = seededRandom(7);
  for (let n = 0; n < 60; n++) {
    const dealer = n % 5 === 0 ? null : rng.below(4);
    const round = E.newRound(E.ALL_RANKS[n % 13], dealer, rng.shuffle(ALL));
    playRound(round, dealer ?? rng.below(4), rng);
  }
});
