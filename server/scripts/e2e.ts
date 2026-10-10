// Local end-to-end test: starts the Worker in `wrangler dev` (workerd, with real SQLite-backed
// Durable Objects, rate limit bindings and WebSockets) on a free port with fresh storage and a
// random DEV_AUTH_SECRET, then runs the smoke test (scripts/smoke.ts) against it.
//
//   npm run e2e

import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { runSmoke } from "./smoke.ts";

const serverDir = fileURLToPath(new URL("..", import.meta.url));

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once("error", reject);
    probe.listen(0, "127.0.0.1", () => {
      const address = probe.address();
      const port = typeof address === "object" && address !== null ? address.port : 0;
      probe.close(() => resolve(port));
    });
  });
}

async function main(): Promise<void> {
  const port = await freePort();
  const secret = randomBytes(24).toString("hex");
  const persist = mkdtempSync(join(tmpdir(), "shengji-e2e-"));
  const url = `http://127.0.0.1:${port}`;
  const output: string[] = [];
  const child = spawn(
    "npx",
    [
      "wrangler",
      "dev",
      "--port",
      String(port),
      "--ip",
      "127.0.0.1",
      "--persist-to",
      persist,
      "--var",
      `DEV_AUTH_SECRET:${secret}`,
      "--var",
      "VERSION:local-e2e",
      "--show-interactive-dev-session=false",
    ],
    { cwd: serverDir, stdio: ["ignore", "pipe", "pipe"], detached: true, env: { ...process.env, CI: "1" } },
  );
  child.stdout.on("data", (chunk: Buffer) => output.push(chunk.toString()));
  child.stderr.on("data", (chunk: Buffer) => output.push(chunk.toString()));
  const stop = () => {
    try {
      if (child.pid !== undefined) process.kill(-child.pid, "SIGTERM");
    } catch {
      // Already gone.
    }
  };
  let failed = false;
  try {
    let up = false;
    for (let i = 0; i < 120 && !up; i++) {
      await new Promise((resolve) => setTimeout(resolve, 500));
      try {
        up = (await fetch(`${url}/health`)).ok;
      } catch {
        // Not listening yet.
      }
      if (child.exitCode !== null) break;
    }
    if (!up) throw new Error(`wrangler dev did not start:\n${output.join("").slice(-4000)}`);
    console.error(`wrangler dev is up at ${url}`);
    const started = Date.now();
    const report = await runSmoke({ baseUrl: url, secret, log: (line) => console.error(line) });
    report.durationMs = Date.now() - started;
    console.log(JSON.stringify(report, null, 2));
  } catch (e) {
    failed = true;
    console.error(`E2E FAILED: ${e instanceof Error ? e.message : String(e)}`);
    console.error(`--- wrangler output (tail) ---\n${output.join("").slice(-6000)}`);
  } finally {
    stop();
    await new Promise((resolve) => setTimeout(resolve, 500));
    rmSync(persist, { recursive: true, force: true });
  }
  process.exit(failed ? 1 : 0);
}

await main();
