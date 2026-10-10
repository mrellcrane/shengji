// The Hub's logic over SQLite: users and linked identities, sessions, devices, clubs and the
// games index.

import assert from "node:assert/strict";
import { test } from "node:test";
import { sessionTokenHash, newSessionToken } from "../src/auth/crypto.ts";
import {
  HubService,
  MAX_ACTIVE_GAMES_PER_USER,
  MAX_CLUB_MEMBERS,
  MAX_DEVICES_PER_USER,
  MAX_SESSIONS_PER_USER,
} from "../src/hub/service.ts";
import type { GameSnapshot } from "../src/game/summary.ts";
import { memorySql } from "./sqlite.ts";

function hub(start = Date.UTC(2026, 0, 1)) {
  const clock = { now: start };
  const service = new HubService(memorySql(), { now: () => new Date(clock.now), random: () => 0.1234 });
  return { service, clock };
}

const DAY = 24 * 60 * 60 * 1000;

async function session(service: HubService, subject: string, name: string | null = null, provider: "apple" | "dev" = "apple") {
  const token = newSessionToken();
  const hash = await sessionTokenHash(token);
  const user = service.signIn({ provider, subject }, name, hash);
  return { token, hash, user };
}

test("sign-in creates one user per identity; providers are separate; a default name is replaced", async () => {
  const { service } = hub();
  const first = await session(service, "apple-sub-1");
  assert.match(first.user.displayName, /^Player \d{4}$/);
  assert.match(first.user.id, /^u_[0-9a-z]{26}$/);
  const again = await session(service, "apple-sub-1", "Mei");
  assert.equal(again.user.id, first.user.id);
  assert.equal(again.user.displayName, "Mei", "the default name gives way to the name from the app");
  const third = await session(service, "apple-sub-1", "Somebody Else");
  assert.equal(third.user.displayName, "Mei", "a chosen name is kept");
  const dev = await session(service, "apple-sub-1", "Dev", "dev");
  assert.notEqual(dev.user.id, first.user.id, "the same subject from another provider is another person");
  // All three Apple sessions work.
  for (const s of [first, again, third]) assert.equal(service.authenticate(s.hash)?.id, first.user.id);
});

test("sessions last 180 days, unknown or expired ones fail, and only the newest 20 are kept", async () => {
  const { service, clock } = hub();
  const s = await session(service, "sub", "Lin");
  assert.equal(service.authenticate(s.hash)?.displayName, "Lin");
  assert.equal(service.authenticate(await sessionTokenHash(newSessionToken())), null);
  clock.now += 179 * DAY;
  assert.ok(service.authenticate(s.hash));
  clock.now += 2 * DAY;
  assert.equal(service.authenticate(s.hash), null);

  const many = [];
  for (let i = 0; i < MAX_SESSIONS_PER_USER + 5; i++) {
    clock.now += 1000;
    many.push(await session(service, "sub"));
  }
  const alive = many.filter((m) => service.authenticate(m.hash) !== null).length;
  assert.equal(alive, MAX_SESSIONS_PER_USER);
  assert.ok(service.authenticate(many[many.length - 1].hash), "the newest session survives");
  assert.equal(service.authenticate(many[0].hash), null, "the oldest one is dropped");
});

test("devices: registered per user, moved when another user registers the token, capped, removable", async () => {
  const { service, clock } = hub();
  const a = (await session(service, "a", "A")).user;
  const b = (await session(service, "b", "B")).user;
  const token = "ab".repeat(32);
  service.registerDevice(a.id, { platform: "ios", token, environment: "sandbox" });
  service.registerDevice(a.id, { platform: "ios", token, environment: "production" });
  assert.deepEqual(service.devices(a.id), [{ platform: "ios", token, environment: "production" }]);
  service.registerDevice(b.id, { platform: "ios", token, environment: "sandbox" });
  assert.deepEqual(service.devices(a.id), []);
  assert.equal(service.devices(b.id).length, 1);
  service.removeDevice(a.id, token);
  assert.equal(service.devices(b.id).length, 1, "only the owner can remove a device");
  service.removeDevice(b.id, token);
  assert.equal(service.devices(b.id).length, 0);
  for (let i = 0; i < MAX_DEVICES_PER_USER + 3; i++) {
    clock.now += 1000;
    service.registerDevice(a.id, { platform: "ios", token: i.toString(16).padStart(64, "0"), environment: "sandbox" });
  }
  const kept = service.devices(a.id);
  assert.equal(kept.length, MAX_DEVICES_PER_USER);
  assert.ok(kept.some((d) => d.token === (MAX_DEVICES_PER_USER + 2).toString(16).padStart(64, "0")));
  service.removeDeviceTokens(kept.map((d) => d.token));
  assert.equal(service.devices(a.id).length, 0);
});

