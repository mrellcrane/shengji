// The wire view one seat receives: a port of ShengjiCore/Sources/ShengjiCore/Engine/SeatView.swift
// (`Round.seatView(for:players:game:)` and `RoundSummary.rotated(by:target:)`), plus the online
// bidding state, which has no Swift producer (Swift only decodes it).
//
// Seats are viewer-relative: the viewer is seat 0, 1 their right (next to play), 2 their partner,
// 3 their left; team 0 is the viewer's team. Bigger tables go on round the same way: with 6 or 8
// players `players` and `handCounts` have 6 or 8 entries, the viewer's team is every even seat and
// the opponents every odd one. The JSON form of `SeatView` is exactly the Swift `SeatView` Codable
// (test/vectors/views.json proves it for every seat of 4, 6 and 8-player tables); optionals are
// written as null where Swift leaves the key out, which Swift's decoder reads the same way.
//
// Privacy (DESIGN.md): a view never contains another hand, the undealt cards, or a kitty the viewer
// may not see (the dealer sees it while burying and after burying it; everyone once the round is
// finished).

import { tableSize } from "./cards.ts";
import type { Card, Rank } from "./cards.ts";
import { normalizeSeat } from "./rules.ts";
import { availableBids, roundPlayers, turn as playTurn } from "./round.ts";
import type { Declaration, Round, RoundResult, TrickRecord } from "./round.ts";
import type { Play } from "./rules.ts";
import { explainRound } from "./game.ts";
import type { GameState, RoundSummary } from "./game.ts";
import type { Trump } from "./trump.ts";

export type SeatViewPhase = "dealing" | "bidding" | "burying" | "playing" | "finished";

/** Swift `SeatView.Player`. */
export interface SeatPlayer {
  name: string;
  isBot: boolean;
  /** Online user id (null for bots). */
  userID: string | null;
}

/** Swift `SeatView.Bid`: a declaration, or a pass when `declaration` is null. */
export interface SeatBid {
  player: number;
  declaration: Declaration | null;
}

/** Swift `SeatView.Bidding`. */
export interface SeatBidding {
  /** Whose turn it is to declare or pass. */
  turn: number | null;
  history: SeatBid[];
  /** Declarations the viewer could make right now (empty unless it is the viewer's turn). */
  available: Declaration[];
}

/** Swift `SeatView`, field for field. */
export interface SeatView {
  /** Players in seat order (4, 6 or 8); index 0 is the viewer. */
  players: SeatPlayer[];
  /** Levels as [viewer's team, other team]. */
  teamLevels: Rank[];
  targetRank: Rank;
  /** 1-based round number within the game. */
  roundNumber: number;
  phase: SeatViewPhase;
  trump: Trump;
  trumpFromKitty: Card | null;
  dealer: number | null;
  /** The viewer's own cards (engine order, not sorted). */
  hand: Card[];
  handCounts: number[];
  declaration: Declaration | null;
  declarationHistory: Declaration[];
  bidding: SeatBidding | null;
  /** Visible only to the dealer once they hold it, and to everyone when the round is finished. */
  kitty: Card[] | null;
  currentTrick: Play[];
  leader: number;
  /** Whose turn it is to play or bury (null when nobody needs to, and while bidding). */
  turn: number | null;
  tricks: TrickRecord[];
  defenderTrickPoints: number;
  result: RoundResult | null;
  lastRoundSummary: RoundSummary | null;
  gameWinnerTeam: number | null;
}

/** `seat` as seen from `viewer` at a table of `players` (Swift `seat(_:)` in `seatView`). */
export function relativeSeat(seat: number, viewer: number, players = 4): number {
  return normalizeSeat(seat - viewer, players);
}

/** The absolute seat of `relative` as seen from `viewer` (inverse of `relativeSeat`). */
export function absoluteSeat(relative: number, viewer: number, players = 4): number {
  return normalizeSeat(relative + viewer, players);
}

