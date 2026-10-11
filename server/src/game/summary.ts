// Game summaries (docs/online-protocol.md, GameSummary) and the public event log line.
//
// A GameRoom publishes a `GameSnapshot` after every change: everything a game list shows, in
// absolute seats and built only from public information (never a hand or the kitty; the friends a
// dealer calls are public once buried). The Hub stores it in its games index, so lists need no call
// to each GameRoom; both turn it into a viewer-relative `GameSummary` with `summarize`.
//
// Tables of 5, 7 or 9 (Finding Friends) have no fixed teams: levels are per seat, a round's line
// names the dealer's side, and the winners are the seats of the dealer's side that held the deal.

import { cardDescription, rankLabel, suitSymbol } from "../engine/cards.ts";
import type { Card, Rank } from "../engine/cards.ts";
import { friendCallList } from "../engine/friends.ts";
import type { FriendCall } from "../engine/friends.ts";
import { levelPhrase } from "../engine/scoring.ts";
import { declarationDetail } from "../engine/round.ts";
import type { Declaration } from "../engine/round.ts";
import { relativeSeat, relativeTeam } from "../engine/seatview.ts";
import type { SeatPlayer } from "../engine/seatview.ts";

export type GameStatus = "active" | "finished";
export type SummaryPhase = "bidding" | "burying" | "playing" | "finished";

/** Something that happened at the table, in absolute seats; only public facts. */
export type GameEvent =
  | { type: "started"; seat: number }
  | { type: "bid"; seat: number; declaration: Declaration }
  | { type: "pass"; seat: number }
  /** Finding Friends: `calls` are the friends the dealer called (public); absent at tables of fixed teams. */
  | { type: "bury"; seat: number; calls?: FriendCall[] }
  | { type: "play"; seat: number; cards: Card[]; lead: boolean; failedThrow: boolean }
  | {
      type: "round";
      /** 1-based number of the round that ended. */
      round: number;
      /** Team that kept or took over the deal (with Finding Friends: 0 for seat 0's side, as `RoundSummary`). */
      team: number;
      tookOver: boolean;
      /** Levels gained (with Finding Friends, the most any one player gained). */
      levelsGained: number;
      /** The team's new level (with Finding Friends, the highest level a player who went up reached). */
      newLevel: Rank;
      /** The winning team when this round ended the game (with Finding Friends: see `side`). */
      gameWinner: number | null;
      /**
       * Finding Friends only: the dealer's side when the round ended (absolute seats, the dealer first
       * and then in play order). The defenders are everyone else.
       */
      side?: number[];
    };

export interface GameSnapshot {
  id: string;
  clubId: string;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
  status: GameStatus;
  version: number;
  /** Absolute seat order (4 to 9 seats). */
  players: SeatPlayer[];
  /** Levels per absolute team, or with Finding Friends (5, 7 or 9 seats) per absolute seat. */
  levels: Rank[];
  targetRank: Rank;
  roundNumber: number;
  phase: SummaryPhase;
  /** Absolute seat that must act (bid, bury or play), or null. */
  turn: number | null;
  /** Absolute winning team, or null (with Finding Friends 0 if seat 0 won; see `winners`). */
  winner: number | null;
  /** The seats that won the game (absolute), or null while it goes on. Absent in older snapshots. */
  winners?: number[] | null;
  lastEvent: GameEvent | null;
}

/** docs/online-protocol.md GameSummary: viewer-relative (index 0 = you). */
export interface GameSummary {
  id: string;
  clubId: string;
  createdAt: string;
  updatedAt: string;
  status: GameStatus;
  players: SeatPlayer[];
  /** [your team, other team]; with Finding Friends (5, 7 or 9 seats) one level per seat, yours first. */
  teamLevels: Rank[];
  targetRank: Rank;
  roundNumber: number;
  phase: SummaryPhase;
  turn: number | null;
  yourTurn: boolean;
  /** 0 when your team (with Finding Friends: your side) won, 1 when the others did, null while the game goes on. */
  winnerTeam: number | null;
  lastEvent: string | null;
  /** The viewer started this game (only they can end it). */
  startedByYou: boolean;
}

/** The seat of `userId` in the snapshot, or null. */
export function seatOfUser(players: readonly SeatPlayer[], userId: string): number | null {
  const index = players.findIndex((p) => !p.isBot && p.userID === userId);
  return index >= 0 ? index : null;
}

function nameOf(players: readonly SeatPlayer[], seat: number, viewer: number | null): string {
  if (viewer !== null && seat === viewer) return "You";
  return players[seat]?.name ?? "Someone";
}

/**
 * "your team", or the team's players by name in seat order: "Mei and Lin" with 4 players, "Mei, Lin
 * and Sam" with 6, four names with 8. A team is every even or every odd seat.
 */
