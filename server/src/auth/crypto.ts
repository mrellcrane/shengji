// Small WebCrypto helpers shared by auth, sessions and push (Workers and Node 22 both provide
// `crypto.subtle` and `crypto.getRandomValues`).

import { randomInt } from "../engine/shuffle.ts";

const encoder = new TextEncoder();

/** A WebCrypto key (named this way so both the Workers and the Node type definitions accept it). */
export type CryptoKeyLike = Awaited<ReturnType<typeof crypto.subtle.importKey>>;

export function utf8(text: string): Uint8Array<ArrayBuffer> {
  return encoder.encode(text) as Uint8Array<ArrayBuffer>;
}

export function randomBytes(count: number): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(new ArrayBuffer(count));
  crypto.getRandomValues(bytes);
  return bytes;
}

export function base64urlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const BASE64URL = /^[A-Za-z0-9_-]*$/;

/** Decodes base64url (no padding needed); null if the text is not base64url. */
export function base64urlDecode(text: string): Uint8Array<ArrayBuffer> | null {
  if (!BASE64URL.test(text) || text.length % 4 === 1) return null;
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  try {
    const binary = atob(padded);
    const bytes = new Uint8Array(new ArrayBuffer(binary.length));
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

/** Decodes standard base64 (as in PEM files), ignoring whitespace; null if invalid. */
export function base64Decode(text: string): Uint8Array<ArrayBuffer> | null {
  const clean = text.replace(/\s+/g, "");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(clean)) return null;
  try {
    const binary = atob(clean);
    const bytes = new Uint8Array(new ArrayBuffer(binary.length));
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  } catch {
    return null;
  }
}

export function hex(bytes: Uint8Array): string {
  let out = "";
  for (const byte of bytes) out += byte.toString(16).padStart(2, "0");
  return out;
}

export async function sha256(data: string | Uint8Array<ArrayBuffer>): Promise<Uint8Array<ArrayBuffer>> {
  const input = typeof data === "string" ? utf8(data) : data;
  return new Uint8Array(await crypto.subtle.digest("SHA-256", input));
}

export async function sha256Hex(data: string): Promise<string> {
  return hex(await sha256(data));
}

/**
 * Compares two secrets in time that does not depend on where they differ (or on their lengths):
 * both are hashed first, then every byte of the digests is compared.
 */
export async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const [x, y] = await Promise.all([sha256(a), sha256(b)]);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
  return diff === 0;
}

// MARK: Sessions

export const SESSION_TOKEN_BYTES = 32;
const SESSION_TOKEN = /^[A-Za-z0-9_-]{43}$/;

/** A new session token: 32 random bytes, base64url (43 characters). Only its hash is stored. */
export function newSessionToken(): string {
  return base64urlEncode(randomBytes(SESSION_TOKEN_BYTES));
}

/** True if `token` has the shape of a session token (checked before hashing or any lookup). */
export function isSessionTokenShape(token: string): boolean {
  return SESSION_TOKEN.test(token);
}

/** What the Hub stores for a session token. */
export function sessionTokenHash(token: string): Promise<string> {
  return sha256Hex(token);
}

// MARK: Ids and invite codes

const ID_ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz";

/** A random id like "g_7f3k...": `prefix` + "_" + 26 characters (130 random bits). */
export function newId(prefix: "u" | "c" | "g"): string {
  let out = `${prefix}_`;
  for (let i = 0; i < 26; i++) out += ID_ALPHABET[randomInt(ID_ALPHABET.length)];
  return out;
}

const ID_SHAPE = /^[ucg]_[0-9a-z]{26}$/;

export function isIdShape(value: string, prefix: "u" | "c" | "g"): boolean {
  return ID_SHAPE.test(value) && value.startsWith(`${prefix}_`);
}

/** Invite code letters: no I, L, O, 0 or 1, which are easy to misread. */
export const INVITE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const INVITE_LENGTH = 8;

/** A new invite code in stored form: 8 characters, no dash. */
export function newInviteCode(): string {
  let out = "";
  for (let i = 0; i < INVITE_LENGTH; i++) out += INVITE_ALPHABET[randomInt(INVITE_ALPHABET.length)];
  return out;
}

/** "ABCDEFGH" -> "ABCD-EFGH". */
export function formatInviteCode(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

/**
 * The stored form of what someone typed: case, dashes and spaces ignored. Null if it cannot be an
 * invite code.
 */
export function normalizeInviteCode(input: string): string | null {
  if (input.length > 32) return null;
  const code = input.toUpperCase().replace(/[\s-]/g, "");
  if (code.length !== INVITE_LENGTH) return null;
  for (const ch of code) if (!INVITE_ALPHABET.includes(ch)) return null;
  return code;
}
