// Sign in with Apple token verification (RS256 against a JWKS), the JWKS cache, and the small
// crypto helpers behind sessions and invite codes.

import assert from "node:assert/strict";
import { test } from "node:test";
import { APPLE_AUDIENCE, APPLE_ISSUER, appleKeySource, verifyAppleIdentityToken } from "../src/auth/apple.ts";
import type { KeySource, RsaJwk } from "../src/auth/apple.ts";
import {
  base64urlDecode,
  base64urlEncode,
  constantTimeEqual,
  formatInviteCode,
  INVITE_ALPHABET,
  isIdShape,
  isSessionTokenShape,
  newId,
  newInviteCode,
  newSessionToken,
  normalizeInviteCode,
  sessionTokenHash,
  utf8,
} from "../src/auth/crypto.ts";
import type { CryptoKeyLike } from "../src/auth/crypto.ts";

type KeyPair = { privateKey: CryptoKeyLike; publicKey: CryptoKeyLike };

async function rsaKey(): Promise<KeyPair> {
  return (await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  )) as KeyPair;
}

async function jwkOf(pair: KeyPair, kid: string): Promise<RsaJwk> {
  const jwk = (await crypto.subtle.exportKey("jwk", pair.publicKey)) as { n: string; e: string };
  return { kty: "RSA", kid, alg: "RS256", use: "sig", n: jwk.n, e: jwk.e };
}

const encode = (value: unknown) => base64urlEncode(utf8(JSON.stringify(value)));

async function sign(pair: KeyPair, header: Record<string, unknown>, payload: Record<string, unknown>): Promise<string> {
  const input = `${encode(header)}.${encode(payload)}`;
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", pair.privateKey, utf8(input));
  return `${input}.${base64urlEncode(new Uint8Array(signature))}`;
}

const NOW = 1_790_000_000;

function claims(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { iss: APPLE_ISSUER, aud: APPLE_AUDIENCE, exp: NOW + 600, iat: NOW - 10, sub: "001234.abcdef.0001", ...overrides };
}

function staticKeys(keys: RsaJwk[]): KeySource & { calls: boolean[] } {
  const source = {
    calls: [] as boolean[],
    async keys(refresh: boolean) {
      source.calls.push(refresh);
      return keys;
    },
  };
  return source;
}

const pairs = Promise.all([rsaKey(), rsaKey()]);

test("a valid Apple identity token is accepted and yields its subject", async () => {
  const [apple] = await pairs;
  const keys = staticKeys([await jwkOf(apple, "k1")]);
  const token = await sign(apple, { alg: "RS256", kid: "k1" }, claims());
  const result = await verifyAppleIdentityToken(token, { keys, nowSeconds: NOW });
  assert.deepEqual(result, { ok: true, identity: { subject: "001234.abcdef.0001" } });
  // aud may also be an array that contains the bundle id.
  const arrayAud = await sign(apple, { alg: "RS256", kid: "k1" }, claims({ aud: ["other", APPLE_AUDIENCE] }));
  assert.equal((await verifyAppleIdentityToken(arrayAud, { keys, nowSeconds: NOW })).ok, true);
});

test("wrong issuer, audience, expiry, future iat, missing subject and bad signatures are refused", async () => {
  const [apple, attacker] = await pairs;
  const keys = staticKeys([await jwkOf(apple, "k1")]);
  const header = { alg: "RS256", kid: "k1" };
  const cases: [string, Promise<string>][] = [
    ["wrong issuer", sign(apple, header, claims({ iss: "https://evil.example" }))],
    ["wrong audience", sign(apple, header, claims({ aud: "com.someone.else" }))],
    ["expired", sign(apple, header, claims({ exp: NOW - 61 }))],
    ["issued in the future", sign(apple, header, claims({ iat: NOW + 3600 }))],
    ["no subject", sign(apple, header, claims({ sub: "" }))],
    ["no exp", sign(apple, header, claims({ exp: undefined }))],
    ["bad signature", sign(attacker, header, claims())],
  ];
  for (const [label, token] of cases) {
    const result = await verifyAppleIdentityToken(await token, { keys, nowSeconds: NOW });
    assert.equal(result.ok, false, label);
  }
  // A token signed for a slightly earlier time is still fine within the clock skew.
  const skewed = await sign(apple, header, claims({ exp: NOW - 30 }));
  assert.equal((await verifyAppleIdentityToken(skewed, { keys, nowSeconds: NOW })).ok, true);
});

test("tampered payloads, other algorithms and malformed tokens are refused", async () => {
  const [apple] = await pairs;
  const keys = staticKeys([await jwkOf(apple, "k1")]);
  const good = await sign(apple, { alg: "RS256", kid: "k1" }, claims());
  const [h, , s] = good.split(".");
  const tampered = `${h}.${encode(claims({ sub: "someone-else" }))}.${s}`;
  const none = `${encode({ alg: "none", kid: "k1" })}.${encode(claims())}.`;
  const hs256 = `${encode({ alg: "HS256", kid: "k1" })}.${encode(claims())}.${s}`;
  for (const token of [tampered, none, hs256, "", "a.b", "a.b.c.d", "!!!.###.$$$", "x".repeat(9000), `${h}.e30.${s}`]) {
    const result = await verifyAppleIdentityToken(token, { keys, nowSeconds: NOW });
    assert.equal(result.ok, false, token.slice(0, 40));
  }
});