/** Players and decks at the table a view shows (from its number of seats: 4, 6 or 8; Swift `SeatView.table`). */
export function viewTable(view: SeatView): { players: number; decks: number } {
  return tableSize(view.handCounts.length === 0 ? view.players.length : view.handCounts.length);
}

/** Team `team` as seen from `viewer` (0 = the viewer's team). */
export function relativeTeam(team: number, viewer: number): number {
  return (team + viewer) % 2;
}


function rotateTeams<T>(values: readonly T[], viewer: number): T[] {
  if (values.length !== 2) return values.slice();
  const out = values.slice();
  out[relativeTeam(0, viewer)] = values[0];
  out[relativeTeam(1, viewer)] = values[1];
  return out;
}

function rotateDeclaration(d: Declaration, viewer: number, players: number): Declaration {
  return { player: relativeSeat(d.player, viewer, players), cards: d.cards.slice(), suit: d.suit, strength: d.strength };
}

function rotatePlay(p: Play, viewer: number, players: number): Play {
  return { player: relativeSeat(p.player, viewer, players), cards: p.cards.slice() };
}

function rotateTrick(t: TrickRecord, viewer: number, players: number): TrickRecord {
  return {
    plays: t.plays.map((p) => rotatePlay(p, viewer, players)),
    winner: relativeSeat(t.winner, viewer, players),
    points: t.points,
  };
}

function rotateResult(r: RoundResult, viewer: number, players: number): RoundResult {
  return {
    dealer: relativeSeat(r.dealer, viewer, players),
    declarerTeam: relativeTeam(r.declarerTeam, viewer),
    trump: { rank: r.trump.rank, suit: r.trump.suit },
    trickPoints: r.trickPoints,
    kittyPoints: r.kittyPoints,
    kittyMultiplier: r.kittyMultiplier,
    defenderPoints: r.defenderPoints,
    outcome: { declarersHold: r.outcome.declarersHold, levels: r.outcome.levels, summary: r.outcome.summary },
    kitty: r.kitty.slice(),
    lastTrickWinner: relativeSeat(r.lastTrickWinner, viewer, players),
  };
}

function copySummary(s: RoundSummary): RoundSummary {
  return structuredClone(s);
}

/**
 * The same summary from `viewer`'s point of view at a table of `players`: seats and teams rotated,
 * explanation rewritten so the viewer's team is "Your team". Swift
 * `RoundSummary.rotated(by:target:players:)`.
 */
export function rotateSummary(summary: RoundSummary, viewer: number, target: Rank, players = 4): RoundSummary {
  const n = tableSize(players).players;
  const v = normalizeSeat(viewer, n);
  if (v === 0) return copySummary(summary);
  const result = rotateResult(summary.result, v, n);
  const after = rotateTeams(summary.levelsAfter, v);
  const benefiting = result.outcome.declarersHold ? result.declarerTeam : 1 - result.declarerTeam;
  const next = relativeSeat(summary.nextDealer, v, n);
  const gameWinner = summary.gameWinner === null ? null : relativeTeam(summary.gameWinner, v);
  const explanation = explainRound({
    result,
    team: benefiting,
    nominal: result.outcome.levels,
    gained: summary.levelsGained,
    newLevel: after[benefiting],
    gameWinner,
    target,
    nextDealer: next,
    nextLevel: after[next % 2],
    players: n,
  });
  return {
    result,
    advancingTeam: summary.advancingTeam === null ? null : relativeTeam(summary.advancingTeam, v),
    levelsGained: summary.levelsGained,
    levelsBefore: rotateTeams(summary.levelsBefore, v),
    levelsAfter: after,
    nextDealer: next,
    gameWinner,
    explanation,
  };
}

/** Structural equality of JSON-like values (Swift `==` on value types). */
function sameValue(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((item, i) => sameValue(item, b[i]));
  }
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return false;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  if (ka.length !== kb.length) return false;
  return ka.every((k) => sameValue((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k]));
}

/** True while online turn-based bidding is open. */
export function isBiddingOpen(round: Round): boolean {
  return round.phase === "dealing" && round.bidding !== null && round.bidding.turn !== null;
}

