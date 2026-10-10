// The GameRoom Durable Object (one per game, named by the game id): a thin adapter over RoomHost
// that adds the live WebSockets (hibernation API: idle sockets cost nothing).

import { DurableObject } from "cloudflare:workers";
import { shuffledDeck } from "../engine/shuffle.ts";
import type { HubApi } from "../hub/host.ts";
import { RoomHost } from "../room/host.ts";
import type { RoomApi } from "../room/host.ts";
import { RoomService } from "../room/service.ts";
import type { ActionRequest, CreateRoomInput } from "../room/service.ts";
import type { WorkerEnv } from "../env.ts";
import { durableSql } from "./sql.ts";

/** The header the Worker sets on a live connection after checking the session. */
export const USER_HEADER = "x-shengji-user";
/** Close code sent when the game is deleted. */
export const CLOSE_GAME_DELETED = 4004;
const MAX_SOCKETS = 40;

interface Attachment {
  userId: string;
  seat: number;
}

export class GameRoom extends DurableObject<WorkerEnv> implements RoomApi {
  private readonly service: RoomService;
  private readonly host: RoomHost;

  constructor(ctx: DurableObjectState, env: WorkerEnv) {
    super(ctx, env);
    this.service = new RoomService(durableSql(ctx.storage), { deck: () => shuffledDeck(), now: () => new Date() });
    const hub = env.HUB.get(env.HUB.idFromName("hub")) as unknown as HubApi;
    this.host = new RoomHost(this.service, {
      hub,
      broadcast: () => this.broadcast(),
      closeAll: () => this.closeAll(),
    });
    // Keep-alive pings are answered without waking the object.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }

  create(input: CreateRoomInput) {
    return this.host.create(input);
  }

  read(userId: string) {
    return this.host.read(userId);
  }

  act(userId: string, request: ActionRequest) {
    return this.host.act(userId, request);
  }

  nudge(userId: string) {
    return this.host.nudge(userId);
  }

  async remove(userId: string) {
    const result = await this.host.remove(userId);
    if (result.ok) await this.ctx.storage.deleteAll();
    return result;
  }

  rename(userId: string, displayName: string) {
    return this.host.rename(userId, displayName);
  }

  /** WebSocket upgrades, forwarded by the Worker with the authenticated user in USER_HEADER. */
  async fetch(request: Request): Promise<Response> {
    const userId = request.headers.get(USER_HEADER);
    if (userId === null || (request.headers.get("upgrade") ?? "").toLowerCase() !== "websocket") {
      return Response.json({ error: "bad_request", message: "Expected a WebSocket upgrade." }, { status: 400 });
    }
    await this.host.read(userId); // runs any overdue bot turns first
    if (this.service.load() === null) {
      return Response.json({ error: "not_found", message: "That game doesn't exist any more." }, { status: 404 });
    }
    const seat = this.service.seatOfUser(userId);
    if (seat === null) {
      return Response.json({ error: "not_seated", message: "You're not playing in this game." }, { status: 403 });
    }
    if (this.ctx.getWebSockets().length >= MAX_SOCKETS) {
      return Response.json({ error: "rate_limited", message: "Too many connections to this game." }, { status: 429 });
    }
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server, [userId]);
    const attachment: Attachment = { userId, seat };
    server.serializeAttachment(attachment);
    const update = this.service.update(seat);
    if (update !== null) server.send(JSON.stringify(update));
    return new Response(null, { status: 101, webSocket: client });
  }

  /** Every connected socket gets its own seat's update (one JSON text per seat). */
  private broadcast(): void {
    const messages = new Map<number, string | null>();
    for (const ws of this.ctx.getWebSockets()) {
      const attachment = ws.deserializeAttachment() as Attachment | null;
      if (attachment === null) continue;
      let message = messages.get(attachment.seat);
      if (message === undefined) {
        const update = this.service.update(attachment.seat);
        message = update === null ? null : JSON.stringify(update);
        messages.set(attachment.seat, message);
      }
      if (message === null) continue;
      try {
        ws.send(message);
      } catch {
        // The socket is closing; the client reconnects and gets a fresh update.
      }
    }
  }

  private closeAll(): void {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(CLOSE_GAME_DELETED, "game deleted");
      } catch {
        // Already closed.
      }
    }
  }

  async webSocketMessage(): Promise<void> {
    // Clients only listen ("ping" is answered automatically); anything else is ignored.
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    try {
      ws.close(code, reason);
    } catch {
      // Already closed.
    }
  }
}
