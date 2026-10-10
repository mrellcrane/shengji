// Apple Push Notification service (token-based auth). Signs the provider JWT (ES256) with the
// .p8 key through WebCrypto, caches it for 50 minutes (Apple accepts one for up to 60 and refuses
// refreshes more often than every 20), and posts alert pushes over HTTPS.
// https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns

import { base64Decode, base64urlEncode, utf8 } from "../auth/crypto.ts";
import type { CryptoKeyLike } from "../auth/crypto.ts";

export const APNS_TOPIC = "com.mrellcrane.shengji";
export const APNS_PRODUCTION = "https://api.push.apple.com";
export const APNS_SANDBOX = "https://api.sandbox.push.apple.com";
const TOKEN_LIFETIME_MS = 50 * 60 * 1000;
/** A push not delivered within a day (phone off) is dropped: by then it is stale. */
const EXPIRATION_SECONDS = 24 * 60 * 60;

export type PushEnvironment = "sandbox" | "production";

export interface ApnsCredentials {
  /** Contents of the AuthKey_XXXXXXXXXX.p8 file (PKCS #8 PEM). */
  keyP8: string;
  keyId: string;
  teamId: string;
}

/** The credentials from the Worker's secrets, or null when push is not configured. */
export function apnsCredentials(env: {
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APPLE_TEAM_ID?: string;
}): ApnsCredentials | null {
  const keyP8 = env.APNS_KEY_P8?.trim();
  const keyId = env.APNS_KEY_ID?.trim();
  const teamId = env.APPLE_TEAM_ID?.trim();
  if (!keyP8 || !keyId || !teamId) return null;
  return { keyP8, keyId, teamId };
}

export interface PushMessage {
  /** Device token, lowercase hex. */
  token: string;
  environment: PushEnvironment;
  title: string;
  body: string;
  /** Number of games where it is the recipient's turn. */
  badge: number;
  gameId: string;
}

export type PushResult =
  | { ok: true }
  | {
      ok: false;
      status: number;
      reason: string;
      /** APNs says this token will never work again: forget the device. */
      unregistered: boolean;
    };

export interface ApnsClient {
  send(message: PushMessage): Promise<PushResult>;
  /** The current provider token (exposed for tests). */
  providerToken(): Promise<string>;
}

/** The PKCS #8 DER bytes inside a PEM .p8 file (or bare base64). */
export function p8KeyBytes(pem: string): Uint8Array<ArrayBuffer> | null {
  const body = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\\n/g, "\n");
  const bytes = base64Decode(body);
  return bytes !== null && bytes.length > 0 ? bytes : null;
}

/** The JSON body APNs receives. */
export function apnsPayload(message: PushMessage): Record<string, unknown> {
  return {
    aps: {
      alert: { title: message.title, body: message.body },
      badge: message.badge,
      sound: "default",
      "thread-id": message.gameId,
    },
    gameId: message.gameId,
  };
}

const UNREGISTERED_REASONS = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"]);

export function createApnsClient(
  credentials: ApnsCredentials,
  deps: { fetch?: typeof fetch; now?: () => number } = {},
): ApnsClient {
  const fetchFn = deps.fetch ?? ((input, init) => fetch(input, init));
  const now = deps.now ?? Date.now;
  let keyPromise: Promise<CryptoKeyLike> | null = null;
  let cached: { token: string; at: number } | null = null;

  function signingKey(): Promise<CryptoKeyLike> {
    if (keyPromise === null) {
      const der = p8KeyBytes(credentials.keyP8);
      keyPromise =
        der === null
          ? Promise.reject(new Error("APNS_KEY_P8 is not a PEM private key"))
          : crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
      keyPromise.catch(() => {
        keyPromise = null;
      });
    }
    return keyPromise;
  }

  async function providerToken(): Promise<string> {
    const at = now();
    if (cached !== null && at - cached.at < TOKEN_LIFETIME_MS) return cached.token;
    const header = base64urlEncode(utf8(JSON.stringify({ alg: "ES256", kid: credentials.keyId })));
    const claims = base64urlEncode(utf8(JSON.stringify({ iss: credentials.teamId, iat: Math.floor(at / 1000) })));
    const input = `${header}.${claims}`;
    // WebCrypto ECDSA signatures are r || s (IEEE P1363), exactly what JWS ES256 wants.
    const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await signingKey(), utf8(input));
    const token = `${input}.${base64urlEncode(new Uint8Array(signature))}`;
    cached = { token, at };
    return token;
  }

  async function send(message: PushMessage): Promise<PushResult> {
    const host = message.environment === "production" ? APNS_PRODUCTION : APNS_SANDBOX;
    let response: Response;
    try {
      response = await fetchFn(`${host}/3/device/${message.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${await providerToken()}`,
          "apns-topic": APNS_TOPIC,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": message.gameId,
          "apns-expiration": String(Math.floor(now() / 1000) + EXPIRATION_SECONDS),
          "content-type": "application/json",
        },
        body: JSON.stringify(apnsPayload(message)),
      });
    } catch (error) {
      return { ok: false, status: 0, reason: `network: ${String(error)}`, unregistered: false };
    }
    if (response.status === 200) return { ok: true };
    let reason = `HTTP ${response.status}`;
    try {
      const body = (await response.json()) as { reason?: unknown };
      if (typeof body.reason === "string") reason = body.reason;
    } catch {
      // No JSON body.
    }
    if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") cached = null;
    const unregistered = response.status === 410 || UNREGISTERED_REASONS.has(reason);
    return { ok: false, status: response.status, reason, unregistered };
  }

  return { send, providerToken };
}