test("clubs: create, join by code (any case, with or without the dash), members only, leave", async () => {
  const { service } = hub();
  const mei = (await session(service, "mei", "Mei")).user;
  const lin = (await session(service, "lin", "Lin")).user;
  const sam = (await session(service, "sam", "Sam")).user;
  const created = service.createClub(mei.id, "Friday Tractor");
  assert.ok(created.ok);
  const club = created.value.club;
  assert.match(club.inviteCode, /^[A-HJKMNP-Z2-9]{4}-[A-HJKMNP-Z2-9]{4}$/);
  assert.deepEqual(club.members, [mei]);

  const joined = service.joinClub(lin.id, club.inviteCode.replace("-", "").toLowerCase());
  assert.ok(joined.ok);
  assert.deepEqual(joined.value.club.members.map((m) => m.displayName), ["Mei", "Lin"]);
  assert.ok(service.joinClub(lin.id, club.inviteCode).ok, "joining twice is harmless");
  assert.equal(service.clubWithGames(lin.id, club.id).ok, true);

  const wrong = service.joinClub(sam.id, "ZZZZ-ZZZZ");
  assert.ok(!wrong.ok && wrong.status === 404);
  const junk = service.joinClub(sam.id, "not a code at all");
  assert.ok(!junk.ok && junk.status === 404);
  const outsider = service.clubWithGames(sam.id, club.id);
  assert.ok(!outsider.ok && outsider.status === 404, "non-members cannot see a club");

  const me = service.me(lin.id);
  assert.ok(me.ok);
  assert.deepEqual(me.value.clubs.map((c) => c.name), ["Friday Tractor"]);

  assert.ok(service.leaveClub(lin.id, club.id).ok);
  assert.equal(service.clubWithGames(lin.id, club.id).ok, false);
  const again = service.leaveClub(lin.id, club.id);
  assert.ok(!again.ok && again.status === 404);
  // The last member leaving removes the club; its code stops working.
  assert.ok(service.leaveClub(mei.id, club.id).ok);
  assert.equal(service.joinClub(sam.id, club.inviteCode).ok, false);
});

test("a club holds at most 50 members", async () => {
  const { service } = hub();
  const owner = (await session(service, "owner", "Owner")).user;
  const created = service.createClub(owner.id, "Big");
  assert.ok(created.ok);
  for (let i = 1; i < MAX_CLUB_MEMBERS; i++) {
    const u = (await session(service, `m${i}`, `M${i}`)).user;
    assert.ok(service.joinClub(u.id, created.value.club.inviteCode).ok);
  }
  const late = (await session(service, "late", "Late")).user;
  const full = service.joinClub(late.id, created.value.club.inviteCode);
  assert.ok(!full.ok && full.code === "club_full");
});

test("prepareGame checks the club, the seats and membership, and names the seats", async () => {
  const { service } = hub();
  const mei = (await session(service, "mei", "Mei")).user;
  const lin = (await session(service, "lin", "Lin")).user;
  const sam = (await session(service, "sam", "Sam")).user;
  const created = service.createClub(mei.id, "Club");
  assert.ok(created.ok);
  const clubId = created.value.club.id;
  assert.ok(service.joinClub(lin.id, created.value.club.inviteCode).ok);

  const good = service.prepareGame(mei.id, {
    clubId,
    seats: [{ userId: mei.id }, { bot: "standard" }, { userId: lin.id }, { bot: "beginner" }],
    targetRank: 10,
  });
  assert.ok(good.ok);
  assert.match(good.value.id, /^g_/);
  assert.equal(good.value.clubName, "Club");
  assert.deepEqual(
    good.value.seats.map((s) => [s.userId, s.bot, s.name]),
    [
      [mei.id, null, "Mei"],
      [null, "standard", "Tiger Bot"],
      [lin.id, null, "Lin"],
      [null, "beginner", "Dragon Bot"],
    ],
  );

  const bad = [
    service.prepareGame(sam.id, { clubId, seats: [{ userId: sam.id }, { bot: "standard" }, { bot: "standard" }, { bot: "standard" }], targetRank: 14 }),
    service.prepareGame(mei.id, { clubId, seats: [{ userId: mei.id }, { userId: sam.id }, { bot: "standard" }, { bot: "standard" }], targetRank: 14 }),
    service.prepareGame(mei.id, { clubId, seats: [{ userId: mei.id }, { userId: mei.id }, { bot: "standard" }, { bot: "standard" }], targetRank: 14 }),
    service.prepareGame(mei.id, { clubId, seats: [{ userId: lin.id }, { bot: "standard" }, { bot: "standard" }, { bot: "standard" }], targetRank: 14 }),
    service.prepareGame(mei.id, { clubId: "c_00000000000000000000000000", seats: [{ userId: mei.id }, { bot: "standard" }, { bot: "standard" }, { bot: "standard" }], targetRank: 14 }),
  ];
  assert.deepEqual(
    bad.map((r) => (r.ok ? "ok" : `${r.status} ${r.code}`)),
    ["404 not_found", "400 bad_request", "400 bad_request", "400 bad_request", "404 not_found"],
  );
});

