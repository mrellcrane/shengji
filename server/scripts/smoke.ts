// End-to-end smoke test of a running server (wrangler dev, or a deployed Worker), through the
// public API only, as two people would use it:
//
//   node --experimental-strip-types scripts/smoke.ts <base-url> [dev-auth-secret]
//   (or SMOKE_URL and DEV_AUTH_SECRET in the environment)
//
// Two dev-auth users ("Smoke A", "Smoke B") make a club (B joins with the invite code typed in
// lower case without the dash), A starts a game with B and two bots, both open the live
// WebSocket, and then each plays from their own view only (moves chosen by the bot logic from the
// view, like a person would) through a whole round until the next round is dealt. On the way it checks the
// error paths (403 not your turn, 409 stale, 400 illegal with the engine's explanation, nudges),
// the game lists, and that no view, HTTP or WebSocket, ever shows a card of another hand. Then a
// rename (a new version that reaches the other socket, and back), more sockets for A than one
// person keeps (the oldest is replaced with close code 4001), a close without a code (answered at
// once), and finally it deletes the game (sockets close with 4004) and leaves the club. Exit code
// 0 on success; prints a JSON report.

import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chooseBotAction } from "../src/game/bots.ts";
import { CLOSE_REPLACED, MAX_SOCKETS_PER_USER } from "../src/room/sockets.ts";
import type { Declaration } from "../src/engine/round.ts";
import type { SeatView } from "../src/engine/seatview.ts";
import type { GameSummary } from "../src/game/summary.ts";
import { checkSeatView, crossCheck } from "./viewcheck.ts";

export interface SmokeOptions {
  baseUrl: string;
  secret: string;
  log?: (line: string) => void;
  /** Safety stop for the move loop. */
  maxActions?: number;
}

export interface SmokeReport {
  url: string;
  serverVersion: string;
  push: boolean;
  gameId: string;
  actions: Record<string, number>;
  botAndHumanVersions: number;
  roundsCompleted: number;
  lastRoundSummary: string;
  webSocketUpdates: Record<string, number>;
  viewsChecked: number;
  checks: string[];
  durationMs: number;
}

interface Session {
  label: string;
  name: string;
  token: string;
  userId: string;
}

interface Table {
  game: GameSummary;
  view: SeatView;
  version: number;
}

interface Reply {
  status: number;
  body: Record<string, unknown> | null;
}

