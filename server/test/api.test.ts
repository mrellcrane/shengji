// The HTTP surface (src/api/router.ts) end to end in Node: health, sign-in (Apple and dev),
// sessions, rate limits, body limits, me, devices, clubs and the live endpoint's checks.

import assert from "node:assert/strict";
import { test } from "node:test";
import { makeCloud } from "./cloud.ts";

test("health reports the version and whether push is on; unknown paths and methods are refused", async () => {
  const on = makeCloud();
  assert.deepEqual((await on.call("GET", "/health")).body, { ok: true, version: "test", push: true });
  const off = makeCloud({ push: false });
  assert.deepEqual((await off.call("GET", "/health")).body, { ok: true, version: "test", push: false });
  assert.equal((await on.call("POST", "/health")).status, 405);
  for (const path of ["/", "/v2/me", "/v1", "/v1/nothing", "/v1/auth/google", "/v1/me/extra", "/v1/games/g_x/live/more/deep"]) {
    const reply = await on.call("GET", path);
    assert.ok(reply.status === 404 || reply.status === 401, `${path}: ${reply.status}`);
    assert.equal(typeof reply.body.error, "string");
    assert.equal(typeof reply.body.message, "string");
  }
  assert.equal((await on.call("GET", "/v1/auth/dev")).status, 405);
});

test("Sign in with Apple: a verified token signs in (name from the app), a bad one is 401, Apple down is 503", async () => {
  let appleDown = false;
  const cloud = makeCloud({
    apple: (token) => {
      if (appleDown) throw new Error("keys unavailable");
      return token === "good-token" ? { ok: true, identity: { subject: "000123.apple" } } : { ok: false, reason: "bad signature" };
    },
  });
  const first = await cloud.call("POST", "/v1/auth/apple", { body: { identityToken: "good-token", displayName: "Mei Chen, who has a very long name" } });
  assert.equal(first.status, 200);
  assert.match(first.body.token, /^[A-Za-z0-9_-]{43}$/);
  assert.equal(first.body.user.displayName, "Mei Chen, who has a very", "long names from Apple are cut to 24 characters");
  const second = await cloud.call("POST", "/v1/auth/apple", { body: { identityToken: "good-token" } });
  assert.equal(second.body.user.id, first.body.user.id);
  assert.notEqual(second.body.token, first.body.token);
  const me = await cloud.call("GET", "/v1/me", { token: second.body.token });
  assert.deepEqual(me.body, { user: first.body.user, clubs: [] });

  const anonymous = await cloud.call("POST", "/v1/auth/apple", { body: { identityToken: "good-token-2".slice(0, 4) } });
  assert.deepEqual([anonymous.status, anonymous.body.error], [401, "invalid_token"]);
  const noName = makeCloud({ apple: () => ({ ok: true, identity: { subject: "s" } }) });
  const created = await noName.call("POST", "/v1/auth/apple", { body: { identityToken: "t" } });
  assert.match(created.body.user.displayName, /^Player \d{4}$/);
  for (const body of [{}, { identityToken: 5 }, { identityToken: "" }, { identityToken: "x".repeat(9000) }]) {
    assert.equal((await cloud.call("POST", "/v1/auth/apple", { body })).status, 400);
  }
  appleDown = true;
  const down = await cloud.call("POST", "/v1/auth/apple", { body: { identityToken: "good-token" } });
  assert.deepEqual([down.status, down.body.error], [503, "unavailable"]);
});

test("dev sign-in exists only with a DEV_AUTH_SECRET and checks it", async () => {
  const disabled = makeCloud({ devSecret: null });
  assert.equal((await disabled.call("POST", "/v1/auth/dev", { body: { secret: "", name: "A" } })).status, 404);
  const empty = makeCloud({ devSecret: "" });
  assert.equal((await empty.call("POST", "/v1/auth/dev", { body: { secret: "", name: "A" } })).status, 404);
  const cloud = makeCloud({ devSecret: "s3cret" });
  assert.equal((await cloud.call("POST", "/v1/auth/dev", { body: { secret: "s3cre", name: "A" } })).status, 401);
  assert.equal((await cloud.call("POST", "/v1/auth/dev", { body: { secret: "s3cret", name: "" } })).status, 400);
  assert.equal((await cloud.call("POST", "/v1/auth/dev", { body: { secret: "s3cret", name: "x".repeat(25) } })).status, 400);
  const a = await cloud.call("POST", "/v1/auth/dev", { body: { secret: "s3cret", name: "Test A" } });
  const again = await cloud.call("POST", "/v1/auth/dev", { body: { secret: "s3cret", name: "Test A" } });
  assert.equal(a.status, 200);
  assert.equal(again.body.user.id, a.body.user.id, "the same dev name is the same user");
});

