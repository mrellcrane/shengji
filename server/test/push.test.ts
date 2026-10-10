// APNs: the ES256 provider token (signed with a locally generated P-256 key, checked with its
// public key), its 50-minute cache, the request (host per environment, headers, payload), and how
// replies are handled; the Hub's delivery (badges, removing dead devices, push switched off); and
// that a slow push never holds up an action's response.

import assert from "node:assert/strict";
import { test } from "node:test";
import { base64urlDecode, utf8 } from "../src/auth/crypto.ts";
import type { CryptoKeyLike } from "../src/auth/crypto.ts";
import { HubHost } from "../src/hub/host.ts";
import { HubService } from "../src/hub/service.ts";
import { apnsCredentials, apnsPayload, createApnsClient, p8KeyBytes } from "../src/push/apns.ts";
import type { PushMessage } from "../src/push/apns.ts";
import type { GameSnapshot } from "../src/game/summary.ts";
import { makeCloud } from "./cloud.ts";
import { memorySql } from "./sqlite.ts";

type KeyPair = { privateKey: CryptoKeyLike; publicKey: CryptoKeyLike };

async function p8(): Promise<{ pem: string; publicKey: CryptoKeyLike }> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as KeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const base64 = Buffer.from(der).toString("base64").replace(/(.{64})/g, "$1\n");
  return { pem: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n`, publicKey: pair.publicKey };
}

interface Sent {
  url: string;
  headers: Record<string, string>;
  body: unknown;
}

function fakeApns(reply: (sent: Sent) => Response | Promise<Response>) {
  const sent: Sent[] = [];
  const fetchFn = (async (input: string | URL | Request, init?: RequestInit) => {
    const entry: Sent = {
      url: String(input),
      headers: Object.fromEntries(new Headers(init?.headers).entries()),
      body: JSON.parse(String(init?.body)),
    };
    sent.push(entry);
    return reply(entry);
  }) as typeof fetch;
  return { sent, fetchFn };
}

const message = (overrides: Partial<PushMessage> = {}): PushMessage => ({
  token: "ab".repeat(32),
  environment: "sandbox",
  title: "Your turn",
  body: "Mei led K♠ K♠ in Friday Tractor.",
  badge: 2,
  gameId: "g_0123456789abcdefghjkmnpqrs",
  ...overrides,
});

test("push requests: ES256 provider token, host per environment, headers and payload", async () => {
  const key = await p8();
  let now = Date.UTC(2026, 9, 1, 12);
  const { sent, fetchFn } = fakeApns(() => new Response(null, { status: 200 }));
  const client = createApnsClient({ keyP8: key.pem, keyId: "KEY1234567", teamId: "TEAM123456" }, { fetch: fetchFn, now: () => now });

  assert.deepEqual(await client.send(message()), { ok: true });
  assert.deepEqual(await client.send(message({ environment: "production" })), { ok: true });
  assert.equal(sent[0].url, `https://api.sandbox.push.apple.com/3/device/${"ab".repeat(32)}`);
  assert.equal(sent[1].url, `https://api.push.apple.com/3/device/${"ab".repeat(32)}`);
  const headers = sent[0].headers;
  assert.equal(headers["apns-topic"], "com.mrellcrane.shengji");
  assert.equal(headers["apns-push-type"], "alert");
  assert.equal(headers["apns-collapse-id"], "g_0123456789abcdefghjkmnpqrs");
  assert.equal(headers["apns-priority"], "10");
  assert.equal(Number(headers["apns-expiration"]), Math.floor(now / 1000) + 86400);
  assert.deepEqual(sent[0].body, {
    aps: { alert: { title: "Your turn", body: "Mei led K♠ K♠ in Friday Tractor." }, badge: 2, sound: "default", "thread-id": "g_0123456789abcdefghjkmnpqrs" },
    gameId: "g_0123456789abcdefghjkmnpqrs",
  });
  assert.deepEqual(apnsPayload(message()), sent[0].body);

  // The provider token: a JWT with alg ES256 and the key id, iss = team, iat = now, signed with the key.
  const jwt = headers.authorization.replace(/^bearer /, "");
  const [h, c, s] = jwt.split(".");
  assert.deepEqual(JSON.parse(new TextDecoder().decode(base64urlDecode(h)!)), { alg: "ES256", kid: "KEY1234567" });
  assert.deepEqual(JSON.parse(new TextDecoder().decode(base64urlDecode(c)!)), { iss: "TEAM123456", iat: Math.floor(now / 1000) });
  const signature = base64urlDecode(s)!;
  assert.equal(signature.length, 64, "JWS ES256 signatures are r || s");
  assert.ok(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key.publicKey, signature, utf8(`${h}.${c}`)));

  // Cached for 50 minutes, then renewed.
  now += 49 * 60 * 1000;
  await client.send(message());
  assert.equal(sent[2].headers.authorization, headers.authorization);
  now += 2 * 60 * 1000;
  await client.send(message());
  assert.notEqual(sent[3].headers.authorization, headers.authorization);
  const renewed = JSON.parse(new TextDecoder().decode(base64urlDecode(sent[3].headers.authorization.split(".")[1])!));
  assert.equal(renewed.iat, Math.floor(now / 1000));
});

