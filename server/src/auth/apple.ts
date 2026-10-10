// Sign in with Apple: verifies the identity token (a JWT) the app gets from Apple.
// RS256 signature against Apple's published keys (JWKS, cached), then iss, aud and exp.
// https://developer.apple.com/documentation/sign_in_with_apple/verifying_a_user

import { base64urlDecode, utf8 } from "./crypto.ts";
import type { CryptoKeyLike } from "./crypto.ts";

export const APPLE_ISSUER = "https://appleid.apple.com";
export const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
/** The app's bundle id: the `aud` of its identity tokens. */
export const APPLE_AUDIENCE = "com.mrellcrane.shengji";

/** Accepted clock difference between Apple and us, in seconds. */
const CLOCK_SKEW_SECONDS = 60;
const MAX_TOKEN_LENGTH = 8192;

export interface RsaJwk {
  kty: string;
  kid: string;
  alg?: string;
  use?: string;
  n: string;
  e: string;
}

/** Where the signing keys come from (Apple's JWKS in production, a fake in tests). */
export interface KeySource {
  /** The current keys; `refresh` asks for a fresh copy (an unknown `kid` may be a rotated key). */
  keys(refresh: boolean): Promise<RsaJwk[]>;
}

export interface AppleIdentity {
  /** Apple's stable user identifier for this app. */
  subject: string;
}

export type VerifyResult = { ok: true; identity: AppleIdentity } | { ok: false; reason: string };

function isRsaJwk(value: unknown): value is RsaJwk {
  if (typeof value !== "object" || value === null) return false;
  const v = value as Record<string, unknown>;
  return v.kty === "RSA" && typeof v.kid === "string" && typeof v.n === "string" && typeof v.e === "string";
}

/**
 * Apple's JWKS, cached for `ttlMs`. A refresh (for an unknown kid) is allowed at most once per
 * `minRefreshMs`, so made-up kids cannot make us hammer Apple.
 */
export function appleKeySource(
  fetchFn: typeof fetch = (input, init) => fetch(input, init),
  now: () => number = Date.now,
  ttlMs = 60 * 60 * 1000,
  minRefreshMs = 60 * 1000,
): KeySource {
  let cached: { keys: RsaJwk[]; at: number } | null = null;
  let inflight: Promise<RsaJwk[]> | null = null;

  async function load(): Promise<RsaJwk[]> {
    const response = await fetchFn(APPLE_JWKS_URL, { headers: { accept: "application/json" } });
    if (!response.ok) throw new Error(`Apple JWKS request failed with ${response.status}`);
    const body = (await response.json()) as { keys?: unknown };
    const keys = Array.isArray(body.keys) ? body.keys.filter(isRsaJwk) : [];
    if (keys.length === 0) throw new Error("Apple JWKS has no RSA keys");
    cached = { keys, at: now() };
    return keys;
  }

  return {
    async keys(refresh) {
      const age = cached === null ? Infinity : now() - cached.at;
      const stale = age > ttlMs || (refresh && age > minRefreshMs);
      if (cached !== null && !stale) return cached.keys;
      if (inflight === null) {
        inflight = load().finally(() => {
          inflight = null;
        });
      }
      try {
        return await inflight;
      } catch (error) {
        // Apple unreachable: keep using the keys we have, if any.
        if (cached !== null) return cached.keys;
        throw error;
      }
    },
  };
}

function decodeJsonPart(part: string): Record<string, unknown> | null {
  const bytes = base64urlDecode(part);
  if (bytes === null) return null;
  try {
    const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
    return typeof value === "object" && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

const importedKeys = new Map<string, Promise<CryptoKeyLike>>();

function importKey(jwk: RsaJwk): Promise<CryptoKeyLike> {
  const cacheKey = `${jwk.kid}:${jwk.n}:${jwk.e}`;
  let key = importedKeys.get(cacheKey);
  if (key === undefined) {
    if (importedKeys.size > 32) importedKeys.clear();
    key = crypto.subtle.importKey(
      "jwk",
      { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"],
    );
    importedKeys.set(cacheKey, key);
    key.catch(() => importedKeys.delete(cacheKey));
  }
  return key;
}

/**
 * Verifies a Sign in with Apple identity token. `nowSeconds` is the current Unix time.
 * Never throws for a bad token; throws only if the keys cannot be fetched at all.
 */
export async function verifyAppleIdentityToken(
  token: string,
  options: { keys: KeySource; audience?: string; nowSeconds: number },
): Promise<VerifyResult> {
  const audience = options.audience ?? APPLE_AUDIENCE;
  if (typeof token !== "string" || token.length === 0 || token.length > MAX_TOKEN_LENGTH) {
    return { ok: false, reason: "malformed" };
  }
  const parts = token.split(".");
  if (parts.length !== 3) return { ok: false, reason: "malformed" };
  const header = decodeJsonPart(parts[0]);
  const payload = decodeJsonPart(parts[1]);
  const signature = base64urlDecode(parts[2]);
  if (header === null || payload === null || signature === null) return { ok: false, reason: "malformed" };
  if (header.alg !== "RS256" || typeof header.kid !== "string") return { ok: false, reason: "unsupported algorithm" };

  let jwk = (await options.keys.keys(false)).find((k) => k.kid === header.kid);
  if (jwk === undefined) jwk = (await options.keys.keys(true)).find((k) => k.kid === header.kid);
  if (jwk === undefined) return { ok: false, reason: "unknown key" };

  let valid = false;
  try {
    const key = await importKey(jwk);
    valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, utf8(`${parts[0]}.${parts[1]}`));
  } catch {
    valid = false;
  }
  if (!valid) return { ok: false, reason: "bad signature" };

  if (payload.iss !== APPLE_ISSUER) return { ok: false, reason: "wrong issuer" };
  const aud = payload.aud;
  const audiences = Array.isArray(aud) ? aud : [aud];
  if (!audiences.includes(audience)) return { ok: false, reason: "wrong audience" };
  const now = options.nowSeconds;
  if (typeof payload.exp !== "number" || payload.exp + CLOCK_SKEW_SECONDS <= now) {
    return { ok: false, reason: "expired" };
  }
  if (typeof payload.iat === "number" && payload.iat - CLOCK_SKEW_SECONDS > now) {
    return { ok: false, reason: "issued in the future" };
  }
  const sub = payload.sub;
  if (typeof sub !== "string" || sub.length === 0 || sub.length > 255) return { ok: false, reason: "no subject" };
  return { ok: true, identity: { subject: sub } };
}
