// Deployment settings in wrangler.toml that matter for privacy and for the free plan.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";

const toml = readFileSync(new URL("../wrangler.toml", import.meta.url), "utf8");
const proxyToml = readFileSync(new URL("../../proxy/wrangler.toml", import.meta.url), "utf8");

/** The body of a [section] (up to the next header). */
function section(text: string, name: string): string | null {
  const lines = text.split("\n");
  const start = lines.findIndex((line) => line.trim() === `[${name}]`);
  if (start < 0) return null;
  const end = lines.findIndex((line, i) => i > start && /^\s*\[/.test(line));
  return lines.slice(start + 1, end < 0 ? undefined : end).join("\n");
}

test("request logs are off and query strings redacted: the live address carries the session token", () => {
  // Workers invocation logs keep every request URL for days; /v1/games/<id>/live?token=... would
  // store 180-day session tokens there. Query strings are also redacted from logs and traces, so
  // turning either on later cannot leak them. console.error lines (failures) are still kept.
  const logs = section(toml, "observability.logs");
  assert.ok(logs !== null, "wrangler.toml needs an [observability.logs] section");
  assert.match(logs, /^\s*invocation_logs\s*=\s*false\s*$/m);
  const observability = section(toml, "observability") ?? "";
  assert.match(observability, /^\s*enabled\s*=\s*true\s*$/m);
  assert.match(observability, /^\s*redact_query_string\s*=\s*true\s*$/m);
});

test("free-plan Durable Objects (SQLite) and rate limiters that do not share counters with the coach proxy", () => {
  assert.match(toml, /new_sqlite_classes\s*=\s*\["Hub",\s*"GameRoom"\]/);
  const ids = (text: string) => [...text.matchAll(/namespace_id\s*=\s*"(\d+)"/g)].map((m) => m[1]);
  const mine = ids(toml);
  assert.equal(mine.length, 3);
  assert.equal(new Set(mine).size, 3);
  for (const id of ids(proxyToml)) assert.ok(!mine.includes(id), `namespace ${id} is also the proxy's`);
});