test("APNs replies: gone or bad tokens mark the device dead; a rejected provider token is renewed", async () => {
  const key = await p8();
  let reply: Response = new Response(null, { status: 200 });
  const { sent, fetchFn } = fakeApns(() => reply);
  let now = 1_000_000;
  const client = createApnsClient({ keyP8: key.pem, keyId: "K", teamId: "T" }, { fetch: fetchFn, now: () => now });
  reply = Response.json({ reason: "Unregistered" }, { status: 410 });
  assert.deepEqual(await client.send(message()), { ok: false, status: 410, reason: "Unregistered", unregistered: true });
  reply = Response.json({ reason: "BadDeviceToken" }, { status: 400 });
  assert.deepEqual(await client.send(message()), { ok: false, status: 400, reason: "BadDeviceToken", unregistered: true });
  reply = Response.json({ reason: "PayloadTooLarge" }, { status: 413 });
  assert.deepEqual(await client.send(message()), { ok: false, status: 413, reason: "PayloadTooLarge", unregistered: false });
  reply = new Response("oops", { status: 500 });
  assert.deepEqual(await client.send(message()), { ok: false, status: 500, reason: "HTTP 500", unregistered: false });
  const before = sent.at(-1)!.headers.authorization;
  reply = Response.json({ reason: "ExpiredProviderToken" }, { status: 403 });
  assert.equal((await client.send(message())).ok, false);
  now += 1000;
  reply = new Response(null, { status: 200 });
  await client.send(message());
  assert.notEqual(sent.at(-1)!.headers.authorization, before, "a fresh token after ExpiredProviderToken");

  const offline = createApnsClient({ keyP8: key.pem, keyId: "K", teamId: "T" }, {
    fetch: (async () => {
      throw new Error("no route");
    }) as typeof fetch,
  });
  const failed = await offline.send(message());
  assert.ok(!failed.ok && failed.status === 0 && !failed.unregistered);
});

test("one provider token at a time: concurrent pushes share it, and a restarted Hub reuses the stored one", async () => {
  // APNs refuses provider tokens renewed more often than every 20 minutes
  // (TooManyProviderTokenUpdates), so neither a burst of pushes nor the Hub waking up again may
  // sign a new one while the current one is good.
  const key = await p8();
  const { sent, fetchFn } = fakeApns(() => new Response(null, { status: 200 }));
  const sql = memorySql();
  let now = Date.UTC(2026, 9, 1, 12);
  const clock = () => now;
  const credentials = { keyP8: key.pem, keyId: "KEY1234567", teamId: "TEAM123456" };
  const hubStore = () => new HubService(sql, { now: () => new Date(now) }).providerTokenStore();
  const first = createApnsClient(credentials, { fetch: fetchFn, now: clock, store: hubStore() });
  await Promise.all(Array.from({ length: 6 }, () => first.send(message())));
  const tokens = new Set(sent.map((s) => s.headers.authorization));
  assert.equal(tokens.size, 1, "six pushes at once use one provider token");
  const token = sent[0].headers.authorization;

  // The Hub restarts (a new client over the same storage) 30 minutes later: same token.
  now += 30 * 60 * 1000;
  const second = createApnsClient(credentials, { fetch: fetchFn, now: clock, store: hubStore() });
  await second.send(message());
  assert.equal(sent.at(-1)!.headers.authorization, token);

  // Another key never reuses it.
  const otherKey = createApnsClient({ ...credentials, keyId: "OTHER12345" }, { fetch: fetchFn, now: clock, store: hubStore() });
  await otherKey.send(message());
  assert.notEqual(sent.at(-1)!.headers.authorization, token);

  // Past 50 minutes a restarted Hub signs a new one; after ExpiredProviderToken too.
  now += 21 * 60 * 1000;
  const third = createApnsClient(credentials, { fetch: fetchFn, now: clock, store: hubStore() });
  await third.send(message());
  const renewed = sent.at(-1)!.headers.authorization;
  assert.notEqual(renewed, token);
  const { sent: rejectedSent, fetchFn: rejecting } = fakeApns(() => Response.json({ reason: "ExpiredProviderToken" }, { status: 403 }));
  const fourth = createApnsClient(credentials, { fetch: rejecting, now: clock, store: hubStore() });
  await fourth.send(message());
  assert.equal(rejectedSent[0].headers.authorization, renewed);
  now += 1000;
  const fifth = createApnsClient(credentials, { fetch: fetchFn, now: clock, store: hubStore() });
  await fifth.send(message());
  assert.notEqual(sent.at(-1)!.headers.authorization, renewed, "a rejected token is not reused after a restart");
});

