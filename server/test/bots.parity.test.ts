// Replays bots.json, written by the Swift ShengjiVectors target from the Swift bots, through the
// TypeScript port in src/bots: at every decision of every round (declaring or bidding, burying,
// leading and following), for both levels, the port must choose exactly the cards the Swift bots
// chose, in the same order. Each round is rebuilt with the TypeScript engine (its parity is proven
// by vectors.test.ts) from the recorded deal and moves, and each view comes from `toSeatView`, the
// view the server sends.
// Regenerate with: cd ShengjiCore && swift run ShengjiVectors ../server/test/vectors

import assert from "node:assert/strict";
import { test } from "node:test";
import { botDiagnostics, cardsToBury, decide, declaration } from "../src/bots/index.ts";
import type { BotLevel } from "../src/bots/index.ts";
import * as E from "../src/engine/index.ts";
import type { Card, Declaration, Rank, Round, RoundResult, SeatPlayer, SeatView, Trump } from "../src/engine/index.ts";
import { loadVectors } from "./support.ts";

type Controller = BotLevel | "random";

interface Step {
  seat: number;
  standard: Card[];
  beginner: Card[];
  /** A random seat's move. */
  move?: Card[];
  /** Offline declaring: cards dealt before this decision. */
  deal?: number;
}

interface BotRound {
  seed: number;
  mode: "online" | "offline";
  trumpRank: Rank;
  dealer: number | null;
  firstBidder?: number;
  controllers: Controller[];
  deck: Card[];
  declaring: Step[];
  burying: Step;
  /** Absent in `deals`, which stop once the kitty is buried. */
  playing?: Step[];
  result?: RoundResult;
}

interface BotsFile {
  format: number;
  rounds: BotRound[];
  deals: BotRound[];
}

const LEVELS: readonly BotLevel[] = ["standard", "beginner"];
const PLAYERS: SeatPlayer[] = [0, 1, 2, 3].map((seat) => ({ name: `Seat ${seat}`, isBot: true, userID: null }));
const SEAT_NAMES = ["you", "right", "partner", "left"];

function sameCards(a: readonly Card[], b: readonly Card[]): boolean {
  return a.length === b.length && a.every((card, index) => card === b[index]);
}

function show(cards: readonly Card[], trump: Trump): string {
  if (cards.length === 0) return "nothing (pass)";
  return `${E.shortText(E.sortCards(trump, cards))}  ids [${cards.join(", ")}]`;
}

/** The situation a decision was made in, in words, for mismatch reports. */
function situation(view: SeatView): string {
  const lines = [
    `phase ${view.phase}, trump ${E.trumpDescription(view.trump)}, dealer ${view.dealer === null ? "none" : SEAT_NAMES[view.dealer]}`,
    `hand: ${E.shortText(E.sortCards(view.trump, view.hand))}`,
  ];
  if (view.declaration !== null) {
    lines.push(`declaration: ${SEAT_NAMES[view.declaration.player]} ${E.shortText(view.declaration.cards)}`);
  }
  if (view.currentTrick.length > 0) {
    lines.push(`trick so far: ${view.currentTrick.map((p) => `${SEAT_NAMES[p.player]} ${E.shortText(p.cards)}`).join(", ")}`);
  }
  if (view.tricks.length > 0) lines.push(`tricks played: ${view.tricks.length}`);
  return lines.join("\n    ");
}

/** Cards of `group` the viewer of `view` has not seen (not in hand, not played, not its buried kitty). */
function unseenCount(view: SeatView, group: E.SuitGroup): number {
  const known = new Set<Card>(view.hand);
  for (const trick of view.tricks) for (const play of trick.plays) for (const card of play.cards) known.add(card);
  for (const play of view.currentTrick) for (const card of play.cards) known.add(card);
  if (view.phase === "playing" && view.dealer === 0) for (const card of view.kitty ?? []) known.add(card);
  let count = 0;
  for (let card = 0; card < E.DECK_SIZE; card++) if (!known.has(card) && E.groupOf(view.trump, card) === group) count++;
  return count;
}

/** Coverage of the vectors: what kinds of decisions they hold. */
function newCoverage() {
  return {
    rounds: { online: 0, offline: 0, noTrump: 0 },
    decisions: 0,
    bids: 0,
    dealingLooks: 0,
    declared: { standard: 0, beginner: 0 },
    noTrumpDeclared: 0,
    overridden: 0,
    buries: 0,
    leads: 0,
    follows: 0,
    throws: 0,
    tractorLeads: 0,
    tractorFollows: 0,
    ruffs: 0,
    /** Standard ruffs of a throw, and of a suit too short for the opponents still to play to follow. */
    throwRuffs: 0,
    shortSuitRuffs: 0,
    seats: [0, 0, 0, 0],
  };
}

