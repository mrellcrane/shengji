// The wire view one seat receives: a port of ShengjiCore/Sources/ShengjiCore/Engine/SeatView.swift
// (`Round.seatView(for:players:game:)` and `RoundSummary.rotated(by:target:)`), plus the online
// bidding state, which has no Swift producer (Swift only decodes it).
//
// Seats are viewer-relative: the viewer is seat 0, 1 their right (next to play), 2 their partner,
// 3 their left; team 0 is the viewer's team. Bigger tables go on round the same way: with 6 or 8
// players `players` and `handCounts` have 6 or 8 entries, the viewer's team is every even seat and
// the opponents every odd one. With an odd number of players (Finding Friends) there are no fixed
// teams: the dealer's side is the dealer plus the friends found so far (`friendCalls`), levels are
// per seat (the viewer's first), and team 0 means the viewer's side. The JSON form of `SeatView` is
// exactly the Swift `SeatView` Codable (test/vectors/views.json proves it for every seat of tables
// of 4 to 9); optionals are written as null where Swift leaves the key out, which Swift's decoder
// reads the same way.
//
// Privacy (DESIGN.md): a view never contains another hand, the undealt cards, or a kitty the viewer
// may not see (the dealer sees it while burying and after burying it; everyone once the round is
// finished). Friend calls are public once the dealer has buried (the friends found are public too:
// everyone saw the called card played).

import { tableFindsFriends, tableSize } from "./cards.ts";
import type { Card, Rank } from "./cards.ts";
import { rotateFriendCall } from "./friends.ts";
import type { FriendCall } from "./friends.ts";
import { normalizeSeat, teamOf } from "./rules.ts";
import {
  availableBids,
  friendCallsOf,
  resultTeamRotation,
  rotateResult,
  roundFindsFriends,
  roundPlayers,
  turn as playTurn,
} from "./round.ts";
import type { Declaration, Round, RoundResult, TrickRecord } from "./round.ts";
import type { Play } from "./rules.ts";
import { rotateSummary } from "./game.ts";
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
  /** Players in seat order (4 to 9); index 0 is the viewer. */
  players: SeatPlayer[];
  /** Levels as [viewer's team, other team]. With Finding Friends one level per seat, the viewer's first. */
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
  /** Viewer-relative winning team when the game is over (with Finding Friends 0 if the viewer won). */
  gameWinnerTeam: number | null;
  /**
   * Finding Friends: the friends the dealer called (null before burying and at tables of fixed
   * teams), each with the seat (viewer-relative) that played the called card once it has been played.
   */
  friendCalls: FriendCall[] | null;
}

/** `seat` as seen from `viewer` at a table of `players` (Swift `seat(_:)` in `seatView`). */
export function relativeSeat(seat: number, viewer: number, players = 4): number {
  return normalizeSeat(seat - viewer, players);
}

/** The absolute seat of `relative` as seen from `viewer` (inverse of `relativeSeat`). */
export function absoluteSeat(relative: number, viewer: number, players = 4): number {
  return normalizeSeat(relative + viewer, players);
}

/** Players and decks at the table a view shows (from its number of seats: 4 to 9; Swift `SeatView.table`). */
export function viewTable(view: SeatView): { players: number; decks: number } {
  return tableSize(view.handCounts.length === 0 ? view.players.length : view.handCounts.length);
}

/** Team `team` as seen from `viewer` (0 = the viewer's team) at a table of fixed teams. */
export function relativeTeam(team: number, viewer: number): number {
  return (team + viewer) % 2;
}

// MARK: Finding Friends from a view (Swift `SeatView` conveniences)

/** True at a table with an odd number of players: no fixed teams, the dealer calls friends. */
export function viewFindsFriends(view: SeatView): boolean {
  return tableFindsFriends(viewTable(view));
}

/** True if `seat` is known to be on the dealer's side (with Finding Friends: the dealer or a friend found). */
export function viewIsDeclarer(view: SeatView, seat: number): boolean {
  if (view.dealer === null) return false;
  if (viewFindsFriends(view)) return seat === view.dealer || (view.friendCalls ?? []).some((call) => call.friend === seat);
  return teamOf(seat) === teamOf(view.dealer);
}

/**
 * True if `seat` is against the dealer's side. With Finding Friends a hidden friend counts as a
 * defender until they play the called card.
 */
export function viewIsDefender(view: SeatView, seat: number): boolean {
  return view.dealer !== null && !viewIsDeclarer(view, seat);
}

/**
 * Team of the dealer (viewer-relative), null before the dealer is known. With Finding Friends: 0
 * while the viewer is the dealer or a friend found so far, else 1.
 */
export function viewDeclarerTeam(view: SeatView): number | null {
  if (view.dealer === null) return null;
  return viewFindsFriends(view) ? (viewIsDeclarer(view, 0) ? 0 : 1) : teamOf(view.dealer);
}

/**
 * The dealer's side as far as anyone can see, the dealer first and then in play order: the dealer's
 * team, or with Finding Friends the dealer and the friends found so far. Empty before the dealer is
 * known.
 */
export function viewDeclarers(view: SeatView): number[] {
  const dealer = view.dealer;
  if (dealer === null) return [];
  const n = viewTable(view).players;
  const seats = viewFindsFriends(view)
    ? [dealer, ...(view.friendCalls ?? []).flatMap((call) => (call.friend === null ? [] : [call.friend]))]
    : Array.from({ length: n }, (_, seat) => seat).filter((seat) => teamOf(seat) === teamOf(dealer));
  return [...new Set(seats)].sort((a, b) => normalizeSeat(a - dealer, n) - normalizeSeat(b - dealer, n));
}

/** Friends called but not played yet. */
export function viewFriendsToFind(view: SeatView): number {
  return (view.friendCalls ?? []).filter((call) => call.friend === null).length;
}

/** Every card played this round: finished tricks, then the trick in progress. */
export function viewPlayedCards(view: SeatView): Card[] {
  const cards: Card[] = [];
  for (const trick of view.tricks) for (const play of trick.plays) cards.push(...play.cards);
  for (const play of view.currentTrick) cards.push(...play.cards);
  return cards;
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

/** Levels as the viewer sees them: [their team, other team], or with Finding Friends one per seat, theirs first. */
function viewLevels(game: GameState, round: Round, viewer: number): Rank[] {
  const n = roundPlayers(round);
  if (!roundFindsFriends(round)) return rotateTeams(game.levels, viewer);
  return Array.from({ length: n }, (_, i) => {
    const index = (i + viewer) % n;
    return index < game.levels.length ? game.levels[index] : round.trumpRank;
  });
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
  const winnerTeam =
    game.winner === null ? null : last === null ? game.winner : resultTeamRotation(last.result, v, n)(game.winner);
  // Friend calls are made when burying: shown from then on (seats rotated), never while dealing or burying.
  const friendCalls =
    roundFindsFriends(round) && round.phase !== "dealing" && round.phase !== "burying"
      ? friendCallsOf(round).map((call) => rotateFriendCall(call, v, n))
      : null;

  return {
    players: rotatedPlayers,
    teamLevels: viewLevels(game, round, v),
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
    gameWinnerTeam: winnerTeam,
    friendCalls,
  };
}