function snapshot(id: string, clubId: string, players: string[], overrides: Partial<GameSnapshot> = {}): GameSnapshot {
  return {
    id,
    clubId,
    createdBy: players[0],
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    status: "active",
    version: 1,
    players: players.map((p, i) =>
      p === "bot" ? { name: `Bot ${i}`, isBot: true, userID: null } : { name: p, isBot: false, userID: p },
    ),
    levels: [2, 2],
    targetRank: 14,
    roundNumber: 1,
    phase: "playing",
    turn: 0,
    winner: null,
    lastEvent: null,
    ...overrides,
  };
}

test("the games index: newer versions win, lists put your turn first, badges count your turns", async () => {
  const { service } = hub();
  const mei = (await session(service, "mei", "Mei")).user.id;
  const lin = (await session(service, "lin", "Lin")).user.id;
  const players = [mei, "bot", lin, "bot"];
  service.gameChanged(snapshot("g1", "c1", players, { turn: 2, updatedAt: "2026-01-01T00:00:05.000Z" }));
  service.gameChanged(snapshot("g2", "c1", players, { turn: 0, updatedAt: "2026-01-01T00:00:01.000Z" }));
  service.gameChanged(snapshot("g3", "c1", players, { status: "finished", turn: null, winner: 1, updatedAt: "2026-01-01T00:00:09.000Z" }));
  // A late, older snapshot does not overwrite a newer one.
  service.gameChanged(snapshot("g1", "c1", players, { version: 5, turn: 0, updatedAt: "2026-01-01T00:00:06.000Z" }));
  service.gameChanged(snapshot("g1", "c1", players, { version: 4, turn: 2, updatedAt: "2026-01-01T00:00:07.000Z" }));

  const forMei = service.listGames(mei);
  assert.deepEqual(forMei.map((g) => [g.id, g.yourTurn, g.status]), [
    ["g1", true, "active"],
    ["g2", true, "active"],
    ["g3", false, "finished"],
  ]);
  const forLin = service.listGames(lin);
  assert.deepEqual(forLin.map((g) => [g.id, g.yourTurn, g.turn]), [
    ["g1", false, 2],
    ["g2", false, 2],
    ["g3", false, null],
  ]);
  assert.equal(forLin.find((g) => g.id === "g3")?.winnerTeam, 1, "Lin (seat 2) is on team 0: the winners are the other team");
  assert.equal(service.turnCount(mei), 2);
  assert.equal(service.turnCount(lin), 0);
  service.gameDeleted("g1");
  assert.deepEqual(service.listGames(mei).map((g) => g.id), ["g2", "g3"]);
  assert.equal(service.turnCount(mei), 1);
  // An update that was still on its way when the game was deleted does not bring it back.
  service.gameChanged(snapshot("g1", "c1", players, { version: 9, turn: 0 }));
  assert.deepEqual(service.listGames(mei).map((g) => g.id), ["g2", "g3"]);
});

test("at most 30 active games for everyone at the table, not only the person starting it", async () => {
  // Otherwise friends could seat someone in more games than their game list shows (it lists 60
  // active games), and games where it is their turn would never appear.
  const { service } = hub();
  const mei = (await session(service, "mei", "Mei")).user;
  const lin = (await session(service, "lin", "Lin")).user;
  const sam = (await session(service, "sam", "Sam")).user;
  const created = service.createClub(mei.id, "Club");
  assert.ok(created.ok);
  const clubId = created.value.club.id;
  for (const u of [lin, sam]) assert.ok(service.joinClub(u.id, created.value.club.inviteCode).ok);
  for (let i = 0; i < MAX_ACTIVE_GAMES_PER_USER; i++) {
    const creator = i % 2 === 0 ? mei.id : sam.id;
    service.gameChanged(snapshot(`g${i}`, clubId, [creator, "bot", lin.id, "bot"]));
  }
  const seatLin = (creator: string) =>
    service.prepareGame(creator, {
      clubId,
      seats: [{ userId: creator }, { bot: "standard" }, { userId: lin.id }, { bot: "standard" }],
      targetRank: 14,
    });
  const refused = seatLin(mei.id);
  assert.ok(!refused.ok);
  assert.deepEqual([refused.status, refused.code], [409, "too_many_games"]);
  assert.match(refused.message, new RegExp(`^Lin already has ${MAX_ACTIVE_GAMES_PER_USER} games going`));
  // A game without Lin is fine, and so is Lin again once one of the games is over.
  const withoutLin = service.prepareGame(mei.id, {
    clubId,
    seats: [{ userId: mei.id }, { bot: "standard" }, { userId: sam.id }, { bot: "standard" }],
    targetRank: 14,
  });
  assert.ok(withoutLin.ok);
  service.gameChanged(snapshot("g0", clubId, [mei.id, "bot", lin.id, "bot"], { version: 2, status: "finished", turn: null, winner: 0 }));
  assert.ok(seatLin(sam.id).ok);
});
