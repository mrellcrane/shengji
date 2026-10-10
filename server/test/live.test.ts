// The live WebSocket's decisions that do not need workerd: who may connect (RoomHost.connect,
// which also runs overdue bot turns and hands back their pushes), which old sockets make room for
// a new one, and how a client's close is answered (src/room/sockets.ts). The Durable Object only
// wires these to the hibernation API; scripts/smoke.ts checks them in workerd.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import { closeReplyCode, MAX_SOCKETS, MAX_SOCKETS_PER_USER, socketsToReplace } from "../src/room/sockets.ts";
import { makeCloud } from "./cloud.ts";

test("connecting: seated players get their seat, others are refused, overdue bot turns run and their pushes come back", async () => {
  const cloud = makeCloud({ seed: 21 });
  const [mei, lin, sam] = [await cloud.signIn("Mei"), await cloud.signIn("Lin"), await cloud.signIn("Sam")];
  const club = await cloud.call("POST", "/v1/clubs", { token: mei.token, body: { name: "Club" } });
  for (const p of [lin, sam]) await cloud.call("POST", "/v1/clubs/join", { token: p.token, body: { inviteCode: club.body.club.inviteCode } });
  const made = await cloud.call("POST", "/v1/games", {
    token: mei.token,
    body: { clubId: club.body.club.id, seats: [{ userId: mei.id }, { bot: "standard" }, { userId: lin.id }, { bot: "standard" }] },
  });
  const gameId = made.body.game.id as string;
  const room = cloud.rooms.get(gameId)!;

  assert.deepEqual(await room.connect(lin.id), { result: { ok: true, value: { seat: 2 } }, notifications: [] });
  const stranger = await room.connect(sam.id);
  assert.equal(stranger.result.ok ? "ok" : stranger.result.code, "not_seated");

  // A request stopped right after Mei's pass: East (a bot) is due. Opening the live socket runs
  // the bots, and the push for whoever must act now is handed back (not dropped).
  const state = room.service.load()!;
  const broken = structuredClone(state);
  E.bid(broken.round, 0, "pass");
  broken.version += 1;
  (room.service as unknown as { save(s: unknown, l: unknown[]): void }).save(broken, [
    { version: broken.version, seat: 0, kind: "action", data: { type: "pass" } },
  ]);
  const reply = await room.connect(mei.id);
  assert.ok(reply.result.ok);
  assert.ok(room.service.load()!.version > broken.version, "the bots caught up");
  assert.equal(reply.notifications.length, 1);
  assert.equal(reply.notifications[0].title, "Your turn");
  assert.equal(reply.notifications[0].userId, lin.id);

  assert.equal((await cloud.call("DELETE", `/v1/games/${gameId}`, { token: mei.token })).status, 204);
  const gone = await room.connect(mei.id);
  assert.equal(gone.result.ok ? "ok" : gone.result.code, "not_found");
});

test("sockets: a person keeps their newest few connections; one person can't fill a game's sockets", () => {
  const at = (userId: string, connectedAt: number) => ({ userId, connectedAt });
  // Room to spare: nothing to close.
  assert.deepEqual(socketsToReplace([at("mei", 1), at("lin", 2)], "mei"), []);
  // Mei already has the most allowed: her oldest goes (connections that dropped without a close
  // pile up as a phone reconnects).
  const mine = Array.from({ length: MAX_SOCKETS_PER_USER }, (_, i) => at("mei", 100 - i));
  const open = [at("lin", 1), ...mine, at("sam", 2)];
  assert.deepEqual(socketsToReplace(open, "mei"), [MAX_SOCKETS_PER_USER]);
  assert.deepEqual(socketsToReplace(open, "lin"), []);
  // More than allowed (an older server allowed it): close down to the limit, oldest first.
  const many = Array.from({ length: MAX_SOCKETS_PER_USER + 3 }, (_, i) => at("mei", i));
  assert.deepEqual(socketsToReplace(many, "mei"), [0, 1, 2, 3]);
  // Four seats can never fill the room, so a seated player always gets in.
  assert.ok(MAX_SOCKETS_PER_USER * 4 < MAX_SOCKETS);
  const full = Array.from({ length: MAX_SOCKETS }, (_, i) => at(`u${i}`, i));
  assert.equal(socketsToReplace(full, "new"), null);
});

test("a client's close is always answered, also when it carried no code", () => {
  // A close frame without a code arrives as 1005 (a dropped connection as 1006). Those codes may
  // not be sent back (workerd's close() throws), and an unanswered close left the client waiting
  // about 10 seconds for an unclean end. They are answered with 1000; real codes are echoed.
  for (const code of [1005, 1006, 1015, 1004, 999, 5000, 0, Number.NaN]) assert.equal(closeReplyCode(code), 1000, String(code));
  for (const code of [1000, 1001, 1008, 1011, 3000, 4001, 4004, 4999]) assert.equal(closeReplyCode(code), code);
});
