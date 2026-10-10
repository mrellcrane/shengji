// The GameRoom Durable Object (one per game, named by the game id): a thin adapter over RoomHost
// that adds the live WebSockets (hibernation API: idle sockets cost nothing).

import { DurableObject } from "cloudflare:workers";
import { shuffledDeck } from "../engine/shuffle.ts";
import { RoomHost, roomHub } from "../room/host.ts";
import type { RoomApi, RoomHub } from "../room/host.ts";
import { RoomService } from "../room/service.ts";
import type { ActionRequest, CreateRoomInput } from "../room/service.ts";
import { CLOSE_REPLACED, closeReplyCode, socketsToReplace } from "../room/sockets.ts";
import type { WorkerEnv } from "../env.ts";
import { durableSql } from "./sql.ts";

/** The header the Worker sets on a live connection after checking the session. */
export const USER_HEADER = "x-shengji-user";
/** Close code sent when the game is deleted. */
export const CLOSE_GAME_DELETED = 4004;

interface Attachment {
  userId: string;
  seat: number;
  /** Unix ms when it connected (the oldest of a person's sockets is replaced first). */
  connectedAt?: number;
}

export class GameRoom extends DurableObject<WorkerEnv> implements RoomApi {
  private readonly service: RoomService;
  private readonly host: RoomHost;
  private readonly hub: RoomHub;

  constructor(ctx: DurableObjectState, env: WorkerEnv) {
    super(ctx, env);
    this.service = new RoomService(durableSql(ctx.storage), { deck: () => shuffledDeck(), now: () => new Date() });
    // A new Hub stub for every call: a Hub that was reset breaks the stubs made before (roomHub).
    this.hub = roomHub(env.HUB);
    this.host = new RoomHost(this.service, {
      hub: this.hub,
      broadcast: () => this.broadcast(),
      closeAll: () => this.closeAll(),
      log: (message) => console.error(message),
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
    // Overdue bot turns run first; their pushes go out from here (the Worker only relays the upgrade).
    const connected = await this.host.connect(userId);
    if (connected.notifications.length > 0) {
      this.ctx.waitUntil(
        this.hub.notify(connected.notifications).then(
          () => undefined,
          (e: unknown) => console.error(`push delivery failed: ${String(e)}`),
        ),
      );
    }
    if (!connected.result.ok) {
      const { status, code, message } = connected.result;
      return Response.json({ error: code, message }, { status });
    }
    const seat = connected.result.value.seat;
    // Make room: this person's oldest sockets (often ones a phone left behind) give way.
    const sockets = this.ctx.getWebSockets();
    const open = sockets.map((ws) => {
      const attachment = ws.deserializeAttachment() as Attachment | null;
      return { userId: attachment?.userId ?? "", connectedAt: attachment?.connectedAt ?? 0 };
    });
    const replace = socketsToReplace(open, userId);
    if (replace === null) {
      return Response.json({ error: "rate_limited", message: "Too many connections to this game." }, { status: 429 });
    }
    for (const index of replace) {
      try {
        sockets[index].close(CLOSE_REPLACED, "replaced by a newer connection");
      } catch {
        // Already closed.
      }
    }
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server, [userId]);
    const attachment: Attachment = { userId, seat, connectedAt: Date.now() };
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
      ws.close(closeReplyCode(code), reason);
    } catch {
      // Already closed.
    }
  }
}
