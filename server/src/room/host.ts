// A GameRoom's public methods (Durable Object RPC): RoomService plus publishing every change,
// in this order: live updates to the connected sockets, then the Hub's games index (awaited, so
// lists are current when the response arrives). Pushes are returned to the caller, which sends
// them without holding up the response (ctx.waitUntil in the Worker).

import { ok } from "../api/result.ts";
import type { Result } from "../api/result.ts";
import type { Notification } from "../game/online.ts";
import type { GameSnapshot, GameSummary } from "../game/summary.ts";
import type { ActionRequest, ActResponse, Change, CreateRoomInput, GameResponse, RoomService } from "./service.ts";

/** A result plus the pushes it causes. */
export interface RoomReply<T> {
  result: Result<T>;
  notifications: Notification[];
}

/** What the HTTP layer calls on a GameRoom. */
export interface RoomApi {
  create(input: CreateRoomInput): Promise<Result<{ game: GameSummary }>>;
  read(userId: string): Promise<RoomReply<GameResponse>>;
  act(userId: string, request: ActionRequest): Promise<RoomReply<ActResponse>>;
  nudge(userId: string): Promise<RoomReply<null>>;
  remove(userId: string): Promise<Result<null>>;
  rename(userId: string, displayName: string): Promise<void>;
}

export interface RoomSurroundings {
  hub: { gameChanged(snapshot: GameSnapshot): Promise<void>; gameDeleted(gameId: string): Promise<void> };
  /** Sends every connected socket its seat's update. */
  broadcast(): void;
  /** Closes every connected socket (the game was deleted). */
  closeAll(): void;
}

export class RoomHost implements RoomApi {
  readonly service: RoomService;
  private readonly around: RoomSurroundings;

  constructor(service: RoomService, around: RoomSurroundings) {
    this.service = service;
    this.around = around;
  }

  private async publish(change: Change | null): Promise<Notification[]> {
    if (change === null) return [];
    this.around.broadcast();
    await this.around.hub.gameChanged(change.snapshot);
    return change.notifications;
  }

  /** Bot turns left over from an interrupted batch run before anything else. */
  private async repair(): Promise<Notification[]> {
    return this.publish(this.service.repair());
  }

  async create(input: CreateRoomInput): Promise<Result<{ game: GameSummary }>> {
    const result = this.service.create(input);
    if (!result.ok) return result;
    await this.publish(result.value.change);
    return ok({ game: result.value.game });
  }

  async read(userId: string): Promise<RoomReply<GameResponse>> {
    const notifications = await this.repair();
    return { result: this.service.read(userId), notifications };
  }

  async act(userId: string, request: ActionRequest): Promise<RoomReply<ActResponse>> {
    const notifications = await this.repair();
    const result = this.service.act(userId, request);
    if (!result.ok) return { result, notifications };
    notifications.push(...(await this.publish(result.value.change)));
    return { result: ok(result.value.body), notifications };
  }

  async nudge(userId: string): Promise<RoomReply<null>> {
    const result = this.service.nudge(userId);
    if (!result.ok) return { result, notifications: [] };
    return { result: ok(null), notifications: result.value.notifications };
  }

  async remove(userId: string): Promise<Result<null>> {
    const id = this.service.load()?.id ?? null;
    const result = this.service.remove(userId);
    if (!result.ok || id === null) return result;
    this.around.closeAll();
    await this.around.hub.gameDeleted(id);
    return result;
  }

  async rename(userId: string, displayName: string): Promise<void> {
    await this.publish(this.service.rename(userId, displayName));
  }
}