test("an unknown key id triggers one refresh of the key set (Apple rotates keys)", async () => {
  const [apple, rotated] = await pairs;
  let served = [await jwkOf(apple, "old")];
  const source = {
    calls: [] as boolean[],
    async keys(refresh: boolean) {
      source.calls.push(refresh);
      return served;
    },
  };
  const token = await sign(rotated, { alg: "RS256", kid: "new" }, claims());
  assert.deepEqual(await verifyAppleIdentityToken(token, { keys: source, nowSeconds: NOW }), {
    ok: false,
    reason: "unknown key",
  });
  assert.deepEqual(source.calls, [false, true]);
  served = [await jwkOf(apple, "old"), await jwkOf(rotated, "new")];
  assert.equal((await verifyAppleIdentityToken(token, { keys: source, nowSeconds: NOW })).ok, true);
});

test("Apple's key set is fetched once, cached, refreshed at most once a minute, and kept if Apple is down", async () => {
  const [apple] = await pairs;
  const jwk = await jwkOf(apple, "k1");
  let now = 0;
  let fetches = 0;
  let down = false;
  const fakeFetch = (async (input: string | URL | Request) => {
    fetches++;
    assert.equal(String(input), "https://appleid.apple.com/auth/keys");
    if (down) throw new Error("network down");
    return Response.json({ keys: [jwk, { kty: "EC", kid: "ignored" }] });
  }) as typeof fetch;
  const source = appleKeySource(fakeFetch, () => now);
  assert.deepEqual(await source.keys(false), [jwk]);
  assert.deepEqual(await source.keys(false), [jwk]);
  assert.equal(fetches, 1);
  // A refresh within the first minute is not allowed to hit Apple again.
  await source.keys(true);
  assert.equal(fetches, 1);
  now = 61_000;
  await source.keys(true);
  assert.equal(fetches, 2);
  // After the cache expires, a failed fetch falls back to the keys we have.
  now = 61_000 + 3_600_001;
  down = true;
  assert.deepEqual(await source.keys(false), [jwk]);
  assert.equal(fetches, 3);
  // With nothing cached, a failure is an error (the API answers 503).
  const empty = appleKeySource((async () => {
    throw new Error("down");
  }) as typeof fetch, () => 0);
  await assert.rejects(empty.keys(false));
});

test("session tokens are 32 random bytes, stored only as a SHA-256 hash", async () => {
  const tokens = new Set(Array.from({ length: 200 }, () => newSessionToken()));
  assert.equal(tokens.size, 200);
  for (const token of tokens) {
    assert.ok(isSessionTokenShape(token));
    assert.equal(base64urlDecode(token)?.length, 32);
  }
  const token = [...tokens][0];
  const hash = await sessionTokenHash(token);
  assert.match(hash, /^[0-9a-f]{64}$/);
  assert.equal(await sessionTokenHash(token), hash);
  assert.ok(!hash.includes(token));
  for (const bad of ["", "short", `${token}x`, `${token.slice(0, 42)}!`, `${token.slice(0, 42)} `]) {
    assert.equal(isSessionTokenShape(bad), false, bad);
  }
});

test("constant-time comparison and base64url helpers", async () => {
  assert.equal(await constantTimeEqual("secret", "secret"), true);
  assert.equal(await constantTimeEqual("secret", "secreT"), false);
  assert.equal(await constantTimeEqual("secret", "secret-but-longer"), false);
  assert.equal(await constantTimeEqual("", ""), true);
  for (let n = 0; n < 40; n++) {
    const bytes = crypto.getRandomValues(new Uint8Array(n));
    assert.deepEqual(base64urlDecode(base64urlEncode(bytes)), bytes);
  }
  assert.equal(base64urlDecode("a+b/"), null);
  assert.equal(base64urlDecode("abcde"), null);
});

test("ids and invite codes", () => {
  const ids = Array.from({ length: 500 }, () => newId("g"));
  assert.equal(new Set(ids).size, 500);
  for (const id of ids) assert.ok(isIdShape(id, "g") && !isIdShape(id, "u"));
  assert.equal(isIdShape("g_short", "g"), false);
  assert.equal(isIdShape(`g_${"A".repeat(26)}`, "g"), false);

  for (let i = 0; i < 500; i++) {
    const code = newInviteCode();
    assert.equal(code.length, 8);
    for (const ch of code) assert.ok(INVITE_ALPHABET.includes(ch));
    const shown = formatInviteCode(code);
    assert.match(shown, /^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    assert.equal(normalizeInviteCode(shown), code);
    assert.equal(normalizeInviteCode(shown.toLowerCase()), code);
    assert.equal(normalizeInviteCode(code.toLowerCase()), code);
    assert.equal(normalizeInviteCode(` ${shown.slice(0, 2)} ${shown.slice(2)} `), code);
  }
  for (const ambiguous of "ILO01") assert.ok(!INVITE_ALPHABET.includes(ambiguous));
  for (const bad of ["", "ABCD-EFG", "ABCD-EFGHJ", "ABCD-EFG1", "ABCD_EFGH", "x".repeat(100)]) {
    assert.equal(normalizeInviteCode(bad), null, bad);
  }
});
