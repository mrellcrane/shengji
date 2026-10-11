// A GameRoom's logic over its SQLite storage: one game's authoritative state (a JSON row with its
// version) and the action log. The Durable Object (src/durable/room.ts) only adds RPC, WebSockets
// and the Hub calls (see RoomHost in host.ts).

import { roundErrorExplanation } from "../engine/round.ts";
import type { Card, Rank } from "../engine/cards.ts";
import { relativeSeat } from "../engine/seatview.ts";
import type { SeatView } from "../engine/seatview.ts";
import { fail, NOT_FOUND_GAME, NOT_SEATED, ok } from "../api/result.ts";
import type { Result } from "../api/result.ts";
import {
  actingSeat,
  batchNotifications,
  cardCountOf,
  newOnlineGame,
  nudgeNotification,
  renameSeat,
  resume,
  seatOf,
  snapshotOf,
  summaryOf,
  takeTurn,
  turnUser,
  viewOf,
} from "../game/online.ts";
import type { GameDeps, LogEntry, Notification, OnlineGame, SeatAction, SeatAssignment } from "../game/online.ts";
import type { GameSnapshot, GameSummary } from "../game/summary.ts";
import { int, text } from "../storage/sql.ts";
import type { Row, Sql } from "../storage/sql.ts";

export const NUDGE_INTERVAL_MS = 10 * 60 * 1000;

/** What a player asks for in POST /v1/games/<id>/actions (viewer-relative; validated shape). */
export interface ActionRequest {
  version: number;
  action: SeatAction;
}

export interface GameResponse {
  game: GameSummary;
  view: SeatView;
  version: number;
}

export interface ActResponse extends GameResponse {
  outcome?: { type: "throwFailed"; forced: Card[]; blocker: number };
}

/** docs/online-protocol.md: the WebSocket message. */
export interface UpdateMessage extends GameResponse {
  type: "update";
}

/** What a change produced: the Hub's new index row and the pushes to send. */
export interface Change {
  snapshot: GameSnapshot;
  notifications: Notification[];
}

