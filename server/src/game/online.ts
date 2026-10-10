// One online game: the authoritative state a GameRoom stores, and everything that changes it.
// Plain data and functions (no storage, no network), so it is tested directly in Node.
//
// Flow (docs/online-protocol.md): the first round deals at creation with bidding at the
// creator's seat. Each accepted human action is followed by bot turns until a human must act.
// When a round ends it is recorded and the next one is dealt at once (fresh crypto shuffle,
// bidding at the next dealer); when a team wins, the game is finished and the last round stays
// on the table. Bots decide from their own seat's view with the app's bot logic (src/bots).

import type { Card, Rank } from "../engine/cards.ts";
import { newGame, recordRound, startOnlineRound } from "../engine/game.ts";
import type { GameState } from "../engine/game.ts";
import { bid, biddingTurn, bury, play, roundErrorExplanation, turn as playTurn } from "../engine/round.ts";
import type { Declaration, PlayOutcome, Round, RoundError } from "../engine/round.ts";
import { roundNumber, toSeatView, viewPhase } from "../engine/seatview.ts";
import type { SeatPlayer, SeatView } from "../engine/seatview.ts";
import { sortCards } from "../engine/trump.ts";
import { chooseBotAction, safeActions } from "./bots.ts";
import type { BotLevel } from "./bots.ts";
import { eventText, summarize, teamName } from "./summary.ts";
import type { GameEvent, GameSnapshot, GameSummary, SummaryPhase } from "./summary.ts";

/** Who sits in an absolute seat. */
export interface SeatAssignment {
  /** The player's user id, or null for a bot. */
  userId: string | null;
  bot: BotLevel | null;
  /** Display name (users: their name when the game was made, kept current by renames). */
  name: string;
}

export interface OnlineGame {
  id: string;
  clubId: string;
  clubName: string;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
  status: "active" | "finished";
  seats: SeatAssignment[];
  creatorSeat: number;
  game: GameState;
  round: Round;
  /** Increases with every change (each action, bot turn, deal and rename of a player). */
  version: number;
  lastEvent: GameEvent | null;
  /** Unix ms of the last nudge (one per 10 minutes per game). */
  lastNudgeAt: number | null;
}

/** An action in absolute terms (a bid's declaration already belongs to the acting seat). */
export type SeatAction =
  | { type: "bid"; declaration: Declaration }
  | { type: "pass" }
  | { type: "bury"; cards: Card[] }
  | { type: "play"; cards: Card[] };

/** One row of the action log (server-side only, never sent to players). */
export interface LogEntry {
  version: number;
  seat: number | null;
  kind: "create" | "deal" | "action" | "bot" | "rename";
  data: unknown;
}

export interface Notification {
  userId: string;
  gameId: string;
  title: string;
  body: string;
}

export interface GameDeps {
  /** A full 108-card deck in a fresh random order. */
  deck(): Card[];
  now(): Date;
}

/** Bot turns run per request at most (a whole round is about 110); stops a runaway loop. */
export const MAX_AUTOMATIC_STEPS = 600;

const BOT_NAMES = ["Panda Bot", "Tiger Bot", "Crane Bot", "Dragon Bot"];

export function botName(seat: number): string {
  return BOT_NAMES[seat] ?? "Bot";
}

/** The seat that must act now (bid, bury or play), or null. */
export function actingSeat(round: Round): number | null {
  const bidder = biddingTurn(round);
  if (bidder !== null) return bidder;
  if (round.phase === "burying") return round.dealer;
  return playTurn(round);
}

export function playersOf(state: OnlineGame): SeatPlayer[] {
  return state.seats.map((s) => ({ name: s.name, isBot: s.userId === null, userID: s.userId }));
}

export function seatOf(state: OnlineGame, userId: string): number | null {
  const index = state.seats.findIndex((s) => s.userId === userId);
  return index >= 0 ? index : null;
}

export interface NewGameInput {
  id: string;
  clubId: string;
  clubName: string;
  createdBy: string;
  seats: SeatAssignment[];
  targetRank: Rank;
}