test("sessions: a missing, malformed or unknown bearer token is 401", async () => {
  const cloud = makeCloud();
  const user = await cloud.signIn("Mei");
  assert.equal((await cloud.call("GET", "/v1/me", { token: user.token })).status, 200);
  const attempts: Record<string, string>[] = [{}, { authorization: "Bearer" }, { authorization: "Basic abc" }, { authorization: "Bearer short" }, { authorization: `Bearer ${"A".repeat(43)}` }];
  for (const headers of attempts) {
    const reply = await cloud.call("GET", "/v1/me", { headers });
    assert.deepEqual([reply.status, reply.body.error], [401, "unauthorized"], JSON.stringify(headers));
  }
  // Expired after 180 days.
  cloud.clock.now += 181 * 24 * 3600 * 1000;
  assert.equal((await cloud.call("GET", "/v1/me", { token: user.token })).status, 401);
});

test("rate limits: per IP on everything, per user once signed in, and on sign-in and invite codes", async () => {
  const cloud = makeCloud();
  const user = await cloud.signIn("Mei");
  cloud.limits.keys.length = 0;
  await cloud.call("GET", "/v1/me", { token: user.token });
  assert.deepEqual(cloud.limits.keys, ["ip:203.0.113.7", `user:${user.id}`]);
  cloud.limits.keys.length = 0;
  await cloud.call("POST", "/v1/clubs/join", { token: user.token, body: { inviteCode: "ABCD-EFGH" } });
  assert.deepEqual(cloud.limits.keys, ["ip:203.0.113.7", `user:${user.id}`, `join:${user.id}`]);
  cloud.limits.keys.length = 0;
  await cloud.call("POST", "/v1/auth/dev", { body: { secret: "test-secret", name: "X" } });
  assert.deepEqual(cloud.limits.keys, ["ip:203.0.113.7", "auth:203.0.113.7"]);
  cloud.limits.allow = false;
  const limited = await cloud.call("GET", "/v1/me", { token: user.token });
  assert.deepEqual([limited.status, limited.body.error, limited.headers.get("retry-after")], [429, "rate_limited", "60"]);
  assert.equal((await cloud.call("GET", "/health")).status, 200, "health is never limited");
});