export interface CreateRoomInput {
  id: string;
  clubId: string;
  clubName: string;
  createdBy: string;
  seats: SeatAssignment[];
  targetRank: Rank;
}

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS state (
     id INTEGER PRIMARY KEY CHECK (id = 1),
     version INTEGER NOT NULL,
     data TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS log (
     version INTEGER PRIMARY KEY,
     at TEXT NOT NULL,
     seat INTEGER,
     kind TEXT NOT NULL,
     data TEXT NOT NULL
   )`,
];

export class RoomService {
  private readonly sql: Sql;
  private readonly deps: GameDeps;
  /** The parsed state (the Durable Object is single-threaded, so this cache is safe). */
  private cached: OnlineGame | null | undefined = undefined;

  constructor(sql: Sql, deps: GameDeps) {
    this.sql = sql;
    this.deps = deps;
  }

  /** The game, or null if this room holds none (never created, or deleted). */
  load(): OnlineGame | null {
    if (this.cached !== undefined) return this.cached;
    let rows: Row[];
    try {
      rows = this.sql.exec("SELECT version, data FROM state WHERE id = 1");
    } catch {
      // No table yet: tables are only created with a game, so stray ids leave no storage behind.
      rows = [];
    }
    this.cached = rows.length > 0 ? (JSON.parse(text(rows[0], "data")) as OnlineGame) : null;
    if (this.cached !== null && this.cached.version !== int(rows[0], "version")) {
      throw new Error("game state version mismatch");
    }
    return this.cached;
  }

  private save(state: OnlineGame, log: readonly LogEntry[]): void {
    const at = this.deps.now().toISOString();
    this.sql.transaction(() => {
      this.sql.exec(
        "INSERT INTO state (id, version, data) VALUES (1, ?, ?) ON CONFLICT(id) DO UPDATE SET version = excluded.version, data = excluded.data",
        state.version,
        JSON.stringify(state),
      );
      for (const entry of log) {
        this.sql.exec(
          "INSERT INTO log (version, at, seat, kind, data) VALUES (?, ?, ?, ?, ?)",
          entry.version,
          at,
          entry.seat,
          entry.kind,
          JSON.stringify(entry.data),
        );
      }
    });
    this.cached = state;
  }

  create(input: CreateRoomInput): Result<{ game: GameSummary; change: Change }> {
    if (this.load() !== null) return fail(409, "exists", "That game already exists.");
    for (const statement of SCHEMA) this.sql.exec(statement);
    const { state, log } = newOnlineGame(input, this.deps);
    this.save(state, log);
    return ok({
      game: summaryOf(state, state.creatorSeat),
      change: { snapshot: snapshotOf(state), notifications: [] },
    });
  }

  /** Runs bot turns that are due (only after an interrupted batch). Returns the change, if any. */
  repair(): Change | null {
    const state = this.load();
    if (state === null || state.status !== "active") return null;
    const seat = actingSeat(state.round);
    if (seat === null || state.seats[seat].userId !== null) return null;
    const working = structuredClone(state);
    const wasActive = working.status === "active";
    const { events, log } = resume(working, this.deps);
    if (log.length === 0) return null;
    this.save(working, log);
    return { snapshot: snapshotOf(working), notifications: batchNotifications(working, null, events, wasActive) };
  }

  response(state: OnlineGame, seat: number): GameResponse {
    return { game: summaryOf(state, seat), view: viewOf(state, seat), version: state.version };
  }

  /** The live update for absolute `seat`, or null if there is no game. */
  update(seat: number): UpdateMessage | null {
    const state = this.load();
    if (state === null) return null;
    return { type: "update", ...this.response(state, seat) };
  }

  seatOfUser(userId: string): number | null {
    const state = this.load();
    return state === null ? null : seatOf(state, userId);
  }

  read(userId: string): Result<GameResponse> {
    const state = this.load();
    if (state === null) return NOT_FOUND_GAME();
    const seat = seatOf(state, userId);
    if (seat === null) return NOT_SEATED();
    return ok(this.response(state, seat));
  }

  act(userId: string, request: ActionRequest): Result<{ body: ActResponse; change: Change }> {
    const state = this.load();
    if (state === null) return NOT_FOUND_GAME();
    const seat = seatOf(state, userId);
    if (seat === null) return NOT_SEATED();
    // Card ids are checked against this table's decks (0...107 with 4 players, up to 0...269 with 9).
    const count = cardCountOf(state);
    const asked = request.action;
    const cards = asked.type === "bid" ? asked.declaration.cards : asked.type === "pass" ? [] : asked.cards;
    if (cards.some((card) => card >= count)) {
      return fail(400, "bad_request", `cards must be card ids of this table (0 to ${count - 1}).`);
    }
    if (request.version !== state.version) {
      return fail(409, "stale", "The game has moved on. Here is the latest table.", { ...this.response(state, seat) });
    }
    if (state.status !== "active") return fail(403, "not_your_turn", "The game is over.");
    if (actingSeat(state.round) !== seat) return fail(403, "not_your_turn", "Wait for your turn.");

    // Bids arrive viewer-relative: the declaration is the viewer's own (player 0).
    const action: SeatAction =
      request.action.type === "bid"
        ? { type: "bid", declaration: { ...request.action.declaration, player: seat } }
        : request.action;
    const working = structuredClone(state);
    const result = takeTurn(working, seat, action, this.deps);
    if (!result.ok) {
      if (result.error.case === "notYourTurn") return fail(403, "not_your_turn", "Wait for your turn.");
      return fail(400, "illegal", roundErrorExplanation(result.error));
    }
    this.save(working, result.log);
    const body: ActResponse = this.response(working, seat);
    if (result.outcome.type === "throwFailed") {
      body.outcome = {
        type: "throwFailed",
        forced: result.outcome.forced.slice(),
        blocker: relativeSeat(result.outcome.blocker, seat, working.seats.length),
      };
    }
    return ok({
      body,
      change: { snapshot: snapshotOf(working), notifications: batchNotifications(working, userId, result.events, true) },
    });
  }

  nudge(userId: string): Result<{ notifications: Notification[] }> {
    const state = this.load();
    if (state === null) return NOT_FOUND_GAME();
    const seat = seatOf(state, userId);
    if (seat === null) return NOT_SEATED();
    if (state.status !== "active") return fail(400, "cannot_nudge", "The game is over.");
    const due = turnUser(state);
    if (due === null) return fail(400, "cannot_nudge", "Nobody needs a reminder right now.");
    if (due === userId) return fail(400, "cannot_nudge", "It's your turn.");
    const now = this.deps.now().getTime();
    if (state.lastNudgeAt !== null && now - state.lastNudgeAt < NUDGE_INTERVAL_MS) {
      const waitMs = NUDGE_INTERVAL_MS - (now - state.lastNudgeAt);
      const minutes = Math.max(1, Math.ceil(waitMs / 60000));
      return {
        ...fail(429, "too_soon", `They were reminded recently. You can nudge again in ${minutes} minute${minutes === 1 ? "" : "s"}.`),
        retryAfter: Math.ceil(waitMs / 1000),
      };
    }
    const working = structuredClone(state);
    working.lastNudgeAt = now;
    this.save(working, []);
    const notification = nudgeNotification(working, seat);
    return ok({ notifications: notification === null ? [] : [notification] });
  }

  /** The game's id if `userId` may delete it (the creator), else why not. */
  removable(userId: string): Result<string> {
    const state = this.load();
    if (state === null) return NOT_FOUND_GAME();
    if (seatOf(state, userId) === null) return NOT_SEATED();
    if (state.createdBy !== userId) return fail(403, "forbidden", "Only the person who started the game can delete it.");
    return ok(state.id);
  }

  /** Deletes the game (creator only). The caller also clears the Durable Object's storage. */
  remove(userId: string): Result<null> {
    const allowed = this.removable(userId);
    if (!allowed.ok) return allowed;
    this.sql.transaction(() => {
      this.sql.exec("DROP TABLE IF EXISTS state");
      this.sql.exec("DROP TABLE IF EXISTS log");
    });
    this.cached = null;
    return ok(null);
  }

  /** A player's new display name (a new version, since every view shows it). */
  rename(userId: string, name: string): Change | null {
    const state = this.load();
    if (state === null) return null;
    const working = structuredClone(state);
    const entry = renameSeat(working, userId, name);
    if (entry === null) return null;
    this.save(working, [entry]);
    return { snapshot: snapshotOf(working), notifications: [] };
  }

  /** The action log (for tests and debugging; never sent to players). */
  log(): LogEntry[] {
    try {
      return this.sql
        .exec("SELECT version, seat, kind, data FROM log ORDER BY version")
        .map((row) => ({
          version: int(row, "version"),
          seat: row.seat === null ? null : int(row, "seat"),
          kind: text(row, "kind") as LogEntry["kind"],
          data: JSON.parse(text(row, "data")) as unknown,
        }));
    } catch {
      return [];
    }
  }
}