/** A new game with its first round dealt and bidding open at the creator's seat. */
export function newOnlineGame(
  input: NewGameInput,
  deps: GameDeps,
): { state: OnlineGame; log: LogEntry[]; events: GameEvent[] } {
  const creatorSeat = input.seats.findIndex((s) => s.userId === input.createdBy);
  if (creatorSeat < 0) throw new RangeError("the creator must hold a seat");
  const game = newGame({ startRank: 2, targetRank: input.targetRank });
  const deck = deps.deck();
  const round = startOnlineRound(game, deck, creatorSeat);
  const at = deps.now().toISOString();
  const state: OnlineGame = {
    id: input.id,
    clubId: input.clubId,
    clubName: input.clubName,
    createdBy: input.createdBy,
    createdAt: at,
    updatedAt: at,
    status: "active",
    seats: input.seats.map((s) => ({ ...s })),
    creatorSeat,
    game,
    round,
    version: 1,
    lastEvent: { type: "started", seat: creatorSeat },
    lastNudgeAt: null,
  };
  const log: LogEntry[] = [
    { version: 1, seat: creatorSeat, kind: "create", data: { seats: state.seats, targetRank: input.targetRank, deck } },
  ];
  const events: GameEvent[] = [{ type: "started", seat: creatorSeat }];
  runAutomatic(state, deps, events, log);
  state.lastEvent = headline(events) ?? state.lastEvent;
  return { state, log, events };
}

function applySeatAction(
  round: Round,
  seat: number,
  action: SeatAction,
): { ok: true; outcome: PlayOutcome; event: GameEvent } | { ok: false; error: RoundError } {
  switch (action.type) {
    case "bid": {
      const error = bid(round, seat, action.declaration);
      if (error !== null) return { ok: false, error };
      const declared = round.declarationHistory[round.declarationHistory.length - 1];
      return { ok: true, outcome: { type: "played" }, event: { type: "bid", seat, declaration: structuredClone(declared) } };
    }
    case "pass": {
      const error = bid(round, seat, "pass");
      if (error !== null) return { ok: false, error };
      return { ok: true, outcome: { type: "played" }, event: { type: "pass", seat } };
    }
    case "bury": {
      const error = bury(round, action.cards, seat);
      if (error !== null) return { ok: false, error };
      return { ok: true, outcome: { type: "played" }, event: { type: "bury", seat } };
    }
    case "play": {
      const lead = round.currentTrick.length === 0;
      const trump = { rank: round.trump.rank, suit: round.trump.suit };
      const result = play(round, action.cards, seat);
      if (!result.ok) return { ok: false, error: result.error };
      const played =
        result.outcome.type === "throwFailed" ? result.outcome.forced : action.cards.slice();
      return {
        ok: true,
        outcome: result.outcome,
        event: {
          type: "play",
          seat,
          cards: sortCards(trump, played),
          lead,
          failedThrow: result.outcome.type === "throwFailed",
        },
      };
    }
  }
}

/**
 * What the bot at absolute `seat` chooses, deciding from that seat's view (the one the server sends
 * the seat) with the app's bot logic. The action in absolute terms, or null.
 */
export function botChoice(state: OnlineGame, seat: number, level: BotLevel): SeatAction | null {
  const action = chooseBotAction(viewOf(state, seat), level);
  if (action?.type !== "bid") return action;
  return { type: "bid", declaration: { ...action.declaration, cards: action.declaration.cards.slice(), player: seat } };
}

/** Where `applyBotTurn` reports a refused bot move (Workers observability keeps console.error lines). */
export type BotReport = (message: string) => void;

const reportError: BotReport = (message) => console.error(message);

function describeAction(action: SeatAction): string {
  switch (action.type) {
    case "bid":
      return `a bid of cards ${action.declaration.cards.join(",")}`;
    case "pass":
      return "a pass";
    case "bury":
    case "play":
      return `${action.type} ${action.cards.join(",")}`;
  }
}

/**
 * Applies a bot's `choice` at absolute `seat`. Should the engine refuse it (it never should), or the
 * bot have no move, the first of the rules-built `safeActions` that the engine accepts is made
 * instead, and each such step is reported with `context`. Null when nothing could be applied.
 */
