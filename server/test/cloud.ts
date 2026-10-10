// An in-process stand-in for the deployed Worker: the real router, HubHost and RoomHosts over
// node:sqlite, wired like src/worker.ts and the Durable Object adapters. Calls between them go
// through `rpc`, which clones arguments and results like Durable Object RPC does (so anything
// that would not survive RPC fails here too). Time, randomness, Apple and APNs are fakes.

import { handleRequest } from "../src/api/router.ts";
import type { Limiter, Services } from "../src/api/router.ts";
import type { VerifyResult } from "../src/auth/apple.ts";
import { doubleDeck } from "../src/engine/cards.ts";
import { shuffle } from "../src/engine/shuffle.ts";
import type { RandomSource } from "../src/engine/shuffle.ts";
import type { Card } from "../src/engine/cards.ts";
import { HubHost } from "../src/hub/host.ts";
import type { HubApi } from "../src/hub/host.ts";
import { HubService } from "../src/hub/service.ts";
import type { ApnsClient, PushMessage, PushResult } from "../src/push/apns.ts";
import { RoomHost } from "../src/room/host.ts";
import type { RoomApi } from "../src/room/host.ts";
import { RoomService } from "../src/room/service.ts";
import { memorySql } from "./sqlite.ts";

/** Wraps an object so every method call clones its arguments and result (like DO RPC). */
export function rpc<T extends object>(target: T): T {
  return new Proxy(target, {
    get(object, key) {
      const value = (object as Record<string | symbol, unknown>)[key];
      if (typeof value !== "function") return value;
      return async (...args: unknown[]) =>
        structuredClone(await (value as (...a: unknown[]) => unknown).apply(object, structuredClone(args)));
    },
  });
}

/** A seeded RandomSource (mulberry32) for reproducible deals. */
export function seededSource(seed: number): RandomSource {
  let state = seed >>> 0;
  return (array) => {
    for (let i = 0; i < array.length; i++) {
      state = (state + 0x6d2b79f5) >>> 0;
      let t = state;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      array[i] = (t ^ (t >>> 14)) >>> 0;
    }
    return array;
  };
}

export interface FakePush extends ApnsClient {
  sent: PushMessage[];
  /** Reply for a token (default: delivered). */
  reply: (message: PushMessage) => PushResult;
}

export function fakePush(): FakePush {
  const push: FakePush = {
    sent: [],
    reply: () => ({ ok: true }),
    async send(message) {
      push.sent.push(message);
      return push.reply(message);
    },
    async providerToken() {
      return "fake";
    },
  };
  return push;
}

export interface CloudOptions {
  devSecret?: string | null;
  seed?: number;
  /** Decks for new rounds, in order (then seeded shuffles). */
  decks?: Card[][];
  apple?: (token: string) => VerifyResult;
  push?: boolean;
}

export interface Reply {
  status: number;
  body: any;
  headers: Headers;
}

export interface Cloud {
  services: Services;
  hub: HubHost;
  rooms: Map<string, RoomHost>;
  push: FakePush;
  clock: { now: number };
  /** Every limiter answers with this (flip to false to test 429). */
  limits: { allow: boolean; keys: string[] };
  broadcasts: Map<string, number>;
  closed: Set<string>;
  logs: string[];
  /** Background work handed to waitUntil (pushes, renames); `settle` awaits it. */
  settle(): Promise<void>;
  call(method: string, path: string, options?: { token?: string; body?: unknown; raw?: string; headers?: Record<string, string> }): Promise<Reply>;
  /** Signs in with dev auth; returns the token and user id. */
  signIn(name: string): Promise<{ token: string; id: string; name: string }>;
}

export function makeCloud(options: CloudOptions = {}): Cloud {
  const clock = { now: Date.UTC(2026, 9, 1, 12, 0, 0) };
  const now = () => new Date(clock.now);
  const source = seededSource(options.seed ?? 1);
  const decks = (options.decks ?? []).slice();
  const deck = () => decks.shift() ?? shuffle(doubleDeck(), source);
  const push = fakePush();
  const logs: string[] = [];
  const hub = new HubHost(new HubService(memorySql(), { now, random: () => 0.5 }), options.push === false ? null : push, (m) =>
    logs.push(m),
  );
  const hubApi = rpc<HubApi>(hub);
  const rooms = new Map<string, RoomHost>();
  const broadcasts = new Map<string, number>();
  const closed = new Set<string>();
  const room = (gameId: string): RoomHost => {
    let host = rooms.get(gameId);
    if (host === undefined) {
      host = new RoomHost(new RoomService(memorySql(), { deck, now }), {
        hub: hubApi,
        broadcast: () => broadcasts.set(gameId, (broadcasts.get(gameId) ?? 0) + 1),
        closeAll: () => closed.add(gameId),
        log: (message) => logs.push(message),
      });
      rooms.set(gameId, host);
    }
    return host;
  };
  const limits = { allow: true, keys: [] as string[] };
  const limiter: Limiter = {
    async limit({ key }) {
      limits.keys.push(key);
      return { success: limits.allow };
    },
  };
  const pending: Promise<unknown>[] = [];
  const services: Services = {
    hub: hubApi,
    room: (gameId) => rpc<RoomApi>(room(gameId)),
    live: async (gameId, userId) => new Response(JSON.stringify({ live: gameId, userId }), { status: 200 }),
    limiters: { user: limiter, ip: limiter, auth: limiter },
    verifyApple: async (token) => (options.apple ?? (() => ({ ok: false, reason: "no apple in tests" })))(token),
    devAuthSecret: options.devSecret === undefined ? "test-secret" : options.devSecret,
    version: "test",
    pushEnabled: options.push !== false,
    waitUntil: (promise) => {
      pending.push(promise);
    },
    log: (message) => logs.push(message),
  };

  const cloud: Cloud = {
    services,
    hub,
    rooms,
    push,
    clock,
    limits,
    broadcasts,
    closed,
    logs,
    async settle() {
      while (pending.length > 0) await pending.shift();
    },
    async call(method, path, opts = {}) {
      const headers: Record<string, string> = { "cf-connecting-ip": "203.0.113.7", ...(opts.headers ?? {}) };
      if (opts.token !== undefined) headers.authorization = `Bearer ${opts.token}`;
      let body: string | undefined = opts.raw;
      if (opts.body !== undefined) {
        body = JSON.stringify(opts.body);
        headers["content-type"] = "application/json";
      }
      const response = await handleRequest(new Request(`https://shengji.test${path}`, { method, headers, body }), services);
      const text = await response.text();
      return { status: response.status, body: text.length > 0 ? JSON.parse(text) : null, headers: response.headers };
    },
    async signIn(name) {
      const reply = await cloud.call("POST", "/v1/auth/dev", { body: { secret: "test-secret", name } });
      if (reply.status !== 200) throw new Error(`sign-in failed: ${JSON.stringify(reply.body)}`);
      return { token: reply.body.token as string, id: reply.body.user.id as string, name };
    },
  };
  return cloud;
}
