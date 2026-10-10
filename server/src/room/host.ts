// A GameRoom's public methods (Durable Object RPC): RoomService plus publishing every change,
// in this order: live updates to the connected sockets, then the Hub's games index (awaited, so
// lists are current when the response arrives). Pushes are returned to the caller, which sends
// them without holding up the response (ctx.waitUntil in the Worker).
//
// A change is saved before it is published, so a Hub that cannot be reached must not turn an
// accepted move into an error (the player would see a failure for a move that was made, and the
// next player's push would be lost): the index update is tried twice (each time with a new Hub
// stub, see roomHub) and then logged, and the next change brings the index up to date. Deleting
// is the other way round: the Hub first, so a failure leaves the game whole (and trying again
// works) rather than a ghost in every list.

import { NOT_FOUND_GAME, NOT_SEATED, ok } from "../api/result.ts";
import type { Result } from "../api/result.ts";
import type { HubApi } from "../hub/host.ts";
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
  log(message: string): void;
}

/** What a GameRoom calls on the Hub. */
export type RoomHub = Pick<HubApi, "gameChanged" | "gameDeleted" | "notify">;

/** The parts of the HUB binding (a Durable Object namespace) a GameRoom uses. */
export interface HubBinding<Id> {
  idFromName(name: string): Id;
  get(id: Id): unknown;
}

/**
 * The Hub as a GameRoom calls it: a new stub for every call. workerd breaks a stub for good once
 * the object behind it is reset (new code, a limit exceeded, an abort): every later call on that
 * stub fails the same way, and only a new stub reaches the Hub again. A stub kept for the room's
 * lifetime would fail every later index update (the retry too), every delete and every push from
 * that room until the room itself was evicted.
 */
export function roomHub<Id>(binding: HubBinding<Id>): RoomHub {
  const stub = () => binding.get(binding.idFromName("hub")) as RoomHub;
  return {
    gameChanged: (snapshot) => stub().gameChanged(snapshot),
    gameDeleted: (gameId) => stub().gameDeleted(gameId),
    notify: (notifications) => stub().notify(notifications),
  };
}

const INDEX_ATTEMPTS = 2;

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
    await this.updateIndex(change.snapshot);
    return change.notifications;
  }

  private async updateIndex(snapshot: GameSnapshot): Promise<void> {
    for (let attempt = 1; attempt <= INDEX_ATTEMPTS; attempt++) {
      try {
        await this.around.hub.gameChanged(snapshot);
        return;
      } catch (e) {
        if (attempt === INDEX_ATTEMPTS) {
          this.around.log(`games index not updated for ${snapshot.id} (version ${snapshot.version}): ${String(e)}`);
        }
      }
    }
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

  /**
   * A live connection: overdue bot turns run first (their pushes are returned, for the caller to
   * send), then the seat whose updates the socket gets, or why it may not connect.
   */
  async connect(userId: string): Promise<RoomReply<{ seat: number }>> {
    const notifications = await this.repair();
    if (this.service.load() === null) return { result: NOT_FOUND_GAME(), notifications };
    const seat = this.service.seatOfUser(userId);
    if (seat === null) return { result: NOT_SEATED(), notifications };
    return { result: ok({ seat }), notifications };
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
    const allowed = this.service.removable(userId);
    if (!allowed.ok) return allowed;
    // The Hub first (it also stops late index updates from bringing the game back): if it cannot
    // be reached, this throws and nothing is deleted.
    await this.around.hub.gameDeleted(allowed.value);
    const result = this.service.remove(userId);
    if (result.ok) this.around.closeAll();
    return result;
  }

  async rename(userId: string, displayName: string): Promise<void> {
    await this.publish(this.service.rename(userId, displayName));
  }
}