test("the .p8 key is read from PEM (also with literal \\n from a pasted secret); push is off without all three secrets", async () => {
  const key = await p8();
  const pasted = key.pem.replace(/\n/g, "\\n");
  assert.deepEqual(p8KeyBytes(pasted), p8KeyBytes(key.pem));
  const client = createApnsClient({ keyP8: pasted, keyId: "K", teamId: "T" }, { fetch: fakeApns(() => new Response(null, { status: 200 })).fetchFn });
  assert.ok((await client.send(message())).ok);
  assert.equal(p8KeyBytes("-----BEGIN PRIVATE KEY-----\n!!!\n-----END PRIVATE KEY-----"), null);
  const broken = createApnsClient({ keyP8: "not a key", keyId: "K", teamId: "T" }, { fetch: fakeApns(() => new Response(null, { status: 200 })).fetchFn });
  await assert.rejects(broken.providerToken());

  assert.equal(apnsCredentials({}), null);
  assert.equal(apnsCredentials({ APNS_KEY_P8: key.pem, APNS_KEY_ID: "K" }), null);
  assert.equal(apnsCredentials({ APNS_KEY_P8: " ", APNS_KEY_ID: "K", APPLE_TEAM_ID: "T" }), null);
  assert.deepEqual(apnsCredentials({ APNS_KEY_P8: key.pem, APNS_KEY_ID: " K ", APPLE_TEAM_ID: "T" }), { keyP8: key.pem.trim(), keyId: "K", teamId: "T" });
});

test("the Hub sends one push per device with the your-turn badge, and forgets devices APNs rejects", async () => {
  const service = new HubService(memorySql(), { now: () => new Date(0) });
  const mei = service.signIn({ provider: "dev", subject: "Mei" }, "Mei", "h1");
  const lin = service.signIn({ provider: "dev", subject: "Lin" }, "Lin", "h2");
  const good = "aa".repeat(32);
  const dead = "bb".repeat(32);
  service.registerDevice(mei.id, { platform: "ios", token: good, environment: "production" });
  service.registerDevice(mei.id, { platform: "ios", token: dead, environment: "sandbox" });
  service.registerDevice(lin.id, { platform: "ios", token: "cc".repeat(32), environment: "sandbox" });
  const snapshot = (id: string, turn: number): GameSnapshot => ({
    id, clubId: "c", createdBy: mei.id, createdAt: "", updatedAt: "", status: "active", version: 1,
    players: [
      { name: "Mei", isBot: false, userID: mei.id },
      { name: "Bot", isBot: true, userID: null },
      { name: "Lin", isBot: false, userID: lin.id },
      { name: "Bot", isBot: true, userID: null },
    ],
    levels: [2, 2], targetRank: 14, roundNumber: 1, phase: "playing", turn, winner: null, lastEvent: null,
  });
  service.gameChanged(snapshot("g1", 0));
  service.gameChanged(snapshot("g2", 0));
  service.gameChanged(snapshot("g3", 2));

  const sent: PushMessage[] = [];
  const host = new HubHost(service, {
    async send(m) {
      sent.push(m);
      return m.token === dead ? { ok: false, status: 410, reason: "Unregistered", unregistered: true } : { ok: true };
    },
    async providerToken() {
      return "t";
    },
  });
  const report = await host.notify([{ userId: mei.id, gameId: "g1", title: "Your turn", body: "Lin led 3♣ in Club." }]);
  assert.deepEqual(report, { sent: 1, failed: 1, removed: 1 });
  assert.deepEqual(sent.map((m) => [m.token, m.environment, m.badge, m.gameId]).sort(), [
    [good, "production", 2, "g1"],
    [dead, "sandbox", 2, "g1"],
  ].sort());
  assert.deepEqual(service.devices(mei.id).map((d) => d.token), [good], "the dead device is gone");

  // Push switched off: nothing is sent, nothing fails.
  const off = new HubHost(service, null);
  assert.deepEqual(await off.notify([{ userId: lin.id, gameId: "g3", title: "t", body: "b" }]), { sent: 0, failed: 0, removed: 0 });
});

test("an action's response never waits for push delivery", async () => {
  const cloud = makeCloud({ seed: 9 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const club = await cloud.call("POST", "/v1/clubs", { token: mei.token, body: { name: "Club" } });
  await cloud.call("POST", "/v1/clubs/join", { token: lin.token, body: { inviteCode: club.body.club.inviteCode } });
  await cloud.call("POST", "/v1/devices", { token: mei.token, body: { platform: "ios", token: "aa".repeat(32), environment: "sandbox" } });
  const game = await cloud.call("POST", "/v1/games", {
    token: mei.token,
    body: { clubId: club.body.club.id, seats: [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }] },
  });
  const gameId = game.body.game.id;
  // APNs hangs forever: the nudge still answers at once.
  let release: () => void = () => {};
  const hanging = new Promise<void>((resolve) => (release = resolve));
  cloud.push.send = async (m) => {
    cloud.push.sent.push(m);
    await hanging;
    return { ok: true };
  };
  const reply = await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token });
  assert.equal(reply.status, 204);
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(cloud.push.sent.length, 1, "the push was started in the background");
  release();
  await cloud.settle();
});
