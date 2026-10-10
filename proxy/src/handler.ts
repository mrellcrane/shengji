// POST /coach: validate, rate-limit, then stream Claude's reply back to the app as simple SSE.
// Kept free of the Anthropic SDK and Workers globals so it can be unit-tested in Node.

import { buildMessages, LIMITS, parseCoachRequest, RequestError } from "./protocol.ts";
import type { ApiMessage } from "./protocol.ts";

/** A chunk of reply text from the model. */
export interface UpstreamText {
  type: "text";
  text: string;
}

export interface UpstreamStream {
  events: AsyncIterable<UpstreamText>;
  /** Resolves once the reply is complete. */
  finish(): Promise<{ stopReason: string | null }>;
  abort(): void;
}

export interface Limiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface CoachDeps {
  deviceLimiter: Limiter;
  ipLimiter: Limiter;
  startStream(messages: ApiMessage[]): UpstreamStream;
  /** Maps an upstream failure to a learner-facing code and message. */
  describeError(error: unknown): { code: string; message: string };
  log?(message: string): void;
  waitUntil?(promise: Promise<unknown>): void;
}

/** Events the app receives, one JSON object per SSE `data:` line. */
export type CoachEvent =
  | { type: "text"; text: string }
  | { type: "done"; stopReason: string }
  | { type: "error"; code: string; message: string };

const SSE_HEADERS = {
  "content-type": "text/event-stream; charset=utf-8",
  "cache-control": "no-cache, no-store",
  "x-content-type-options": "nosniff",
};

export const MESSAGES = {
  rateLimited: "You're asking faster than the coach can keep up. Wait a minute and try again.",
  refusal: "I can't help with that one. Ask me anything about the game.",
  tooLarge: "That message is too long for the coach.",
  badJson: "The app sent something the coach couldn't read.",
} as const;

function jsonError(status: number, code: string, message: string, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify({ error: code, message }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });
}

export async function handleCoach(request: Request, deps: CoachDeps): Promise<Response> {
  if (request.method !== "POST") {
    return jsonError(405, "method_not_allowed", "Use POST.", { allow: "POST" });
  }

  const declared = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > LIMITS.maxBodyBytes) {
    return jsonError(413, "too_large", MESSAGES.tooLarge);
  }
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > LIMITS.maxBodyBytes) {
    return jsonError(413, "too_large", MESSAGES.tooLarge);
  }

  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return jsonError(400, "bad_json", MESSAGES.badJson);
  }

  let coachRequest;
  try {
    coachRequest = parseCoachRequest(body);
  } catch (error) {
    if (error instanceof RequestError) return jsonError(error.status, error.code, error.message);
    throw error;
  }

  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  const [ipOutcome, deviceOutcome] = await Promise.all([
    deps.ipLimiter.limit({ key: `ip:${ip}` }),
    deps.deviceLimiter.limit({ key: `device:${coachRequest.deviceId}` }),
  ]);
  if (!ipOutcome.success || !deviceOutcome.success) {
    return jsonError(429, "rate_limited", MESSAGES.rateLimited, { "retry-after": "60" });
  }

  let upstream: UpstreamStream;
  try {
    upstream = deps.startStream(buildMessages(coachRequest));
  } catch (error) {
    const described = deps.describeError(error);
    deps.log?.(`coach: failed to start stream: ${String(error)}`);
    return jsonError(502, described.code, described.message);
  }

  const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
  const writer = writable.getWriter();
  const encoder = new TextEncoder();
  const send = (event: CoachEvent) => writer.write(encoder.encode(`data: ${JSON.stringify(event)}\n\n`));

  const pump = (async () => {
    try {
      // An SSE comment flushes the headers right away, before the model's first token.
      await writer.write(encoder.encode(": coach\n\n"));
      for await (const chunk of upstream.events) {
        if (chunk.text.length > 0) await send({ type: "text", text: chunk.text });
      }
      const { stopReason } = await upstream.finish();
      if (stopReason === "refusal") {
        await send({ type: "error", code: "refusal", message: MESSAGES.refusal });
      } else {
        await send({ type: "done", stopReason: stopReason ?? "end_turn" });
      }
    } catch (error) {
      upstream.abort();
      const described = deps.describeError(error);
      deps.log?.(`coach: stream failed (${described.code}): ${String(error)}`);
      try {
        await send({ type: "error", ...described });
      } catch {
        // The app already went away.
      }
    } finally {
      try {
        await writer.close();
      } catch {
        // Already closed or errored.
      }
    }
  })();
  deps.waitUntil?.(pump);

  return new Response(readable, { status: 200, headers: SSE_HEADERS });
}
