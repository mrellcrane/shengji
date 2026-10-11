import assert from "node:assert/strict";
import { test } from "node:test";
import { handleCoach, MESSAGES } from "../src/handler.ts";
import type { CoachDeps, UpstreamStream } from "../src/handler.ts";
import { buildMessages, LIMITS, parseCoachRequest, RequestError } from "../src/protocol.ts";
import type { ApiMessage } from "../src/protocol.ts";
import { SYSTEM_PROMPT } from "../src/prompt.ts";

const okLimiter = { limit: async () => ({ success: true }) };
const noLimiter = { limit: async () => ({ success: false }) };

function fakeStream(chunks: string[], stopReason: string | null = "end_turn", failAfter?: number): UpstreamStream & { aborted: boolean } {
  const s = {
    aborted: false,
    events: (async function* () {
      for (let i = 0; i < chunks.length; i++) {
        if (failAfter !== undefined && i === failAfter) throw new Error("upstream exploded");
        yield { type: "text" as const, text: chunks[i] };
      }
    })(),
    finish: async () => ({ stopReason }),
    abort: () => {
      s.aborted = true;
    },
  };
  return s;
}

function deps(overrides: Partial<CoachDeps> = {}, stream?: UpstreamStream): CoachDeps & { sent: ApiMessage[][] } {
  const sent: ApiMessage[][] = [];
  return {
    sent,
    deviceLimiter: okLimiter,
    ipLimiter: okLimiter,
    startStream: (messages) => {
      sent.push(messages);
      return stream ?? fakeStream(["Hi"]);
    },
    describeError: () => ({ code: "unavailable", message: "down" }),
    ...overrides,
  };
}

function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("https://coach.example/coach", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": "1.2.3.4", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const validBody = {
  deviceId: "device-1234",
  turns: [{ role: "user", text: "Why can't I play 9♣ here?", context: "Phase: playing\nTrump: ♥, rank 2" }],
};

async function events(response: Response): Promise<Array<Record<string, unknown>>> {
  const text = await response.text();
  return text
    .split("\n\n")
    .filter((block) => block.startsWith("data: "))
    .map((block) => JSON.parse(block.slice(6)));
}

test("parseCoachRequest accepts a valid conversation", () => {
  const parsed = parseCoachRequest({
    deviceId: "abcdefgh",
    turns: [
      { role: "user", text: "What is a tractor?" },
      { role: "assistant", text: "Two or more consecutive pairs." },
      { role: "user", text: "Like 7799?", context: "rank 8" },
    ],
  });
  assert.equal(parsed.turns.length, 3);
  assert.equal(parsed.turns[2].context, "rank 8");
});

test("parseCoachRequest rejects bad shapes", () => {
  const bad: unknown[] = [
    null,
    [],
    { deviceId: "short", turns: [{ role: "user", text: "hi" }] },
    { deviceId: "abcdefgh", turns: [] },
    { deviceId: "abcdefgh", turns: [{ role: "assistant", text: "hi" }] },
    { deviceId: "abcdefgh", turns: [{ role: "user", text: "hi" }, { role: "assistant", text: "yo" }] },
    { deviceId: "abcdefgh", turns: [{ role: "user", text: "   " }] },
    { deviceId: "abcdefgh", turns: [{ role: "user", text: "x".repeat(LIMITS.maxUserChars + 1) }] },
    { deviceId: "abcdefgh", turns: [{ role: "user", text: "hi", context: "x".repeat(LIMITS.maxContextChars + 1) }] },
    { deviceId: "abcdefgh", turns: [{ role: "user", text: "hi" }, { role: "assistant", text: "yo", context: "nope" }, { role: "user", text: "ok" }] },
    { deviceId: "abcdefgh", turns: Array.from({ length: LIMITS.maxTurns + 1 }, (_, i) => ({ role: i % 2 ? "assistant" : "user", text: "t" })) },
  ];
  for (const body of bad) {
    assert.throws(() => parseCoachRequest(body), RequestError, JSON.stringify(body)?.slice(0, 80));
  }
});

