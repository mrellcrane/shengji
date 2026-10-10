// The Hub's logic over its SQLite storage: users, linked sign-in identities, sessions, devices,
// clubs, memberships and the games index. Synchronous: the Durable Object (src/durable/hub.ts)
// adds RPC and push delivery (see HubHost in host.ts).

import { formatInviteCode, newId, newInviteCode, normalizeInviteCode } from "../auth/crypto.ts";
import type { Rank } from "../engine/cards.ts";
import { compareSummaries, seatOfUser, summarize } from "../game/summary.ts";
import type { GameSnapshot, GameSummary } from "../game/summary.ts";
import type { BotLevel } from "../game/bots.ts";
import { botName } from "../game/online.ts";
import type { Notification, SeatAssignment } from "../game/online.ts";
import type { ProviderTokenStore, PushEnvironment, PushMessage, StoredProviderToken } from "../push/apns.ts";
import { fail, ok } from "../api/result.ts";
import type { Result } from "../api/result.ts";
import { int, one, text } from "../storage/sql.ts";
import type { Row, Sql } from "../storage/sql.ts";

export const SESSION_DAYS = 180;
export const MAX_SESSIONS_PER_USER = 20;
export const MAX_DEVICES_PER_USER = 10;
export const MAX_CLUBS_PER_USER = 20;
export const MAX_CLUB_MEMBERS = 50;
export const MAX_ACTIVE_GAMES_PER_USER = 30;
export const FINISHED_GAMES_LISTED = 20;
export const CLUB_GAMES_LISTED = 50;

export interface User {
  id: string;
  displayName: string;
}

export interface Club {
  id: string;
  name: string;
  /** Shown as ABCD-EFGH. */
  inviteCode: string;
  members: User[];
}

/** A sign-in identity: provider "apple" (now), "google" (later), "dev" (smoke tests). */
export interface Identity {
  provider: "apple" | "google" | "dev";
  subject: string;
}

export interface Device {
  platform: "ios";
  token: string;
  environment: PushEnvironment;
}

/** A seat as POST /v1/games names it (absolute order). */
export type SeatRequest = { userId: string } | { bot: BotLevel };

export interface GameRequest {
  clubId: string;
  seats: SeatRequest[];
  targetRank: Rank;
}