class SmokeFailure extends Error {}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new SmokeFailure(message);
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function runSmoke(options: SmokeOptions): Promise<SmokeReport> {
  const started = Date.now();
  const base = options.baseUrl.replace(/\/+$/, "");
  const log = options.log ?? (() => {});
  const checks: string[] = [];
  let viewsChecked = 0;

  async function call(method: string, path: string, token: string | null, body?: unknown): Promise<Reply> {
    for (let attempt = 0; ; attempt++) {
      const response = await fetch(`${base}${path}`, {
        method,
        headers: {
          ...(token === null ? {} : { authorization: `Bearer ${token}` }),
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const text = await response.text();
      if (response.status === 429 && attempt < 6 && !path.endsWith("/nudge")) {
        log(`rate limited on ${method} ${path}; waiting`);
        await sleep(10_000);
        continue;
      }
      let parsed: Record<string, unknown> | null = null;
      if (text.length > 0) {
        try {
          parsed = JSON.parse(text) as Record<string, unknown>;
        } catch {
          throw new SmokeFailure(`${method} ${path}: not JSON (${response.status}): ${text.slice(0, 200)}`);
        }
      }
      return { status: response.status, body: parsed };
    }
  }

  function expectStatus(reply: Reply, status: number, what: string): Record<string, unknown> {
    assert(reply.status === status, `${what}: expected ${status}, got ${reply.status} ${JSON.stringify(reply.body)}`);
    return reply.body ?? {};
  }

  function checkView(view: SeatView, where: string): void {
    const problems = checkSeatView(view);
    assert(problems.length === 0, `${where}: ${problems.join("; ")}`);
    viewsChecked++;
  }

  // Health.
  const health = expectStatus(await call("GET", "/health", null), 200, "GET /health");
  assert(health.ok === true, "health is not ok");
  checks.push(`health ok (version ${String(health.version)}, push ${String(health.push)})`);

  // Two people.
  const signIn = async (label: string, name: string): Promise<Session> => {
    const body = expectStatus(await call("POST", "/v1/auth/dev", null, { secret: options.secret, name }), 200, `sign in ${name}`);
    const user = body.user as { id: string; displayName: string };
    assert(typeof body.token === "string" && typeof user.id === "string", "sign-in reply is incomplete");
    const token = body.token as string;
    if (user.displayName !== name) {
      // A run that stopped half way through the rename check left the other name behind.
      expectStatus(await call("PATCH", "/v1/me", token, { displayName: name }), 200, `rename ${name} back`);
    }
    return { label, name, token, userId: user.id };
  };
  const a = await signIn("A", "Smoke A");
  const b = await signIn("B", "Smoke B");
  const wrong = await call("POST", "/v1/auth/dev", null, { secret: `${options.secret}x`, name: "Smoke A" });
  expectStatus(wrong, 401, "dev sign-in with a wrong secret");
  expectStatus(await call("GET", "/v1/me", null), 401, "GET /v1/me without a session");
  checks.push("dev sign-in for two users; wrong secret and missing session refused");

  // A club; B joins with the code typed loosely.
  const created = expectStatus(await call("POST", "/v1/clubs", a.token, { name: "Smoke test club" }), 200, "create club");
  const club = created.club as { id: string; inviteCode: string; members: { id: string }[] };
  assert(/^[A-Z0-9]{4}-[A-Z0-9]{4}$/.test(club.inviteCode), `invite code looks wrong: ${club.inviteCode}`);
  const loose = club.inviteCode.replace("-", "").toLowerCase();
  const joined = expectStatus(await call("POST", "/v1/clubs/join", b.token, { inviteCode: loose }), 200, "join club");
  const members = (joined.club as { members: { id: string }[] }).members.map((m) => m.id);
  assert(members.includes(a.userId) && members.includes(b.userId), "club members are missing someone");
  const me = expectStatus(await call("GET", "/v1/me", b.token), 200, "GET /v1/me");
  assert((me.clubs as { id: string }[]).some((c) => c.id === club.id), "B's clubs do not include the club");
  checks.push(`club created (${club.inviteCode}) and joined with "${loose}"`);

  let gameId = "";
  const sockets: WebSocket[] = [];
  try {
    // A game: A and B (opponents) with two bots.
    const seats = [{ userId: a.userId }, { userId: b.userId }, { bot: "standard" }, { bot: "beginner" }];
    const made = expectStatus(
      await call("POST", "/v1/games", a.token, { clubId: club.id, seats, targetRank: 14 }),
      200,
      "create game",
    );
    const summary = made.game as GameSummary;
    gameId = summary.id;
    assert(summary.phase === "bidding" && summary.yourTurn === true, "A should bid first in round 1");
    checks.push(`game ${gameId} created; bidding starts at the creator`);

    // Live updates for both.
    const updates: Record<string, Table[]> = { A: [], B: [] };
    const closes: Record<string, number | null> = { A: null, B: null };
    const wsBase = base.replace(/^http/, "ws");
    for (const session of [a, b]) {
      const ws = new WebSocket(`${wsBase}/v1/games/${gameId}/live?token=${encodeURIComponent(session.token)}`);
      sockets.push(ws);
      ws.addEventListener("message", (event) => {
        if (typeof event.data !== "string" || event.data === "pong") return;
        const message = JSON.parse(event.data) as { type: string } & Table;
        if (message.type === "update") updates[session.label].push(message);
      });
      ws.addEventListener("close", (event) => {
        closes[session.label] = event.code;
      });
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new SmokeFailure(`${session.label}: WebSocket did not open`)), 15_000);
        ws.addEventListener("open", () => {
          clearTimeout(timer);
          resolve();
        });
        ws.addEventListener("error", () => {
          clearTimeout(timer);
          reject(new SmokeFailure(`${session.label}: WebSocket failed to connect`));
        });
      });
    }
    // Without a valid session the upgrade is refused (401), so the socket never opens.
    const refused = await new Promise<boolean>((resolve) => {
      const ws = new WebSocket(`${wsBase}/v1/games/${gameId}/live?token=${"x".repeat(43)}`);
      const timer = setTimeout(() => resolve(false), 15_000);
      ws.addEventListener("open", () => {
        clearTimeout(timer);
        ws.close();
        resolve(false);
      });
      ws.addEventListener("error", () => {
        clearTimeout(timer);
        resolve(true);
      });
    });
    assert(refused, "a live connection without a valid session was accepted");
    const plain = await call("GET", `/v1/games/${gameId}/live`, a.token);
    expectStatus(plain, 426, "the live address without a WebSocket upgrade");
    checks.push("live WebSockets for both players; refused without a session; 426 for plain HTTP");

    const read = async (session: Session): Promise<Table> => {
      const body = expectStatus(await call("GET", `/v1/games/${gameId}`, session.token), 200, `GET game (${session.label})`);
      const table = body as unknown as Table;
      checkView(table.view, `GET view of ${session.label}`);
      return table;
    };
    const tables: Record<string, Table> = { A: await read(a), B: await read(b) };
    const myTurn = (view: SeatView) => view.bidding?.turn === 0 || view.turn === 0;
    const crossIfSameVersion = () => {
      if (tables.A.version !== tables.B.version) return;
      const problems = crossCheck(tables.A.view, tables.B.view);
      assert(problems.length === 0, `cross-check at version ${tables.A.version}: ${problems.join("; ")}`);
    };
    crossIfSameVersion();

    const actions: Record<string, number> = { A: 0, B: 0 };
    let bidOnce = false;
    let notYourTurnChecked = false;
    let staleChecked = false;
    let illegalChecked = false;
    let nudgeChecked = false;
    let listsChecked = false;
    const max = options.maxActions ?? 400;

    const chooseAction = (view: SeatView): Record<string, unknown> => {
      const action = chooseBotAction(view, "standard");
      if (action === null) throw new SmokeFailure(`no move from a view in phase ${view.phase} on our turn`);
      if (view.bidding !== null && view.bidding !== undefined) {
        // Bid at least once (the first offer if the bot would pass), so the bid path is exercised.
        const offered = view.bidding.available;
        let choice: Declaration | null = action.type === "bid" ? action.declaration : null;
        if (choice === null && !bidOnce && offered.length > 0) choice = offered[0];
        if (choice !== null) {
          bidOnce = true;
          return { type: "bid", declaration: choice };
        }
      }
      return action;
    };

    let roundsCompleted = 0;
    let lastRoundSummary = "";
    for (let step = 0; step < max * 2; step++) {
      if (actions.A + actions.B >= max) throw new SmokeFailure(`no round finished after ${max} actions`);
      let actor = [a, b].find((s) => myTurn(tables[s.label].view));
      if (actor === undefined) {
        tables.A = await read(a);
        tables.B = await read(b);
        crossIfSameVersion();
        actor = [a, b].find((s) => myTurn(tables[s.label].view));
        assert(actor !== undefined, "neither player can act, but the game is not waiting for a bot");
      }
      const other = actor === a ? b : a;
      const table = tables[actor.label];

      // Error paths, once each.
      if (!notYourTurnChecked) {
        const reply = await call("POST", `/v1/games/${gameId}/actions`, other.token, {
          version: table.version,
          action: { type: "pass" },
        });
        expectStatus(reply, 403, "acting out of turn");
        assert(reply.body?.error === "not_your_turn", "out-of-turn error code");
        notYourTurnChecked = true;
        checks.push("403 not_your_turn for the player who must wait");
      }
      if (!staleChecked && table.version > 1) {
        const reply = await call("POST", `/v1/games/${gameId}/actions`, actor.token, {
          version: table.version - 1,
          action: chooseAction(table.view),
        });
        const body = expectStatus(reply, 409, "acting on an old version");
        assert(body.error === "stale" && body.version === table.version, "stale reply should carry the current version");
        checkView(body.view as SeatView, "stale reply view");
        staleChecked = true;
        checks.push("409 stale with the current game, view and version");
      }
      if (!illegalChecked && table.view.phase === "playing") {
        const notMine = Array.from({ length: 108 }, (_, id) => id).find((id) => !table.view.hand.includes(id)) ?? 0;
        const reply = await call("POST", `/v1/games/${gameId}/actions`, actor.token, {
          version: table.version,
          action: { type: "play", cards: [notMine] },
        });
        const body = expectStatus(reply, 400, "an illegal play");
        assert(body.error === "illegal" && typeof body.message === "string" && body.message.length > 10, "illegal reply");
        illegalChecked = true;
        checks.push(`400 illegal: "${String(body.message)}"`);
      }
      if (!nudgeChecked) {
        expectStatus(await call("POST", `/v1/games/${gameId}/nudge`, other.token), 204, "nudge");
        const again = await call("POST", `/v1/games/${gameId}/nudge`, other.token);
        expectStatus(again, 429, "a second nudge right away");
        assert(again.body?.error === "too_soon", "second nudge error code");
        nudgeChecked = true;
        checks.push("nudge sent; a second one within 10 minutes refused (429 too_soon)");
      }
      if (!listsChecked) {
        const listed = expectStatus(await call("GET", "/v1/games", actor.token), 200, "GET /v1/games");
        const mine = (listed.games as GameSummary[]).find((g) => g.id === gameId);
        assert(mine !== undefined && mine.yourTurn === true, "the game should be listed as your turn");
        assert((listed.games as GameSummary[])[0].yourTurn === true, "your-turn games come first");
        const clubPage = expectStatus(await call("GET", `/v1/clubs/${club.id}`, other.token), 200, "GET club");
        const there = (clubPage.games as GameSummary[]).find((g) => g.id === gameId);
        assert(there !== undefined && there.yourTurn === false, "the club page should list the game");
        listsChecked = true;
        checks.push("game listed (your turn first) and on the club page");
      }

      const action = chooseAction(table.view);
      const reply = await call("POST", `/v1/games/${gameId}/actions`, actor.token, { version: table.version, action });
      if (reply.status === 409) {
        tables[actor.label] = reply.body as unknown as Table;
        continue;
      }
      const body = expectStatus(reply, 200, `${actor.label} ${String(action.type)}`);
      actions[actor.label]++;
      const next = body as unknown as Table;
      checkView(next.view, `action reply view of ${actor.label}`);
      assert(next.version > table.version, "the version must increase after an action");
      tables[actor.label] = next;
      if (next.view.lastRoundSummary !== null && next.view.roundNumber >= 2) {
        roundsCompleted = next.view.roundNumber - 1;
        lastRoundSummary = next.view.lastRoundSummary.explanation;
        tables[other.label] = await read(other);
        crossIfSameVersion();
        break;
      }
      if (!myTurn(next.view)) {
        tables[other.label] = await read(other);
        crossIfSameVersion();
      }
    }
    assert(roundsCompleted >= 1, "no round was completed");
    checks.push(`a whole round played (${actions.A} moves by A, ${actions.B} by B, bots in between)`);
    const otherSummary = tables[a.label].view.lastRoundSummary;
    assert(otherSummary !== null && tables.B.view.lastRoundSummary !== null, "both see the round summary");

    // The sockets got the latest version.
    const finalVersion = Math.max(tables.A.version, tables.B.version);
    for (let wait = 0; wait < 50; wait++) {
      const latest = (label: string) => updates[label].at(-1)?.version ?? 0;
      if (latest("A") >= finalVersion && latest("B") >= finalVersion) break;
      await sleep(100);
    }
    for (const label of ["A", "B"]) {
      const list = updates[label];
      assert(list.length >= 2, `${label} received ${list.length} WebSocket updates`);
      for (let i = 1; i < list.length; i++) assert(list[i].version >= list[i - 1].version, "updates out of order");
      assert(list.at(-1)!.version === finalVersion, `${label}'s last update is version ${list.at(-1)!.version}, not ${finalVersion}`);
      for (const update of list) checkView(update.view, `WebSocket update for ${label}`);
    }
    const byVersion = new Map(updates.B.map((u) => [u.version, u.view]));
    let crossed = 0;
    for (const update of updates.A) {
      const bView = byVersion.get(update.version);
      if (bView === undefined) continue;
      const problems = crossCheck(update.view, bView);
      assert(problems.length === 0, `WebSocket cross-check at version ${update.version}: ${problems.join("; ")}`);
      crossed++;
    }
    checks.push(
      `WebSocket updates: A ${updates.A.length}, B ${updates.B.length}, in order, ending at version ${finalVersion}; ${crossed} cross-checked pairs`,
    );
    checks.push(`${viewsChecked} views checked: no other hand, no hidden kitty, cards add up`);

    // A rename is a new version that reaches the other player's socket (the app keeps only newer
    // versions); then the name goes back.
    const waitForUpdate = async (label: string, test: (u: Table) => boolean, what: string): Promise<Table> => {
      for (let wait = 0; wait < 150; wait++) {
        const found = updates[label].find(test);
        if (found !== undefined) return found;
        await sleep(100);
      }
      throw new SmokeFailure(`${label} never got ${what}`);
    };
    const renamed = "Smoke B renamed";
    expectStatus(await call("PATCH", "/v1/me", b.token, { displayName: renamed }), 200, "rename B");
    const seen = await waitForUpdate(
      "A",
      (u) => u.version > finalVersion && u.view.players.some((p) => p.name === renamed),
      "an update with B's new name",
    );
    checkView(seen.view, "WebSocket update after a rename");
    expectStatus(await call("PATCH", "/v1/me", b.token, { displayName: b.name }), 200, "rename B back");
    await waitForUpdate("A", (u) => u.version > seen.version && u.view.players.some((p) => p.name === b.name), "B's name back");
    checks.push(`renames are new versions (${finalVersion} -> ${seen.version}) and reach the other player's socket`);

    // A person keeps their newest few sockets: one more replaces A's oldest (close code 4001).
    for (let extra = 0; extra < MAX_SOCKETS_PER_USER; extra++) {
      const ws = new WebSocket(`${wsBase}/v1/games/${gameId}/live?token=${encodeURIComponent(a.token)}`);
      sockets.push(ws);
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(() => reject(new SmokeFailure(`extra socket ${extra + 1} got no update`)), 15_000);
        ws.addEventListener("message", (event) => {
          if (typeof event.data === "string" && event.data.includes('"type":"update"')) {
            clearTimeout(timer);
            resolve();
          }
        });
        ws.addEventListener("error", () => {
          clearTimeout(timer);
          reject(new SmokeFailure(`extra socket ${extra + 1} failed to connect`));
        });
      });
    }
    // A close without a code (the server sees 1005, which may not be sent back) is still answered
    // at once and cleanly.
    const quitter = sockets[sockets.length - 1];
    const quit = await new Promise<{ code: number; clean: boolean } | null>((resolve) => {
      const timer = setTimeout(() => resolve(null), 5_000);
      quitter.addEventListener("close", (event) => {
        clearTimeout(timer);
        resolve({ code: event.code, clean: event.wasClean });
      });
      quitter.close();
    });
    assert(quit !== null && quit.clean, `a close without a code was not answered (${JSON.stringify(quit)})`);
    checks.push(`a close without a code is answered at once (${quit.code})`);

    // Clean up: the creator deletes the game; sockets close; both leave the club.
    expectStatus(await call("DELETE", `/v1/games/${gameId}`, b.token), 403, "deleting someone else's game");
    expectStatus(await call("DELETE", `/v1/games/${gameId}`, a.token), 204, "delete game");
    expectStatus(await call("GET", `/v1/games/${gameId}`, a.token), 404, "GET deleted game");
    // Clients can see a server's close some seconds after it was sent (wrangler dev: about 10).
    for (let wait = 0; wait < 250 && (closes.A === null || closes.B === null); wait++) await sleep(100);
    assert(closes.A === CLOSE_REPLACED, `A's oldest socket should close with ${CLOSE_REPLACED} (got ${closes.A})`);
    checks.push(`${MAX_SOCKETS_PER_USER + 1} sockets for one person: the oldest is replaced (${CLOSE_REPLACED})`);
    assert(closes.B === 4004, `B's socket should close with 4004 when the game is deleted (got ${closes.B})`);
    gameId = "";
    checks.push("game deleted by its creator (not by the other player); sockets closed with 4004");

    // Bigger tables: 6 seats (3 decks) with both people play into the first trick; 8 seats are
    // accepted and 5 refused.
    const sixSeats = [
      { userId: a.userId }, { bot: "standard" }, { bot: "standard" },
      { userId: b.userId }, { bot: "beginner" }, { bot: "standard" },
    ];
    const sixMade = expectStatus(
      await call("POST", "/v1/games", a.token, { clubId: club.id, seats: sixSeats, targetRank: 5 }),
      200,
      "create a 6-player game",
    );
    gameId = (sixMade.game as GameSummary).id;
    assert((sixMade.game as GameSummary).players.length === 6, "a 6-player game should list 6 players");
    const readSix = async (session: Session): Promise<Table> => {
      const body = expectStatus(await call("GET", `/v1/games/${gameId}`, session.token), 200, `GET 6-player game (${session.label})`);
      const table = body as unknown as Table;
      checkView(table.view, `6-player view of ${session.label}`);
      assert(table.view.handCounts.length === 6, "a 6-player view should count 6 hands");
      assert(table.view.hand.every((card) => card >= 0 && card < 162), "a 6-player hand holds ids of 3 decks");
      return table;
    };
    let sixActions = 0;
    let sixPlaying = false;
    for (let step = 0; step < 60 && !sixPlaying; step++) {
      let acted = false;
      for (const session of [a, b]) {
        const table = await readSix(session);
        if (table.view.phase === "playing" && table.view.tricks.length + table.view.currentTrick.length > 0) {
          sixPlaying = true;
          break;
        }
        if (!myTurn(table.view)) continue;
        const action = chooseBotAction(table.view, "standard");
        if (action === null) throw new SmokeFailure(`no move at the 6-player table in phase ${table.view.phase}`);
        const reply = await call("POST", `/v1/games/${gameId}/actions`, session.token, { version: table.version, action });
        if (reply.status === 409) continue;
        expectStatus(reply, 200, `${session.label} ${String(action.type)} at the 6-player table`);
        sixActions++;
        acted = true;
      }
      if (!acted && !sixPlaying) await sleep(200);
    }
    assert(sixPlaying, "the 6-player game should reach its first trick");
    expectStatus(await call("DELETE", `/v1/games/${gameId}`, a.token), 204, "delete the 6-player game");
    gameId = "";
    const eightSeats = [{ userId: a.userId }, ...Array.from({ length: 7 }, () => ({ bot: "beginner" }))];
    const eightMade = expectStatus(
      await call("POST", "/v1/games", a.token, { clubId: club.id, seats: eightSeats, targetRank: 5 }),
      200,
      "create an 8-player game",
    );
    gameId = (eightMade.game as GameSummary).id;
    assert((eightMade.game as GameSummary).players.length === 8, "an 8-player game should list 8 players");
    expectStatus(await call("DELETE", `/v1/games/${gameId}`, a.token), 204, "delete the 8-player game");
    gameId = "";
    const fiveSeats = [{ userId: a.userId }, ...Array.from({ length: 4 }, () => ({ bot: "standard" }))];
    expectStatus(await call("POST", "/v1/games", a.token, { clubId: club.id, seats: fiveSeats, targetRank: 5 }), 400,
                 "a 5-seat game is refused");
    checks.push(`a 6-player game reached its first trick (${sixActions} human moves); 8 seats accepted, 5 refused`);

    const report: SmokeReport = {
      url: base,
      serverVersion: String(health.version),
      push: health.push === true,
      gameId: summary.id,
      actions,
      botAndHumanVersions: finalVersion,
      roundsCompleted,
      lastRoundSummary,
      webSocketUpdates: { A: updates.A.length, B: updates.B.length },
      viewsChecked,
      checks,
      durationMs: 0,
    };
    return report;
  } finally {
    for (const ws of sockets) {
      try {
        ws.close();
      } catch {
        // ignore
      }
    }
    if (gameId !== "") await call("DELETE", `/v1/games/${gameId}`, a.token).catch(() => undefined);
    await call("POST", `/v1/clubs/${club.id}/leave`, a.token).catch(() => undefined);
    await call("POST", `/v1/clubs/${club.id}/leave`, b.token).catch(() => undefined);
    log(`smoke finished in ${Date.now() - started} ms`);
  }
}

async function main(): Promise<void> {
  const baseUrl = process.argv[2] ?? process.env.SMOKE_URL;
  const secret = process.argv[3] ?? process.env.DEV_AUTH_SECRET;
  if (!baseUrl || !secret) {
    console.error("usage: node --experimental-strip-types scripts/smoke.ts <base-url> [dev-auth-secret]");
    console.error("       (or set SMOKE_URL and DEV_AUTH_SECRET)");
    process.exit(2);
  }
  const started = Date.now();
  try {
    const report = await runSmoke({ baseUrl, secret, log: (line) => console.error(line) });
    report.durationMs = Date.now() - started;
    console.log(JSON.stringify(report, null, 2));
  } catch (e) {
    console.error(`SMOKE TEST FAILED: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
  }
}

// Run when executed directly (scripts/e2e.ts imports runSmoke instead).
if (process.argv[1] !== undefined && fileURLToPath(import.meta.url) === resolve(process.argv[1])) await main();