export function applyBotTurn(
  round: Round,
  seat: number,
  choice: SeatAction | null,
  context: string,
  report: BotReport = reportError,
): { action: SeatAction; event: GameEvent } | null {
  if (choice !== null) {
    const result = applySeatAction(round, seat, choice);
    if (result.ok) return { action: choice, event: result.event };
    report(`${context}: the bot at seat ${seat} chose ${describeAction(choice)}, which was refused: ${roundErrorExplanation(result.error)}`);
  } else {
    report(`${context}: the bot at seat ${seat} had no move in phase ${round.phase}`);
  }
  for (const action of safeActions(round, seat)) {
    const result = applySeatAction(round, seat, action);
    if (!result.ok) continue;
    report(`${context}: made the safe move ${describeAction(action)} for seat ${seat} instead`);
    return { action, event: result.event };
  }
  report(`${context}: no safe move was accepted for seat ${seat}; the game waits`);
  return null;
}

/**
 * Bot turns and round changes until a human must act (or the game is over): a finished round is
 * recorded, then either the game ends or the next round is dealt with bidding at the next dealer.
 */
function runAutomatic(state: OnlineGame, deps: GameDeps, events: GameEvent[], log: LogEntry[]): void {
  for (let step = 0; step < MAX_AUTOMATIC_STEPS && state.status === "active"; step++) {
    const round = state.round;
    if (round.phase === "finished" && round.result !== null) {
      const summary = recordRound(state.game, round.result);
      const team = summary.result.outcome.declarersHold ? summary.result.declarerTeam : 1 - summary.result.declarerTeam;
      events.push({
        type: "round",
        round: state.game.roundsPlayed,
        team,
        tookOver: !summary.result.outcome.declarersHold,
        levelsGained: summary.levelsGained,
        newLevel: summary.levelsAfter[team],
        gameWinner: summary.gameWinner,
      });
      if (state.game.winner !== null) {
        state.status = "finished";
        break;
      }
      const deck = deps.deck();
      state.round = startOnlineRound(state.game, deck, state.creatorSeat);
      state.version += 1;
      log.push({ version: state.version, seat: null, kind: "deal", data: { round: state.game.roundsPlayed + 1, deck } });
      continue;
    }
    const seat = actingSeat(round);
    if (seat === null) break;
    const assignment = state.seats[seat];
    if (assignment.userId !== null) break;
    const applied = applyBotTurn(round, seat, botChoice(state, seat, assignment.bot ?? "standard"), `game ${state.id}`);
    if (applied === null) break;
    state.version += 1;
    log.push({ version: state.version, seat, kind: "bot", data: applied.action });
    events.push(applied.event);
  }
}

/** The most useful line for a batch: the last event, but a round result outranks later bids. */
export function headline(events: readonly GameEvent[]): GameEvent | null {
  let pick: GameEvent | null = null;
  for (const event of events) {
    if (pick?.type === "round" && (event.type === "bid" || event.type === "pass" || event.type === "bury")) continue;
    pick = event;
  }
  return pick;
}

export type TurnResult =
  | { ok: true; outcome: PlayOutcome; events: GameEvent[]; log: LogEntry[] }
  | { ok: false; error: RoundError };

/**
 * A human's action at absolute `seat`, then automatic turns. Changes `state` only when the action
 * is accepted (callers pass a copy and keep it only on success anyway).
 */
export function takeTurn(state: OnlineGame, seat: number, action: SeatAction, deps: GameDeps): TurnResult {
  const result = applySeatAction(state.round, seat, action);
  if (!result.ok) return result;
  state.version += 1;
  const log: LogEntry[] = [{ version: state.version, seat, kind: "action", data: action }];
  const events: GameEvent[] = [result.event];
  runAutomatic(state, deps, events, log);
  state.updatedAt = deps.now().toISOString();
  state.lastEvent = headline(events);
  return { ok: true, outcome: result.outcome, events, log };
}

/** Runs automatic turns if a bot is due (repairs a game stopped by the step limit). */
export function resume(state: OnlineGame, deps: GameDeps): { events: GameEvent[]; log: LogEntry[] } {
  const events: GameEvent[] = [];
  const log: LogEntry[] = [];
  runAutomatic(state, deps, events, log);
  if (events.length > 0 || log.length > 0) {
    state.updatedAt = deps.now().toISOString();
    state.lastEvent = headline(events) ?? state.lastEvent;
  }
  return { events, log };
}

