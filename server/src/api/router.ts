// HTTP routing for docs/online-protocol.md: rate limits, authentication, input validation, then
// the Hub or a GameRoom. Free of Workers globals (the Worker passes its bindings in as
// `Services`), so the whole API is tested in Node against real Hub and GameRoom logic.

import type { VerifyResult } from "../auth/apple.ts";
import { constantTimeEqual, isIdShape, isSessionTokenShape, sessionTokenHash } from "../auth/crypto.ts";
import type { HubApi } from "../hub/host.ts";
import type { User } from "../hub/service.ts";
import type { RoomApi } from "../room/host.ts";
import type { Notification } from "../game/online.ts";
import { fail } from "./result.ts";
import type { Failure, Result } from "./result.ts";
import { cleanName, isDeviceToken, LIMITS, parseActionRequest, parseDevice, parseGameRequest } from "./validate.ts";

export interface Limiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Services {
  hub: HubApi;
  room(gameId: string): RoomApi;
  /** Hands an authenticated WebSocket upgrade to the game's room. */
  live(gameId: string, userId: string, request: Request): Promise<Response>;
  limiters: { user: Limiter; ip: Limiter; auth: Limiter };
  verifyApple(identityToken: string): Promise<VerifyResult>;
  /** POST /v1/auth/dev is enabled only when this is set. */
  devAuthSecret: string | null;
  version: string;
  pushEnabled: boolean;
  /** Keeps background work (pushes) alive after the response (ctx.waitUntil). */
  waitUntil(promise: Promise<unknown>): void;
  log(message: string): void;
}

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...JSON_HEADERS, ...headers } });
}

function noContent(): Response {
  return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
}

export function errorResponse(failure: Failure): Response {
  const headers: Record<string, string> = failure.status === 429 ? { "retry-after": "60" } : {};
  return json({ error: failure.code, message: failure.message, ...(failure.details ?? {}) }, failure.status, headers);
}

function error(status: number, code: string, message: string): Response {
  return errorResponse(fail(status, code, message));
}

function respond<T>(result: Result<T>, render: (value: T) => Response = (value) => json(value)): Response {
  return result.ok ? render(result.value) : errorResponse(result);
}

const RATE_LIMITED = (): Response =>
  error(429, "rate_limited", "You're going a little fast. Wait a minute and try again.");

/** The parsed JSON body, or an error response (too large, not JSON). */
async function readBody(request: Request): Promise<{ ok: true; body: unknown } | { ok: false; response: Response }> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > LIMITS.maxBodyBytes) {
    return { ok: false, response: error(413, "too_large", "That request is too large.") };
  }
  // Read at most the limit (a chunked body has no content-length to check up front).
  const chunks: Uint8Array[] = [];
  let size = 0;
  if (request.body !== null) {
    const reader = request.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > LIMITS.maxBodyBytes) {
        await reader.cancel().catch(() => undefined);
        return { ok: false, response: error(413, "too_large", "That request is too large.") };
      }
      chunks.push(value);
    }
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  let raw: string;
  try {
    raw = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    return { ok: false, response: error(400, "bad_json", "The request body is not valid UTF-8 JSON.") };
  }
  try {
    return { ok: true, body: raw.length === 0 ? {} : (JSON.parse(raw) as unknown) };
  } catch {
    return { ok: false, response: error(400, "bad_json", "The request body is not valid JSON.") };
  }
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function methodNotAllowed(allow: string): Response {
  return error(405, "method_not_allowed", `Use ${allow}.`);
}

async function authenticate(token: string | null, services: Services): Promise<User | null> {
  if (token === null || !isSessionTokenShape(token)) return null;
  return services.hub.authenticate(await sessionTokenHash(token));
}

function bearer(request: Request): string | null {
  const header = request.headers.get("authorization");
  if (header === null) return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match === null ? null : match[1];
}

function sendPushes(services: Services, notifications: Notification[]): void {
  if (notifications.length === 0) return;
  services.waitUntil(
    services.hub.notify(notifications).catch((e: unknown) => services.log(`push delivery failed: ${String(e)}`)),
  );
}

export async function handleRequest(request: Request, services: Services): Promise<Response> {
  try {
    return await route(request, services);
  } catch (e) {
    services.log(`unhandled error for ${request.method} ${new URL(request.url).pathname}: ${String(e)}`);
    return error(500, "internal", "Something went wrong on the server. Try again in a moment.");
  }
}