export interface PreparedGame {
  id: string;
  clubId: string;
  clubName: string;
  createdBy: string;
  seats: SeatAssignment[];
  targetRank: Rank;
}

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS users (
     id TEXT PRIMARY KEY,
     display_name TEXT NOT NULL,
     created_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS identities (
     provider TEXT NOT NULL,
     subject TEXT NOT NULL,
     user_id TEXT NOT NULL,
     created_at TEXT NOT NULL,
     PRIMARY KEY (provider, subject)
   )`,
  `CREATE INDEX IF NOT EXISTS identities_user ON identities (user_id)`,
  `CREATE TABLE IF NOT EXISTS sessions (
     token_hash TEXT PRIMARY KEY,
     user_id TEXT NOT NULL,
     created_at TEXT NOT NULL,
     expires_at INTEGER NOT NULL
   )`,
  `CREATE INDEX IF NOT EXISTS sessions_user ON sessions (user_id)`,
  `CREATE TABLE IF NOT EXISTS devices (
     token TEXT PRIMARY KEY,
     user_id TEXT NOT NULL,
     platform TEXT NOT NULL,
     environment TEXT NOT NULL,
     updated_at TEXT NOT NULL
   )`,
  `CREATE INDEX IF NOT EXISTS devices_user ON devices (user_id)`,
  `CREATE TABLE IF NOT EXISTS clubs (
     id TEXT PRIMARY KEY,
     name TEXT NOT NULL,
     invite_code TEXT NOT NULL UNIQUE,
     created_by TEXT NOT NULL,
     created_at TEXT NOT NULL
   )`,
  `CREATE TABLE IF NOT EXISTS memberships (
     club_id TEXT NOT NULL,
     user_id TEXT NOT NULL,
     joined_at TEXT NOT NULL,
     PRIMARY KEY (club_id, user_id)
   )`,
  `CREATE INDEX IF NOT EXISTS memberships_user ON memberships (user_id)`,
  `CREATE TABLE IF NOT EXISTS games (
     id TEXT PRIMARY KEY,
     club_id TEXT NOT NULL,
     created_by TEXT NOT NULL,
     status TEXT NOT NULL,
     updated_at TEXT NOT NULL,
     version INTEGER NOT NULL,
     turn_user TEXT,
     snapshot TEXT NOT NULL
   )`,
  `CREATE INDEX IF NOT EXISTS games_club ON games (club_id, updated_at)`,
  `CREATE INDEX IF NOT EXISTS games_turn ON games (turn_user, status)`,
  `CREATE TABLE IF NOT EXISTS game_players (
     game_id TEXT NOT NULL,
     user_id TEXT NOT NULL,
     seat INTEGER NOT NULL,
     PRIMARY KEY (game_id, user_id)
   )`,
  `CREATE INDEX IF NOT EXISTS game_players_user ON game_players (user_id)`,
  // Deleted games, so an index update still in flight cannot bring one back.
  `CREATE TABLE IF NOT EXISTS deleted_games (
     id TEXT PRIMARY KEY,
     deleted_at TEXT NOT NULL
   )`,
  // Small server state that must outlive the Durable Object's restarts (the APNs provider token).
  `CREATE TABLE IF NOT EXISTS settings (
     key TEXT PRIMARY KEY,
     value TEXT NOT NULL
   )`,
];

const PROVIDER_TOKEN_KEY = "apns_provider_token";

const DEFAULT_NAME = /^Player \d{4}$/;

export class HubService {
  private readonly sql: Sql;
  private readonly now: () => Date;
  private readonly random: () => number;

  constructor(sql: Sql, deps: { now(): Date; random?: () => number }) {
    this.sql = sql;
    this.now = deps.now;
    this.random = deps.random ?? Math.random;
    for (const statement of SCHEMA) sql.exec(statement);
  }

  private iso(): string {
    return this.now().toISOString();
  }

  // MARK: Users and sessions

  private user(id: string): User | null {
    const row = one(this.sql, "SELECT id, display_name FROM users WHERE id = ?", id);
    return row === null ? null : { id: text(row, "id"), displayName: text(row, "display_name") };
  }

  /**
   * Finds or creates the user of `identity` and stores a session for `tokenHash` (180 days).
   * `displayName` names a new user (else "Player 1234"); it also replaces such a default name.
   */
  signIn(identity: Identity, displayName: string | null, tokenHash: string): User {
    const now = this.now();
    return this.sql.transaction(() => {
      const row = one(
        this.sql,
        "SELECT user_id FROM identities WHERE provider = ? AND subject = ?",
        identity.provider,
        identity.subject,
      );
      let userId: string;
      if (row === null) {
        userId = newId("u");
        const name = displayName ?? `Player ${1000 + Math.floor(this.random() * 9000)}`;
        this.sql.exec("INSERT INTO users (id, display_name, created_at) VALUES (?, ?, ?)", userId, name, now.toISOString());
        this.sql.exec(
          "INSERT INTO identities (provider, subject, user_id, created_at) VALUES (?, ?, ?, ?)",
          identity.provider,
          identity.subject,
          userId,
          now.toISOString(),
        );
      } else {
        userId = text(row, "user_id");
        const current = this.user(userId);
        if (displayName !== null && current !== null && DEFAULT_NAME.test(current.displayName)) {
          this.sql.exec("UPDATE users SET display_name = ? WHERE id = ?", displayName, userId);
        }
      }
      this.sql.exec("DELETE FROM sessions WHERE user_id = ? AND expires_at <= ?", userId, now.getTime());
      this.sql.exec(
        "INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
        tokenHash,
        userId,
        now.toISOString(),
        now.getTime() + SESSION_DAYS * 24 * 60 * 60 * 1000,
      );
      // Keep the newest sessions only (each sign-in makes one).
      this.sql.exec(
        `DELETE FROM sessions WHERE user_id = ? AND token_hash NOT IN (
           SELECT token_hash FROM sessions WHERE user_id = ? ORDER BY expires_at DESC LIMIT ?)`,
        userId,
        userId,
        MAX_SESSIONS_PER_USER,
      );
      const user = this.user(userId);
      if (user === null) throw new Error("user vanished during sign-in");
      return user;
    });
  }

  /** The user of a session, or null if there is no such session or it expired. */
  authenticate(tokenHash: string): User | null {
    const row = one(
      this.sql,
      `SELECT u.id, u.display_name, s.expires_at FROM sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ?`,
      tokenHash,
    );
    if (row === null) return null;
    if (int(row, "expires_at") <= this.now().getTime()) {
      this.sql.exec("DELETE FROM sessions WHERE token_hash = ?", tokenHash);
      return null;
    }
    return { id: text(row, "id"), displayName: text(row, "display_name") };
  }

  me(userId: string): Result<{ user: User; clubs: Club[] }> {
    const user = this.user(userId);
    if (user === null) return fail(401, "unauthorized", "Sign in again.");
    const clubs = this.sql
      .exec(
        `SELECT c.id FROM memberships m JOIN clubs c ON c.id = m.club_id WHERE m.user_id = ?
         ORDER BY m.joined_at, m.rowid`,
        userId,
      )
      .map((row) => this.club(text(row, "id")))
      .filter((club): club is Club => club !== null);
    return ok({ user, clubs });
  }

  /** Renames the user; also returns their active games, whose seats show the name. */
  rename(userId: string, displayName: string): Result<{ user: User; activeGames: string[] }> {
    this.sql.exec("UPDATE users SET display_name = ? WHERE id = ?", displayName, userId);
    const user = this.user(userId);
    if (user === null) return fail(401, "unauthorized", "Sign in again.");
    const activeGames = this.sql
      .exec(
        `SELECT g.id FROM game_players p JOIN games g ON g.id = p.game_id
         WHERE p.user_id = ? AND g.status = 'active'`,
        userId,
      )
      .map((row) => text(row, "id"));
    return ok({ user, activeGames });
  }

  // MARK: Devices

  registerDevice(userId: string, device: Device): void {
    this.sql.transaction(() => {
      this.sql.exec(
        `INSERT INTO devices (token, user_id, platform, environment, updated_at) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, platform = excluded.platform,
           environment = excluded.environment, updated_at = excluded.updated_at`,
        device.token,
        userId,
        device.platform,
        device.environment,
        this.iso(),
      );
      this.sql.exec(
        `DELETE FROM devices WHERE user_id = ? AND token NOT IN (
           SELECT token FROM devices WHERE user_id = ? ORDER BY updated_at DESC, token LIMIT ?)`,
        userId,
        userId,
        MAX_DEVICES_PER_USER,
      );
    });
  }

  removeDevice(userId: string, token: string): void {
    this.sql.exec("DELETE FROM devices WHERE token = ? AND user_id = ?", token, userId);
  }

  /** Forgets devices that APNs reported as no longer valid. */
  removeDeviceTokens(tokens: readonly string[]): void {
    for (const token of tokens) this.sql.exec("DELETE FROM devices WHERE token = ?", token);
  }

  devices(userId: string): Device[] {
    return this.sql
      .exec("SELECT token, platform, environment FROM devices WHERE user_id = ? ORDER BY updated_at DESC", userId)
      .map((row) => ({
        platform: "ios",
        token: text(row, "token"),
        environment: text(row, "environment") === "production" ? "production" : "sandbox",
      }));
  }

  // MARK: Clubs

  private club(clubId: string): Club | null {
    const row = one(this.sql, "SELECT id, name, invite_code FROM clubs WHERE id = ?", clubId);
    if (row === null) return null;
    const members = this.sql
      .exec(
        `SELECT u.id, u.display_name FROM memberships m JOIN users u ON u.id = m.user_id
         WHERE m.club_id = ? ORDER BY m.joined_at, m.rowid`,
        clubId,
      )
      .map((r) => ({ id: text(r, "id"), displayName: text(r, "display_name") }));
    return { id: text(row, "id"), name: text(row, "name"), inviteCode: formatInviteCode(text(row, "invite_code")), members };
  }

  private isMember(clubId: string, userId: string): boolean {
    return one(this.sql, "SELECT 1 AS yes FROM memberships WHERE club_id = ? AND user_id = ?", clubId, userId) !== null;
  }

  private clubCount(userId: string): number {
    const row = one(this.sql, "SELECT COUNT(*) AS n FROM memberships WHERE user_id = ?", userId);
    return row === null ? 0 : int(row, "n");
  }

  createClub(userId: string, name: string): Result<{ club: Club }> {
    if (this.clubCount(userId) >= MAX_CLUBS_PER_USER) {
      return fail(409, "too_many_clubs", `You can be in at most ${MAX_CLUBS_PER_USER} clubs.`);
    }
    const id = newId("c");
    const at = this.iso();
    this.sql.transaction(() => {
      let code = newInviteCode();
      while (one(this.sql, "SELECT 1 AS yes FROM clubs WHERE invite_code = ?", code) !== null) code = newInviteCode();
      this.sql.exec(
        "INSERT INTO clubs (id, name, invite_code, created_by, created_at) VALUES (?, ?, ?, ?, ?)",
        id,
        name,
        code,
        userId,
        at,
      );
      this.sql.exec("INSERT INTO memberships (club_id, user_id, joined_at) VALUES (?, ?, ?)", id, userId, at);
    });
    const club = this.club(id);
    if (club === null) throw new Error("club vanished");
    return ok({ club });
  }

  joinClub(userId: string, inviteCode: string): Result<{ club: Club }> {
    const code = normalizeInviteCode(inviteCode);
    const row = code === null ? null : one(this.sql, "SELECT id FROM clubs WHERE invite_code = ?", code);
    if (row === null) return fail(404, "not_found", "No club has that invite code. Check it and try again.");
    const clubId = text(row, "id");
    if (!this.isMember(clubId, userId)) {
      if (this.clubCount(userId) >= MAX_CLUBS_PER_USER) {
        return fail(409, "too_many_clubs", `You can be in at most ${MAX_CLUBS_PER_USER} clubs.`);
      }
      const members = one(this.sql, "SELECT COUNT(*) AS n FROM memberships WHERE club_id = ?", clubId);
      if (members !== null && int(members, "n") >= MAX_CLUB_MEMBERS) {
        return fail(409, "club_full", "That club is full.");
      }
      this.sql.exec("INSERT INTO memberships (club_id, user_id, joined_at) VALUES (?, ?, ?)", clubId, userId, this.iso());
    }
    const club = this.club(clubId);
    if (club === null) throw new Error("club vanished");
    return ok({ club });
  }

  clubWithGames(userId: string, clubId: string): Result<{ club: Club; games: GameSummary[] }> {
    const club = this.isMember(clubId, userId) ? this.club(clubId) : null;
    if (club === null) return fail(404, "not_found", "That club doesn't exist, or you're not a member.");
    const games = this.sql
      .exec(
        `SELECT snapshot FROM games WHERE club_id = ? ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END,
         updated_at DESC LIMIT ?`,
        clubId,
        CLUB_GAMES_LISTED,
      )
      .map((row) => {
        const snapshot = JSON.parse(text(row, "snapshot")) as GameSnapshot;
        return summarize(snapshot, seatOfUser(snapshot.players, userId));
      })
      .sort(compareSummaries);
    return ok({ club, games });
  }

  leaveClub(userId: string, clubId: string): Result<null> {
    if (!this.isMember(clubId, userId)) return fail(404, "not_found", "That club doesn't exist, or you're not a member.");
    this.sql.transaction(() => {
      this.sql.exec("DELETE FROM memberships WHERE club_id = ? AND user_id = ?", clubId, userId);
      const left = one(this.sql, "SELECT COUNT(*) AS n FROM memberships WHERE club_id = ?", clubId);
      // An empty club goes away (its games stay with their players).
      if (left !== null && int(left, "n") === 0) this.sql.exec("DELETE FROM clubs WHERE id = ?", clubId);
    });
    return ok(null);
  }

  // MARK: Games index

  /** Checks a new game's table against the club and names the seats. */
  prepareGame(userId: string, request: GameRequest): Result<PreparedGame> {
    const clubRow = one(this.sql, "SELECT name FROM clubs WHERE id = ?", request.clubId);
    if (clubRow === null || !this.isMember(request.clubId, userId)) {
      return fail(404, "not_found", "That club doesn't exist, or you're not a member.");
    }
    if (request.seats.length !== 4) return fail(400, "bad_request", "A table has exactly four seats.");
    const humans = request.seats.flatMap((s) => ("userId" in s ? [s.userId] : []));
    if (new Set(humans).size !== humans.length) return fail(400, "bad_request", "Each person can take only one seat.");
    if (!humans.includes(userId)) return fail(400, "bad_request", "You need a seat at your own table.");
    const seats: SeatAssignment[] = [];
    for (const [index, seat] of request.seats.entries()) {
      if ("bot" in seat) {
        seats.push({ userId: null, bot: seat.bot, name: botName(index) });
        continue;
      }
      const user = this.user(seat.userId);
      if (user === null || !this.isMember(request.clubId, seat.userId)) {
        return fail(400, "bad_request", "Everyone at the table must be a member of the club.");
      }
      seats.push({ userId: user.id, bot: null, name: user.displayName });
    }
    // Everyone at the table, not only the creator: game lists show each person's active games
    // only up to a limit, so nobody may be seated in more than this.
    for (const seat of seats) {
      if (seat.userId === null) continue;
      const active = one(
        this.sql,
        `SELECT COUNT(*) AS n FROM game_players p JOIN games g ON g.id = p.game_id
         WHERE p.user_id = ? AND g.status = 'active'`,
        seat.userId,
      );
      if (active !== null && int(active, "n") >= MAX_ACTIVE_GAMES_PER_USER) {
        return fail(
          409,
          "too_many_games",
          seat.userId === userId
            ? `You can have at most ${MAX_ACTIVE_GAMES_PER_USER} games going at once.`
            : `${seat.name} already has ${MAX_ACTIVE_GAMES_PER_USER} games going, the most at once. Try again when one of them ends.`,
        );
      }
    }
    return ok({
      id: newId("g"),
      clubId: request.clubId,
      clubName: text(clubRow, "name"),
      createdBy: userId,
      seats,
      targetRank: request.targetRank,
    });
  }

  /** Stores a game's new snapshot (ignored if an older one arrives late). */
  gameChanged(snapshot: GameSnapshot): void {
    if (one(this.sql, "SELECT 1 AS yes FROM deleted_games WHERE id = ?", snapshot.id) !== null) return;
    const turnSeat = snapshot.status === "active" ? snapshot.turn : null;
    const turnUser = turnSeat === null ? null : (snapshot.players[turnSeat]?.userID ?? null);
    this.sql.transaction(() => {
      this.sql.exec(
        `INSERT INTO games (id, club_id, created_by, status, updated_at, version, turn_user, snapshot)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET status = excluded.status, updated_at = excluded.updated_at,
           version = excluded.version, turn_user = excluded.turn_user, snapshot = excluded.snapshot
         WHERE excluded.version >= games.version`,
        snapshot.id,
        snapshot.clubId,
        snapshot.createdBy,
        snapshot.status,
        snapshot.updatedAt,
        snapshot.version,
        turnUser,
        JSON.stringify(snapshot),
      );
      snapshot.players.forEach((player, seat) => {
        if (player.isBot || player.userID === null) return;
        this.sql.exec(
          "INSERT OR IGNORE INTO game_players (game_id, user_id, seat) VALUES (?, ?, ?)",
          snapshot.id,
          player.userID,
          seat,
        );
      });
    });
  }

  gameDeleted(gameId: string): void {
    this.sql.transaction(() => {
      this.sql.exec("DELETE FROM games WHERE id = ?", gameId);
      this.sql.exec("DELETE FROM game_players WHERE game_id = ?", gameId);
      this.sql.exec("INSERT OR IGNORE INTO deleted_games (id, deleted_at) VALUES (?, ?)", gameId, this.iso());
    });
  }

  /** The caller's games: active ones (your turn first), then the latest finished ones. */
  listGames(userId: string): GameSummary[] {
    const rows = (status: string, limit: number) =>
      this.sql.exec(
        `SELECT g.snapshot, p.seat FROM game_players p JOIN games g ON g.id = p.game_id
         WHERE p.user_id = ? AND g.status = ? ORDER BY g.updated_at DESC LIMIT ?`,
        userId,
        status,
        limit,
      );
    const toSummary = (row: Row): GameSummary =>
      summarize(JSON.parse(text(row, "snapshot")) as GameSnapshot, int(row, "seat"));
    const active = rows("active", MAX_ACTIVE_GAMES_PER_USER * 2).map(toSummary);
    const finished = rows("finished", FINISHED_GAMES_LISTED).map(toSummary);
    return [...active.sort(compareSummaries), ...finished.sort(compareSummaries)];
  }

  /** Number of active games where it is the user's turn (the app icon badge). */
  turnCount(userId: string): number {
    const row = one(this.sql, "SELECT COUNT(*) AS n FROM games WHERE turn_user = ? AND status = 'active'", userId);
    return row === null ? 0 : int(row, "n");
  }

  // MARK: Settings

  private setting(key: string): string | null {
    const row = one(this.sql, "SELECT value FROM settings WHERE key = ?", key);
    return row === null ? null : text(row, "value");
  }

  private setSetting(key: string, value: string | null): void {
    if (value === null) this.sql.exec("DELETE FROM settings WHERE key = ?", key);
    else this.sql.exec("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, value);
  }

  /** Keeps the APNs provider token across restarts of the Hub (see ProviderTokenStore). */
  providerTokenStore(): ProviderTokenStore {
    return {
      load: () => {
        const value = this.setting(PROVIDER_TOKEN_KEY);
        if (value === null) return null;
        try {
          const parsed = JSON.parse(value) as StoredProviderToken;
          return typeof parsed.token === "string" && typeof parsed.issuedAt === "number" ? parsed : null;
        } catch {
          return null;
        }
      },
      save: (token) => this.setSetting(PROVIDER_TOKEN_KEY, token === null ? null : JSON.stringify(token)),
    };
  }

  /** One push per device of each notified user, with their badge count. */
  pushMessages(notifications: readonly Notification[]): PushMessage[] {
    const out: PushMessage[] = [];
    for (const n of notifications) {
      const badge = this.turnCount(n.userId);
      for (const device of this.devices(n.userId)) {
        out.push({
          token: device.token,
          environment: device.environment,
          title: n.title,
          body: n.body,
          badge,
          gameId: n.gameId,
        });
      }
    }
    return out;
  }
}
