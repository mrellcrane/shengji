// Cloudflare Worker entry point (shengji-online): wires the bindings into the HTTP router.
// Routing, validation and all game logic live in plain modules (src/api, src/hub, src/room,
// src/game, src/engine) that are unit-tested in Node; the Durable Object classes are thin adapters.

import { appleKeySource, verifyAppleIdentityToken } from "./auth/apple.ts";
import { handleRequest } from "./api/router.ts";
import type { HubApi } from "./hub/host.ts";
import type { RoomApi } from "./room/host.ts";
import { apnsCredentials } from "./push/apns.ts";
import { USER_HEADER } from "./durable/room.ts";
import type { WorkerEnv } from "./env.ts";

export { Hub } from "./durable/hub.ts";
export { GameRoom } from "./durable/room.ts";

/** Apple's signing keys, cached per isolate. */
const appleKeys = appleKeySource();

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const hub = env.HUB.get(env.HUB.idFromName("hub")) as unknown as HubApi;
    const roomStub = (gameId: string) => env.GAMES.get(env.GAMES.idFromName(gameId));
    return handleRequest(request, {
      hub,
      room: (gameId) => roomStub(gameId) as unknown as RoomApi,
      live: (gameId, userId, original) => {
        const headers = new Headers(original.headers);
        headers.set(USER_HEADER, userId);
        return roomStub(gameId).fetch(new Request(original, { headers }));
      },
      limiters: { user: env.USER_LIMITER, ip: env.IP_LIMITER, auth: env.AUTH_LIMITER },
      verifyApple: (identityToken) =>
        verifyAppleIdentityToken(identityToken, { keys: appleKeys, nowSeconds: Math.floor(Date.now() / 1000) }),
      devAuthSecret: env.DEV_AUTH_SECRET?.trim() || null,
      version: env.VERSION || "dev",
      pushEnabled: apnsCredentials(env) !== null,
      waitUntil: (promise) => ctx.waitUntil(promise),
      log: (message) => console.error(message),
    });
  },
} satisfies ExportedHandler<WorkerEnv>;