test("bodies: too large is 413, not JSON is 400; responses are JSON and not cached", async () => {
  const cloud = makeCloud();
  const user = await cloud.signIn("Mei");
  const big = await cloud.call("POST", "/v1/clubs", { token: user.token, raw: JSON.stringify({ name: "x".repeat(20000) }) });
  assert.equal(big.status, 413);
  const bad = await cloud.call("POST", "/v1/clubs", { token: user.token, raw: "{not json" });
  assert.deepEqual([bad.status, bad.body.error], [400, "bad_json"]);
  const ok = await cloud.call("GET", "/v1/me", { token: user.token });
  assert.equal(ok.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(ok.headers.get("cache-control"), "no-store");
});

test("me: names are 1 to 24 characters, trimmed, without control characters; emoji are fine", async () => {
  const cloud = makeCloud();
  const user = await cloud.signIn("Mei");
  const rename = (displayName: unknown) => cloud.call("PATCH", "/v1/me", { token: user.token, body: { displayName } });
  for (const bad of ["", "   ", "x".repeat(25), 42, null, "a\u0000b", "bad‮name", undefined]) {
    assert.equal((await rename(bad)).status, 400, JSON.stringify(bad));
  }
  assert.equal((await rename("小明")).body.user.displayName, "小明");
  assert.equal((await rename("👩‍👩‍👧 Team")).body.user.displayName, "👩‍👩‍👧 Team");
  assert.equal((await rename("x".repeat(24))).status, 200);
  assert.equal((await cloud.call("DELETE", "/v1/me", { token: user.token })).status, 405);
});

test("devices: token, platform and environment are validated; removal is idempotent", async () => {
  const cloud = makeCloud();
  const user = await cloud.signIn("Mei");
  const add = (body: unknown) => cloud.call("POST", "/v1/devices", { token: user.token, body });
  const token = "0f".repeat(32);
  assert.equal((await add({ platform: "ios", token, environment: "sandbox" })).status, 204);
  assert.equal((await add({ platform: "ios", token: token.toUpperCase(), environment: "production" })).status, 204);
  assert.deepEqual(cloud.hub.service.devices(user.id), [{ platform: "ios", token, environment: "production" }]);
  for (const body of [
    { platform: "android", token, environment: "sandbox" },
    { platform: "ios", token: "xyz", environment: "sandbox" },
    { platform: "ios", token: "0f".repeat(8), environment: "sandbox" },
    { platform: "ios", token: `${token}0`, environment: "sandbox" },
    { platform: "ios", token, environment: "staging" },
    [],
  ]) {
    assert.equal((await add(body)).status, 400, JSON.stringify(body));
  }
  assert.equal((await cloud.call("DELETE", `/v1/devices/${token.toUpperCase()}`, { token: user.token })).status, 204);
  assert.deepEqual(cloud.hub.service.devices(user.id), []);
  assert.equal((await cloud.call("DELETE", `/v1/devices/${token}`, { token: user.token })).status, 204);
  assert.equal((await cloud.call("DELETE", "/v1/devices/not-hex", { token: user.token })).status, 400);
});

test("clubs over HTTP: create, join, read, leave; names are validated", async () => {
  const cloud = makeCloud();
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  for (const name of ["", "x".repeat(41), 7]) {
    assert.equal((await cloud.call("POST", "/v1/clubs", { token: mei.token, body: { name } })).status, 400);
  }
  const created = await cloud.call("POST", "/v1/clubs", { token: mei.token, body: { name: " Friday   Tractor " } });
  assert.equal(created.status, 200);
  const club = created.body.club;
  assert.equal(club.name, "Friday Tractor");
  assert.deepEqual(Object.keys(club).sort(), ["id", "inviteCode", "members", "name"]);
  const joined = await cloud.call("POST", "/v1/clubs/join", { token: lin.token, body: { inviteCode: club.inviteCode.toLowerCase() } });
  assert.deepEqual(joined.body.club.members, [{ id: mei.id, displayName: "Mei" }, { id: lin.id, displayName: "Lin" }]);
  assert.equal((await cloud.call("POST", "/v1/clubs/join", { token: lin.token, body: { inviteCode: 12345678 } })).status, 400);
  assert.equal((await cloud.call("POST", "/v1/clubs/join", { token: lin.token, body: { inviteCode: "WXYZ-WXYZ" } })).status, 404);
  const page = await cloud.call("GET", `/v1/clubs/${club.id}`, { token: lin.token });
  assert.deepEqual(page.body, { club: joined.body.club, games: [] });
  assert.equal((await cloud.call("GET", "/v1/clubs/c_not-an-id", { token: lin.token })).status, 404);
  assert.equal((await cloud.call("POST", `/v1/clubs/${club.id}/leave`, { token: lin.token })).status, 204);
  assert.equal((await cloud.call("GET", `/v1/clubs/${club.id}`, { token: lin.token })).status, 404);
  assert.equal((await cloud.call("GET", `/v1/clubs/${club.id}/leave`, { token: lin.token })).status, 405);
});

test("live: needs a session (token in the query) and a WebSocket upgrade, then goes to the room", async () => {
  const cloud = makeCloud();
  const mei = await cloud.signIn("Mei");
  const id = "g_0123456789abcdefghjkmnpqrs";
  const upgrade = { upgrade: "websocket" };
  assert.equal((await cloud.call("GET", `/v1/games/${id}/live`, { headers: upgrade })).status, 401);
  assert.equal((await cloud.call("GET", `/v1/games/${id}/live?token=${"A".repeat(43)}`, { headers: upgrade })).status, 401);
  assert.equal((await cloud.call("GET", `/v1/games/${id}/live?token=${mei.token}`)).status, 426);
  const ok = await cloud.call("GET", `/v1/games/${id}/live?token=${encodeURIComponent(mei.token)}`, { headers: upgrade });
  assert.deepEqual(ok.body, { live: id, userId: mei.id });
  assert.equal((await cloud.call("GET", `/v1/games/g_bad/live?token=${mei.token}`, { headers: upgrade })).status, 404);
});