/** The phase a view shows: "bidding" while online bidding is open, otherwise the round's phase. */
export function viewPhase(round: Round): SeatViewPhase {
  return isBiddingOpen(round) ? "bidding" : round.phase;
}

/** True if `viewer` may see the kitty now (Swift `kittyVisible`). */
export function kittyVisibleTo(round: Round, viewer: number): boolean {
  switch (round.phase) {
    case "dealing":
      return false;
    case "burying":
    case "playing":
      return round.dealer === viewer;
    case "finished":
      return true;
  }
}

/** 1-based number of the round in progress (or just finished). */
export function roundNumber(game: GameState, round: Round): number {
  const last = game.history.length > 0 ? game.history[game.history.length - 1] : null;
  const recorded = round.phase === "finished" && last !== null && sameValue(last.result, round.result);
  return game.roundsPlayed + (recorded ? 0 : 1);
}

/**
 * The view of absolute seat `viewer`, rotated so the viewer is seat 0. `players` are in absolute
 * seat order. Swift `Round.seatView(for:players:game:)`, plus `bidding` while online bidding is
 * open. Shares no objects with its inputs.
 */
export function toSeatView(game: GameState, round: Round, viewer: number, players: readonly SeatPlayer[]): SeatView {
  const n = roundPlayers(round);
  const v = normalizeSeat(viewer, n);
  const seat = (s: number): number => relativeSeat(s, v, n);
  const seats = Array.from({ length: n }, (_, i) => i);
  const rotatedPlayers = seats.map((i) => {
    const p = players[absoluteSeat(i, v, n) % Math.max(players.length, 1)];
    return { name: p.name, isBot: p.isBot, userID: p.userID };
  });
  const hand = (s: number): Card[] => (s >= 0 && s < round.hands.length ? round.hands[s] : []);
  const playing = playTurn(round);
  let bidding: SeatBidding | null = null;
  if (isBiddingOpen(round) && round.bidding !== null) {
    const open = round.bidding;
    bidding = {
      turn: open.turn === null ? null : seat(open.turn),
      history: open.bids.map((b) => ({
        player: seat(b.seat),
        declaration: b.declaration === null ? null : rotateDeclaration(b.declaration, v, n),
      })),
      available: availableBids(round, v).map((d) => rotateDeclaration(d, v, n)),
    };
  }
  const last = game.history.length > 0 ? game.history[game.history.length - 1] : null;

  return {
    players: rotatedPlayers,
    teamLevels: rotateTeams(game.levels, v),
    targetRank: game.settings.targetRank,
    roundNumber: roundNumber(game, round),
    phase: viewPhase(round),
    trump: { rank: round.trump.rank, suit: round.trump.suit },
    trumpFromKitty: round.trumpFromKitty,
    dealer: round.dealer === null ? null : seat(round.dealer),
    hand: hand(v).slice(),
    handCounts: seats.map((i) => hand(absoluteSeat(i, v, n)).length),
    declaration: round.declaration === null ? null : rotateDeclaration(round.declaration, v, n),
    declarationHistory: round.declarationHistory.map((d) => rotateDeclaration(d, v, n)),
    bidding,
    kitty: kittyVisibleTo(round, v) ? round.kitty.slice() : null,
    currentTrick: round.currentTrick.map((p) => rotatePlay(p, v, n)),
    leader: seat(round.leader),
    turn:
      playing !== null
        ? seat(playing)
        : round.phase === "burying" && round.dealer !== null
          ? seat(round.dealer)
          : null,
    tricks: round.tricks.map((t) => rotateTrick(t, v, n)),
    defenderTrickPoints: round.defenderTrickPoints,
    result: round.result === null ? null : rotateResult(round.result, v, n),
    lastRoundSummary: last === null ? null : rotateSummary(last, v, game.settings.targetRank, n),
    gameWinnerTeam: game.winner === null ? null : relativeTeam(game.winner, v),
  };
}