test("buildMessages wraps context in a table_state block and keeps history stable", () => {
  const request = parseCoachRequest({
    deviceId: "abcdefgh",
    turns: [
      { role: "user", text: "First?", context: "A" },
      { role: "assistant", text: "Answer." },
      { role: "user", text: "Second?", context: "B" },
    ],
  });
  const messages = buildMessages(request);
  assert.equal(messages[0].content, "<table_state>\nA\n</table_state>\n\nFirst?");
  assert.equal(messages[1].content, "Answer.");
  assert.equal(messages[2].content, "<table_state>\nB\n</table_state>\n\nSecond?");
  // Same input, same bytes: the history is append-only across requests.
  assert.deepEqual(buildMessages(request), messages);
});

test("rejects non-POST", async () => {
  const response = await handleCoach(new Request("https://coach.example/coach"), deps());
  assert.equal(response.status, 405);
});

test("rejects oversized bodies", async () => {
  const response = await handleCoach(post("x".repeat(LIMITS.maxBodyBytes + 10)), deps());
  assert.equal(response.status, 413);
});

test("rejects invalid JSON and invalid requests with a message", async () => {
  const badJson = await handleCoach(post("{nope"), deps());
  assert.equal(badJson.status, 400);
  assert.equal((await badJson.json()).message, MESSAGES.badJson);

  const invalid = await handleCoach(post({ deviceId: "x", turns: [] }), deps());
  assert.equal(invalid.status, 400);
  assert.equal((await invalid.json()).error, "bad_device_id");
});

test("rate limits by device and by IP", async () => {
  const byDevice = await handleCoach(post(validBody), deps({ deviceLimiter: noLimiter }));
  assert.equal(byDevice.status, 429);
  assert.equal(byDevice.headers.get("retry-after"), "60");
  const byIp = await handleCoach(post(validBody), deps({ ipLimiter: noLimiter }));
  assert.equal(byIp.status, 429);
});

test("limiter keys are namespaced and use the device id and client IP", async () => {
  const keys: string[] = [];
  const recorder = { limit: async ({ key }: { key: string }) => (keys.push(key), { success: true }) };
  const response = await handleCoach(post(validBody), deps({ deviceLimiter: recorder, ipLimiter: recorder }));
  await response.text();
  assert.deepEqual(keys.sort(), ["device:device-1234", "ip:1.2.3.4"]);
});

test("streams text then done", async () => {
  const d = deps({}, fakeStream(["You must ", "follow suit."]));
  const response = await handleCoach(post(validBody), d);
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /text\/event-stream/);
  const got = await events(response);
  assert.deepEqual(got, [
    { type: "text", text: "You must " },
    { type: "text", text: "follow suit." },
    { type: "done", stopReason: "end_turn" },
  ]);
  assert.equal(d.sent.length, 1);
  assert.match(d.sent[0][0].content, /<table_state>/);
});

test("a refusal becomes a friendly error event", async () => {
  const response = await handleCoach(post(validBody), deps({}, fakeStream([], "refusal")));
  const got = await events(response);
  assert.deepEqual(got, [{ type: "error", code: "refusal", message: MESSAGES.refusal }]);
});

test("an upstream failure mid-stream becomes an error event and aborts upstream", async () => {
  const stream = fakeStream(["Partial ", "never"], "end_turn", 1);
  const logs: string[] = [];
  const response = await handleCoach(post(validBody), deps({ log: (m) => logs.push(m) }, stream));
  const got = await events(response);
  assert.deepEqual(got, [
    { type: "text", text: "Partial " },
    { type: "error", code: "unavailable", message: "down" },
  ]);
  assert.equal(stream.aborted, true);
  assert.equal(logs.length, 1);
});

test("a failure to start the stream returns 502 JSON", async () => {
  const response = await handleCoach(
    post(validBody),
    deps({
      startStream: () => {
        throw new Error("no");
      },
    }),
  );
  assert.equal(response.status, 502);
  assert.equal((await response.json()).error, "unavailable");
});

test("system prompt stays free of em dashes and states the key thresholds", () => {
  assert.equal(SYSTEM_PROMPT.includes("—"), false);
  assert.match(SYSTEM_PROMPT, /80 to 115 = defenders take over/);
  // Bigger tables: 3 decks take over at 120.
  assert.match(SYSTEM_PROMPT, /# Bigger tables \(6 or 8 players\)/);
  assert.match(SYSTEM_PROMPT, /120 takes over/);
  assert.match(SYSTEM_PROMPT, /claude|Coach/);
});