interface Replay {
  /** Bot choices that differ from Swift's, and reports of the first ones. */
  mismatches: number;
  failures: string[];
  /** Times the bots fell back to their rules-built safety net. */
  fallbacks: number;
  coverage: ReturnType<typeof newCoverage>;
}

let replayed: Replay | null = null;

/** Replays every round of bots.json once; both tests read the outcome. */
function replay(): Replay {
  if (replayed !== null) return replayed;
  const file = loadVectors<BotsFile>("bots.json");
  assert.equal(file.format, 1);
  const coverage = newCoverage();
  const failures: string[] = [];
  let mismatches = 0;
  const fallbacksBefore = botDiagnostics.fallbacks;

  for (const entry of [...file.rounds, ...file.deals]) {
    const round: Round = E.newRound(entry.trumpRank, entry.dealer, entry.deck);
    const game = E.newGame({ startRank: entry.trumpRank, targetRank: 14 });
    coverage.rounds[entry.mode] += 1;
    const label = (part: string, index: number, step: Step): string =>
      `seed ${entry.seed} (${entry.mode}), ${part} step ${index}, absolute seat ${step.seat}`;

    /** Compares both levels' choices with Swift's; returns the move to make (Swift's, so the replay stays in step). */
    const compare = (context: string, step: Step, view: SeatView, choose: (level: BotLevel) => Card[]): Card[] => {
      coverage.decisions += 1;
      for (const level of LEVELS) {
        const expected = step[level];
        const actual = choose(level);
        if (sameCards(actual, expected)) continue;
        mismatches += 1;
        if (failures.length < 12) {
          failures.push(
            `  ${context}, ${level} bot:\n` +
              `    Swift chose: ${show(expected, view.trump)}\n` +
              `    TS chose:    ${show(actual, view.trump)}\n` +
              `    ${situation(view)}`,
          );
        }
      }
      const controller = entry.controllers[step.seat];
      const move = controller === "random" ? step.move : step[controller];
      assert.ok(move !== undefined, `${context}: no move recorded`);
      return move;
    };

    // Declaring: online turn-based bidding, or offline while the cards are dealt.
    if (entry.mode === "online") {
      assert.equal(E.startBidding(round, entry.firstBidder ?? 0), null);
    }
    entry.declaring.forEach((step, index) => {
      const context = label("declaring", index, step);
      if (step.deal !== undefined) {
        let last = -1;
        for (let i = 0; i < step.deal; i++) last = E.dealNext(round)?.player ?? -1;
        assert.equal(last, step.seat, `${context}: the step's seat did not receive the last card`);
      }
      if (entry.mode === "online") assert.equal(E.biddingTurn(round), step.seat, `${context}: not this seat's turn to bid`);
      const view = E.toSeatView(game, round, step.seat, PLAYERS);
      const available =
        entry.mode === "online"
          ? (view.bidding?.available ?? [])
          : E.availableDeclarations(round, step.seat).map((d) => ({ ...d, player: 0 }));
      if (entry.mode === "online") coverage.bids += 1;
      else coverage.dealingLooks += 1;
      const move = compare(context, step, view, (level) => {
        const choice = declaration(view, available, level);
        if (choice !== null) {
          coverage.declared[level] += 1;
          if (level === "standard" && choice.suit === null) coverage.noTrumpDeclared += 1;
          if (level === "standard" && view.declaration !== null && view.declaration.player !== 0) coverage.overridden += 1;
        }
        return choice?.cards ?? [];
      });
      let made: Declaration | null = null;
      if (move.length > 0) {
        made = E.availableDeclarations(round, step.seat).find((d) => sameCards(d.cards, move)) ?? null;
        assert.ok(made !== null, `${context}: the move is not an available declaration`);
      }
      if (entry.mode === "online") {
        assert.equal(E.bid(round, step.seat, made ?? "pass"), null, `${context}: bid refused`);
      } else if (made !== null) {
        assert.equal(E.declare(round, made), null, `${context}: declaration refused`);
      }
    });
    if (entry.mode === "offline") E.finishDealing(round);
    assert.equal(round.phase, "burying", `seed ${entry.seed}: the declaring did not end`);
    if (round.trump.suit === null) coverage.rounds.noTrump += 1;

    // Burying.
    {
      const step = entry.burying;
      const context = label("burying", 0, step);
      assert.equal(round.dealer, step.seat, `${context}: not the dealer`);
      const view = E.toSeatView(game, round, step.seat, PLAYERS);
      coverage.buries += 1;
      const move = compare(context, step, view, (level) => {
        const cards = cardsToBury(view, level) ?? [];
        assert.deepEqual(decide(view, level), cards, `${context}: decide and cardsToBury differ`);
        return cards;
      });
      assert.equal(E.bury(round, move, step.seat), null, `${context}: bury refused`);
    }
    if (entry.playing === undefined) {
      assert.equal(round.phase, "playing", `seed ${entry.seed}: the burial was not accepted`);
      continue;
    }

    // Playing.
    entry.playing.forEach((step, index) => {
      const context = label("playing", index, step);
      assert.equal(E.turn(round), step.seat, `${context}: not this seat's turn`);
      const view = E.toSeatView(game, round, step.seat, PLAYERS);
      const leading = view.currentTrick.length === 0;
      coverage.seats[step.seat] += 1;
      if (leading) coverage.leads += 1;
      else coverage.follows += 1;
      const lead = leading ? [] : view.currentTrick[0].cards;
      const ledGroup = leading ? null : (E.groupOfCards(lead, view.trump) ?? E.groupOf(view.trump, lead[0]));
      if (!leading && E.decompose(lead, view.trump).some((c) => c.shape.type === "tractor")) coverage.tractorFollows += 1;
      const move = compare(context, step, view, (level) => {
        const cards = decide(view, level) ?? [];
        if (level === "standard" && leading && cards.length > 0) {
          if (E.isThrow(cards, view.trump)) coverage.throws += 1;
          if (E.decompose(cards, view.trump).some((c) => c.shape.type === "tractor")) coverage.tractorLeads += 1;
        }
        if (level === "standard" && ledGroup !== null && ledGroup !== "trump" && cards.length > 0) {
          if (cards.every((card) => E.isTrump(view.trump, card))) {
            coverage.ruffs += 1;
            const later = 3 - view.currentTrick.length;
            const laterOpponents = later >= 3 ? 2 : later >= 1 ? 1 : 0;
            if (E.isThrow(lead, view.trump)) coverage.throwRuffs += 1;
            else if (laterOpponents > 0 && unseenCount(view, ledGroup) < Math.max(1, lead.length * laterOpponents)) {
              coverage.shortSuitRuffs += 1;
            }
          }
        }
        return cards;
      });
      const result = E.play(round, move, step.seat);
      assert.ok(result.ok, `${context}: play refused`);
    });

    assert.equal(round.phase, "finished", `seed ${entry.seed}: the round did not finish`);
    assert.deepEqual(round.result, entry.result, `seed ${entry.seed}: the replayed round ended differently`);
  }
  replayed = { mismatches, failures, fallbacks: botDiagnostics.fallbacks - fallbacksBefore, coverage };
  return replayed;
}