async function route(request: Request, services: Services): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.length > 1 ? url.pathname.replace(/\/+$/, "") : url.pathname;
  const method = request.method.toUpperCase();

  if (path === "/health") {
    if (method !== "GET" && method !== "HEAD") return methodNotAllowed("GET");
    return json({ ok: true, version: services.version, push: services.pushEnabled });
  }
  if (!path.startsWith("/v1/")) return error(404, "not_found", "There is nothing here.");
  const parts = path.slice("/v1/".length).split("/");
  if (parts.length > 4 || parts.some((p) => p.length === 0 || p.length > 256)) {
    return error(404, "not_found", "There is nothing here.");
  }

  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  if (!(await services.limiters.ip.limit({ key: `ip:${ip}` })).success) return RATE_LIMITED();

  // MARK: Sign-in (no session needed)
  if (parts[0] === "auth") {
    if (parts.length !== 2 || (parts[1] !== "apple" && parts[1] !== "dev")) {
      return error(404, "not_found", "There is nothing here.");
    }
    if (method !== "POST") return methodNotAllowed("POST");
    if (!(await services.limiters.auth.limit({ key: `auth:${ip}` })).success) return RATE_LIMITED();
    const read = await readBody(request);
    if (!read.ok) return read.response;
    const body = read.body;
    if (!isObject(body)) return error(400, "bad_request", "Send a JSON object.");
    if (parts[1] === "apple") {
      const token = body.identityToken;
      if (typeof token !== "string" || token.length === 0 || token.length > LIMITS.identityToken) {
        return error(400, "bad_request", "identityToken is missing.");
      }
      const name = body.displayName === undefined || body.displayName === null
        ? null
        : cleanName(body.displayName, LIMITS.displayName, true);
      let verified: VerifyResult;
      try {
        verified = await services.verifyApple(token);
      } catch (e) {
        services.log(`Apple keys unavailable: ${String(e)}`);
        return error(503, "unavailable", "Sign in with Apple can't be checked right now. Try again in a minute.");
      }
      if (!verified.ok) {
        return error(401, "invalid_token", "Sign in with Apple didn't work. Try signing in again.");
      }
      return json(await services.hub.signIn({ provider: "apple", subject: verified.identity.subject }, name));
    }
    // Dev sign-in: only when the Worker has a DEV_AUTH_SECRET (the deploy's smoke test).
    if (services.devAuthSecret === null || services.devAuthSecret.length === 0) {
      return error(404, "not_found", "There is nothing here.");
    }
    const secret = body.secret;
    const name = cleanName(body.name, LIMITS.displayName);
    if (typeof secret !== "string" || secret.length > LIMITS.devSecret || name === null) {
      return error(400, "bad_request", "Send {\"secret\", \"name\"} (a name of 1 to 24 characters).");
    }
    if (!(await constantTimeEqual(secret, services.devAuthSecret))) {
      return error(401, "unauthorized", "That secret is wrong.");
    }
    return json(await services.hub.signIn({ provider: "dev", subject: name }, name));
  }

  // MARK: Everything else needs a session
  const isLive = parts[0] === "games" && parts.length === 3 && parts[2] === "live";
  const token = isLive ? (url.searchParams.get("token") ?? bearer(request)) : bearer(request);
  const user = await authenticate(token, services);
  if (user === null) return error(401, "unauthorized", "Sign in again.");
  if (!(await services.limiters.user.limit({ key: `user:${user.id}` })).success) return RATE_LIMITED();

  switch (parts[0]) {
    case "me": {
      if (parts.length !== 1) break;
      if (method === "GET") return respond(await services.hub.me(user.id));
      if (method !== "PATCH") return methodNotAllowed("GET or PATCH");
      const read = await readBody(request);
      if (!read.ok) return read.response;
      const name = isObject(read.body) ? cleanName(read.body.displayName, LIMITS.displayName) : null;
      if (name === null) return error(400, "bad_request", "Choose a name of 1 to 24 characters.");
      const result = await services.hub.rename(user.id, name);
      if (result.ok) {
        // Seats in the player's active games show the new name.
        const games = result.value.activeGames;
        services.waitUntil(
          Promise.all(games.map((id) => services.room(id).rename(user.id, name))).catch((e: unknown) =>
            services.log(`rename in games failed: ${String(e)}`),
          ),
        );
      }
      return respond(result, (value) => json({ user: value.user }));
    }

    case "devices": {
      if (parts.length === 1) {
        if (method !== "POST") return methodNotAllowed("POST");
        const read = await readBody(request);
        if (!read.ok) return read.response;
        const device = parseDevice(read.body);
        if (!device.ok) return errorResponse(device);
        await services.hub.registerDevice(user.id, device.value);
        return noContent();
      }
      if (parts.length !== 2) break;
      if (method !== "DELETE") return methodNotAllowed("DELETE");
      const deviceToken = parts[1];
      if (!isDeviceToken(deviceToken)) return error(400, "bad_request", "That is not a device token.");
      await services.hub.removeDevice(user.id, deviceToken.toLowerCase());
      return noContent();
    }

    case "clubs": {
      if (parts.length === 1) {
        if (method !== "POST") return methodNotAllowed("POST");
        const read = await readBody(request);
        if (!read.ok) return read.response;
        const name = isObject(read.body) ? cleanName(read.body.name, LIMITS.clubName) : null;
        if (name === null) return error(400, "bad_request", "Choose a club name of 1 to 40 characters.");
        return respond(await services.hub.createClub(user.id, name));
      }
      if (parts.length === 2 && parts[1] === "join") {
        if (method !== "POST") return methodNotAllowed("POST");
        if (!(await services.limiters.auth.limit({ key: `join:${user.id}` })).success) return RATE_LIMITED();
        const read = await readBody(request);
        if (!read.ok) return read.response;
        const code = isObject(read.body) ? read.body.inviteCode : undefined;
        if (typeof code !== "string" || code.length > 32) return error(400, "bad_request", "Send the club's invite code.");
        return respond(await services.hub.joinClub(user.id, code));
      }
      const clubId = parts[1];
      if (!isIdShape(clubId, "c")) return error(404, "not_found", "That club doesn't exist, or you're not a member.");
      if (parts.length === 2) {
        if (method !== "GET") return methodNotAllowed("GET");
        return respond(await services.hub.club(user.id, clubId));
      }
      if (parts.length === 3 && parts[2] === "leave") {
        if (method !== "POST") return methodNotAllowed("POST");
        return respond(await services.hub.leaveClub(user.id, clubId), () => noContent());
      }
      break;
    }

    case "games": {
      if (parts.length === 1) {
        if (method === "GET") return json({ games: await services.hub.listGames(user.id) });
        if (method !== "POST") return methodNotAllowed("GET or POST");
        const read = await readBody(request);
        if (!read.ok) return read.response;
        const parsed = parseGameRequest(read.body);
        if (!parsed.ok) return errorResponse(parsed);
        const prepared = await services.hub.prepareGame(user.id, parsed.value);
        if (!prepared.ok) return errorResponse(prepared);
        return respond(await services.room(prepared.value.id).create(prepared.value));
      }
      const gameId = parts[1];
      if (!isIdShape(gameId, "g")) return error(404, "not_found", "That game doesn't exist any more.");
      const room = services.room(gameId);
      if (parts.length === 2) {
        if (method === "GET") {
          const reply = await room.read(user.id);
          sendPushes(services, reply.notifications);
          return respond(reply.result);
        }
        if (method !== "DELETE") return methodNotAllowed("GET or DELETE");
        return respond(await room.remove(user.id), () => noContent());
      }
      if (parts.length !== 3) break;
      if (parts[2] === "actions") {
        if (method !== "POST") return methodNotAllowed("POST");
        const read = await readBody(request);
        if (!read.ok) return read.response;
        const parsed = parseActionRequest(read.body);
        if (!parsed.ok) return errorResponse(parsed);
        const reply = await room.act(user.id, parsed.value);
        sendPushes(services, reply.notifications);
        return respond(reply.result);
      }
      if (parts[2] === "nudge") {
        if (method !== "POST") return methodNotAllowed("POST");
        const reply = await room.nudge(user.id);
        sendPushes(services, reply.notifications);
        return respond(reply.result, () => noContent());
      }
      if (parts[2] === "live") {
        if (method !== "GET") return methodNotAllowed("GET");
        if ((request.headers.get("upgrade") ?? "").toLowerCase() !== "websocket") {
          return error(426, "upgrade_required", "Open this address as a WebSocket.");
        }
        return services.live(gameId, user.id, request);
      }
      break;
    }
  }
  return error(404, "not_found", "There is nothing here.");
}