// MARK: What players see

export function viewOf(state: OnlineGame, seat: number): SeatView {
  return toSeatView(state.game, state.round, seat, playersOf(state));
}

export function snapshotOf(state: OnlineGame): GameSnapshot {
  const phase = viewPhase(state.round);
  const turnSeat = state.status === "active" ? actingSeat(state.round) : null;
  return {
    id: state.id,
    clubId: state.clubId,
    createdBy: state.createdBy,
    createdAt: state.createdAt,
    updatedAt: state.updatedAt,
    status: state.status,
    version: state.version,
    players: playersOf(state),
    levels: state.game.levels.slice(),
    targetRank: state.game.settings.targetRank,
    roundNumber: roundNumber(state.game, state.round),
    phase: (phase === "dealing" ? "bidding" : phase) as SummaryPhase,
    turn: turnSeat,
    winner: state.game.winner,
    lastEvent: state.lastEvent === null ? null : structuredClone(state.lastEvent),
  };
}

export function summaryOf(state: OnlineGame, seat: number | null): GameSummary {
  return summarize(snapshotOf(state), seat);
}

/** The user whose turn it is (null for a bot's turn, or when nobody must act). */
export function turnUser(state: OnlineGame): string | null {
  if (state.status !== "active") return null;
  const seat = actingSeat(state.round);
  return seat === null ? null : state.seats[seat].userId;
}

// MARK: Notifications

/**
 * Pushes after a batch made by `actorUserId`: game over to everyone else; "your turn" to the
 * person who must act now; "round over" to the other people when a round ended. At most one per
 * person (pushes collapse per game on the phone anyway).
 */
export function batchNotifications(
  state: OnlineGame,
  actorUserId: string | null,
  events: readonly GameEvent[],
  wasActive: boolean,
): Notification[] {
  const out: Notification[] = [];
  const players = playersOf(state);
  const roundEvent = [...events].reverse().find((e) => e.type === "round") ?? null;
  const gameOver = wasActive && state.status === "finished";
  const due = turnUser(state);
  const club = state.clubName;
  state.seats.forEach((seat, index) => {
    if (seat.userId === null || seat.userId === actorUserId) return;
    if (gameOver) {
      const winner = state.game.winner;
      const body =
        winner === index % 2
          ? `Your team won the game in ${club}!`
          : winner === null
            ? `The game in ${club} is over.`
            : `${capitalize(teamName(players, winner, index))} won the game in ${club}.`;
      out.push({ userId: seat.userId, gameId: state.id, title: "Game over", body });
      return;
    }
    if (seat.userId === due && state.lastEvent !== null) {
      const line = eventText(state.lastEvent, players, index);
      const body = state.lastEvent.type === "round" ? `${line}. It's your turn in ${club}.` : `${line} in ${club}.`;
      out.push({ userId: seat.userId, gameId: state.id, title: "Your turn", body });
      return;
    }
    if (roundEvent !== null) {
      out.push({ userId: seat.userId, gameId: state.id, title: club, body: `${eventText(roundEvent, players, index)}.` });
    }
  });
  return out;
}

function capitalize(text: string): string {
  return text.length > 0 ? text[0].toUpperCase() + text.slice(1) : text;
}

/** The reminder for whoever must act, from the person at `fromSeat`. */
export function nudgeNotification(state: OnlineGame, fromSeat: number): Notification | null {
  const due = turnUser(state);
  if (due === null) return null;
  const from = state.seats[fromSeat]?.name ?? "Someone";
  return { userId: due, gameId: state.id, title: "Your turn", body: `${from} is waiting for you in ${state.clubName}.` };
}

/**
 * Puts a new display name on the user's seat. Every view shows it, so it is a change like a move:
 * the version grows (clients keep only newer versions). Returns the log entry, or null if nothing
 * changed.
 */
export function renameSeat(state: OnlineGame, userId: string, name: string): LogEntry | null {
  const seat = seatOf(state, userId);
  if (seat === null || state.seats[seat].name === name) return null;
  state.seats[seat].name = name;
  state.version += 1;
  return { version: state.version, seat, kind: "rename", data: { name } };
}