export function teamName(players: readonly SeatPlayer[], team: number, viewer: number | null): string {
  if (viewer !== null && viewer % 2 === team) return "your team";
  const names: string[] = [];
  for (let seat = team; seat < Math.max(players.length, 4); seat += 2) names.push(nameOf(players, seat, null));
  return names.length <= 1 ? (names[0] ?? "Someone") : `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/**
 * Finding Friends: the players of a side by name in the order given (the dealer first), the viewer
 * as "you": "Mei, Lin and Sam", "you and Mei".
 */
export function sideNames(players: readonly SeatPlayer[], seats: readonly number[], viewer: number | null): string {
  const names = seats.map((seat) => (viewer !== null && seat === viewer ? "you" : nameOf(players, seat, null)));
  if (names.length <= 1) return names[0] ?? "Someone";
  return `${names.slice(0, -1).join(", ")} and ${names[names.length - 1]}`;
}

/** "♥ (pair of 2♥)", "no trump (three small jokers)". */
function declarationText(d: Declaration): string {
  const what = d.suit === null ? "no trump" : suitSymbol(d.suit);
  return d.strength >= 1 ? `${what} (${declarationDetail(d)})` : what;
}

/**
 * One line about the event from `viewer`'s side ("You led K♠ K♠", "Mei passed",
 * "Round 3: your team took over the deal"). `viewer` null: names only (someone not seated).
 */
export function eventText(event: GameEvent, players: readonly SeatPlayer[], viewer: number | null): string {
  switch (event.type) {
    case "started":
      return `${nameOf(players, event.seat, viewer)} started the game`;
    case "bid":
      return `${nameOf(players, event.seat, viewer)} declared ${declarationText(event.declaration)}`;
    case "pass":
      return `${nameOf(players, event.seat, viewer)} passed`;
    case "bury": {
      const who = nameOf(players, event.seat, viewer);
      const calls = event.calls ?? [];
      return calls.length === 0 ? `${who} buried the kitty` : `${who} buried the kitty and called ${friendCallList(calls)}`;
    }
    case "play": {
      const who = nameOf(players, event.seat, viewer);
      const cards = event.cards.map(cardDescription).join(" ");
      if (event.failedThrow) return `${who} tried a throw that failed and led ${cards}`;
      return `${who} ${event.lead ? "led" : "played"} ${cards}`;
    }
    case "round": {
      const prefix = `Round ${event.round}: `;
      if (event.side !== undefined) {
        // Finding Friends: the dealer's side by name, or the defenders.
        const up = event.levelsGained > 0 ? ` and went up ${levelPhrase(event.levelsGained)}` : "";
        const side = sideNames(players, event.side, viewer);
        if (event.gameWinner !== null) return `${prefix}${side} won the game`;
        return event.tookOver ? `${prefix}the defenders took over the deal${up}` : `${prefix}${side} kept the deal${up}`;
      }
      if (event.gameWinner !== null) return `${prefix}${teamName(players, event.gameWinner, viewer)} won the game`;
      const team = teamName(players, event.team, viewer);
      const deal = event.tookOver ? "took over the deal" : "kept the deal";
      const up = event.levelsGained > 0 ? ` and went up ${levelPhrase(event.levelsGained)} to ${rankLabel(event.newLevel)}` : "";
      return `${prefix}${team} ${deal}${up}`;
    }
  }
}

/**
 * The summary seen from absolute seat `viewer`; null for a club member who is not seated (then
 * seat order is absolute, nobody is "You", and yourTurn is false).
 */
export function summarize(snapshot: GameSnapshot, viewer: number | null): GameSummary {
  const v = viewer ?? 0;
  const n = snapshot.players.length;
  const players = snapshot.players.map((_, i) => {
    const p = snapshot.players[(i + v) % n];
    return { name: p.name, isBot: p.isBot, userID: p.userID };
  });
  // Finding Friends (an odd number of seats): one level per seat, the viewer's first.
  const perSeat = n % 2 === 1 && snapshot.levels.length === n;
  const teamLevels = perSeat
    ? snapshot.levels.map((_, i) => snapshot.levels[(i + v) % n])
    : snapshot.levels.length === 2
      ? [snapshot.levels[v % 2], snapshot.levels[(v + 1) % 2]]
      : snapshot.levels.slice();
  let winnerTeam: number | null = null;
  if (snapshot.winner !== null) {
    const winners = snapshot.winners ?? null;
    winnerTeam = n % 2 === 1 && winners !== null ? (winners.includes(v) ? 0 : 1) : relativeTeam(snapshot.winner, v);
  }
  return {
    id: snapshot.id,
    clubId: snapshot.clubId,
    createdAt: snapshot.createdAt,
    updatedAt: snapshot.updatedAt,
    status: snapshot.status,
    players,
    teamLevels,
    targetRank: snapshot.targetRank,
    roundNumber: snapshot.roundNumber,
    phase: snapshot.phase,
    turn: snapshot.turn === null ? null : relativeSeat(snapshot.turn, v, n),
    yourTurn: viewer !== null && snapshot.status === "active" && snapshot.turn === viewer,
    winnerTeam,
    lastEvent: snapshot.lastEvent === null ? null : eventText(snapshot.lastEvent, snapshot.players, viewer),
    startedByYou: viewer !== null && !snapshot.players[viewer].isBot && snapshot.players[viewer].userID === snapshot.createdBy,
  };
}

/** Lists: your turn first, then other active games, newest first; finished games after. */
export function compareSummaries(a: GameSummary, b: GameSummary): number {
  const rank = (s: GameSummary): number => (s.status === "finished" ? 2 : s.yourTurn ? 0 : 1);
  return rank(a) - rank(b) || (a.updatedAt < b.updatedAt ? 1 : a.updatedAt > b.updatedAt ? -1 : 0) || (a.id < b.id ? -1 : 1);
}
