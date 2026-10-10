// The Hub's public methods (Durable Object RPC): HubService plus session tokens and push
// delivery. The Durable Object class delegates every method here; tests use it directly.

import { newSessionToken, sessionTokenHash } from "../auth/crypto.ts";
import type { Result } from "../api/result.ts";
import type { Notification } from "../game/online.ts";
import type { GameSnapshot, GameSummary } from "../game/summary.ts";
import type { ApnsClient } from "../push/apns.ts";
import type { Club, Device, GameRequest, HubService, Identity, PreparedGame, User } from "./service.ts";

export interface SignInResult {
  /** The session token (shown once; only its hash is stored). */
  token: string;
  user: User;
}

export interface PushReport {
  sent: number;
  failed: number;
  removed: number;
}

/** What the HTTP layer and the GameRooms call on the Hub. */
export interface HubApi {
  signIn(identity: Identity, displayName: string | null): Promise<SignInResult>;
  authenticate(tokenHash: string): Promise<User | null>;
  me(userId: string): Promise<Result<{ user: User; clubs: Club[] }>>;
  rename(userId: string, displayName: string): Promise<Result<{ user: User; activeGames: string[] }>>;
  registerDevice(userId: string, device: Device): Promise<void>;
  removeDevice(userId: string, token: string): Promise<void>;
  createClub(userId: string, name: string): Promise<Result<{ club: Club }>>;
  joinClub(userId: string, inviteCode: string): Promise<Result<{ club: Club }>>;
  club(userId: string, clubId: string): Promise<Result<{ club: Club; games: GameSummary[] }>>;
  leaveClub(userId: string, clubId: string): Promise<Result<null>>;
  prepareGame(userId: string, request: GameRequest): Promise<Result<PreparedGame>>;
  gameChanged(snapshot: GameSnapshot): Promise<void>;
  gameDeleted(gameId: string): Promise<void>;
  listGames(userId: string): Promise<GameSummary[]>;
  notify(notifications: Notification[]): Promise<PushReport>;
}

export class HubHost implements HubApi {
  readonly service: HubService;
  private readonly push: ApnsClient | null;
  private readonly log: (message: string) => void;

  constructor(service: HubService, push: ApnsClient | null, log: (message: string) => void = () => {}) {
    this.service = service;
    this.push = push;
    this.log = log;
  }

  async signIn(identity: Identity, displayName: string | null): Promise<SignInResult> {
    const token = newSessionToken();
    const user = this.service.signIn(identity, displayName, await sessionTokenHash(token));
    return { token, user };
  }

  async authenticate(tokenHash: string): Promise<User | null> {
    return this.service.authenticate(tokenHash);
  }

  async me(userId: string) {
    return this.service.me(userId);
  }

  async rename(userId: string, displayName: string) {
    return this.service.rename(userId, displayName);
  }

  async registerDevice(userId: string, device: Device): Promise<void> {
    this.service.registerDevice(userId, device);
  }

  async removeDevice(userId: string, token: string): Promise<void> {
    this.service.removeDevice(userId, token);
  }

  async createClub(userId: string, name: string) {
    return this.service.createClub(userId, name);
  }

  async joinClub(userId: string, inviteCode: string) {
    return this.service.joinClub(userId, inviteCode);
  }

  async club(userId: string, clubId: string) {
    return this.service.clubWithGames(userId, clubId);
  }

  async leaveClub(userId: string, clubId: string) {
    return this.service.leaveClub(userId, clubId);
  }

  async prepareGame(userId: string, request: GameRequest) {
    return this.service.prepareGame(userId, request);
  }

  async gameChanged(snapshot: GameSnapshot): Promise<void> {
    this.service.gameChanged(snapshot);
  }

  async gameDeleted(gameId: string): Promise<void> {
    this.service.gameDeleted(gameId);
  }

  async listGames(userId: string): Promise<GameSummary[]> {
    return this.service.listGames(userId);
  }

  /** Sends the pushes (when push is configured) and forgets devices APNs rejects for good. */
  async notify(notifications: Notification[]): Promise<PushReport> {
    const report: PushReport = { sent: 0, failed: 0, removed: 0 };
    if (this.push === null || notifications.length === 0) return report;
    const push = this.push;
    const messages = this.service.pushMessages(notifications);
    const results = await Promise.all(messages.map((message) => push.send(message)));
    const dead: string[] = [];
    results.forEach((result, index) => {
      if (result.ok) {
        report.sent++;
        return;
      }
      report.failed++;
      if (result.unregistered) dead.push(messages[index].token);
      else this.log(`push to a device failed: ${result.status} ${result.reason}`);
    });
    if (dead.length > 0) {
      this.service.removeDeviceTokens(dead);
      report.removed = dead.length;
    }
    return report;
  }
}