test("the TypeScript bots choose exactly what the Swift bots choose (bots.json)", () => {
  const { mismatches, failures, fallbacks, coverage } = replay();
  if (mismatches > 0) {
    assert.fail(
      `bots.json: ${mismatches} of ${2 * coverage.decisions} bot choices differ from the Swift bots ` +
        `(first ${failures.length}):\n${failures.join("\n")}`,
    );
  }
  // The Swift bots never need their rules-built safety net in these rounds; neither may the port.
  assert.equal(fallbacks, 0, "the bots fell back to a rules-built play");
});

test("bots.json covers every kind of decision", () => {
  const c = replay().coverage;
  const report = JSON.stringify(c);
  assert.ok(c.rounds.online >= 500 && c.rounds.offline >= 150, report);
  assert.ok(c.rounds.noTrump >= 150, `few no-trump rounds: ${report}`);
  assert.ok(c.bids >= 2000 && c.dealingLooks >= 3000, report);
  assert.ok(c.declared.standard >= 800 && c.declared.beginner >= 600, `few declarations: ${report}`);
  assert.ok(c.noTrumpDeclared >= 50 && c.overridden >= 30, `few no-trump declarations or overrides: ${report}`);
  assert.ok(c.buries >= 650, report);
  assert.ok(c.leads >= 5000 && c.follows >= 15000, report);
  assert.ok(c.throws >= 500 && c.tractorLeads >= 200, `few throws or tractor leads: ${report}`);
  assert.ok(c.tractorFollows >= 300 && c.ruffs >= 700, `few tractor follows or ruffs: ${report}`);
  // Rare at random, so ShengjiVectors keeps extra rounds that hold them (BotVectors `ruffRounds`).
  assert.ok(c.throwRuffs >= 30 && c.shortSuitRuffs >= 100, `few ruffs of throws or of short suits: ${report}`);
  assert.ok(c.seats.every((n) => n >= 5000), `every seat decides: ${report}`);
});
