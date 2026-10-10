// Games through the HTTP API (the in-process cloud: real router, Hub and GameRoom logic):
// creation rules, the action flow from bidding to finished rounds and games with bots between
// human turns, version conflicts, illegal moves with the engine's explanation, turn and seat
// checks, notifications, nudges, renames and deletion.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, SeatView } from "../src/engine/index.ts";
import { chooseBid, chooseBury, chooseFollow, chooseLead } from "../src/game/bots.ts";
import type { GameSummary } from "../src/game/summary.ts";
import { checkSeatView } from "../scripts/viewcheck.ts";
import { buildDeck } from "./support.ts";
import { HUB_RESET_ERROR, makeCloud } from "./cloud.ts";
import type { Cloud } from "./cloud.ts";

type Player = { token: string; id: string; name: string };
type Table = { game: GameSummary; view: SeatView; version: number };

async function clubOf(cloud: Cloud, owner: Player, members: Player[], name = "Friday Tractor"): Promise<string> {
  const created = await cloud.call("POST", "/v1/clubs", { token: owner.token, body: { name } });
  assert.equal(created.status, 200);
  for (const m of members) {
    const joined = await cloud.call("POST", "/v1/clubs/join", { token: m.token, body: { inviteCode: created.body.club.inviteCode } });
    assert.equal(joined.status, 200);
  }
  return created.body.club.id as string;
}

async function newGame(cloud: Cloud, creator: Player, clubId: string, seats: unknown[], targetRank = 14): Promise<string> {
  const reply = await cloud.call("POST", "/v1/games", { token: creator.token, body: { clubId, seats, targetRank } });
  assert.equal(reply.status, 200, JSON.stringify(reply.body));
  return reply.body.game.id as string;
}

async function read(cloud: Cloud, player: Player, gameId: string): Promise<Table> {
  const reply = await cloud.call("GET", `/v1/games/${gameId}`, { token: player.token });
  assert.equal(reply.status, 200, JSON.stringify(reply.body));
  assert.deepEqual(checkSeatView(reply.body.view), []);
  return reply.body as Table;
}

const isMyTurn = (view: SeatView) => view.bidding?.turn === 0 || view.turn === 0;

/** What a sensible person would do from this view (the bots' choices, made from the view only). */
function moveFrom(view: SeatView): Record<string, unknown> {
  if (view.bidding !== null) {
    const choice = chooseBid(view.bidding.available, view.hand);
    return choice === null ? { type: "pass" } : { type: "bid", declaration: choice };
  }
  if (view.phase === "burying") return { type: "bury", cards: chooseBury(view.hand, view.trump) };
  if (view.currentTrick.length === 0) return { type: "play", cards: chooseLead(view.hand, view.trump) };
  return { type: "play", cards: chooseFollow({ hand: view.hand, trump: view.trump, currentTrick: view.currentTrick, seat: 0 }) };
}

/** Plays for every person until `stop` says so; returns the number of human moves. */
async function drive(
  cloud: Cloud,
  players: Player[],
  gameId: string,
  stop: (table: Table) => boolean,
  limit = 3000,
): Promise<{ moves: number; last: Table }> {
  let moves = 0;
  for (;;) {
    const tables = await Promise.all(players.map((p) => read(cloud, p, gameId)));
    const done = tables.find(stop);
    if (done !== undefined) return { moves, last: done };
    const index = tables.findIndex((t) => isMyTurn(t.view));
    assert.ok(index >= 0, "nobody can act but the game waits");
    const table = tables[index];
    const reply = await cloud.call("POST", `/v1/games/${gameId}/actions`, {
      token: players[index].token,
      body: { version: table.version, action: moveFrom(table.view) },
    });
    assert.equal(reply.status, 200, JSON.stringify(reply.body));
    assert.ok(reply.body.version > table.version);
    moves++;
    assert.ok(moves < limit, "the game did not get there");
  }
}

test("creating a game: seats, membership and target are checked; bidding opens at the creator", async () => {
  const cloud = makeCloud();
  const [mei, lin, sam] = [await cloud.signIn("Mei"), await cloud.signIn("Lin"), await cloud.signIn("Sam")];
  const clubId = await clubOf(cloud, mei, [lin]);
  const bot = { bot: "standard" };
  const cases: [unknown, number, string][] = [
    [{ clubId, seats: [{ userId: mei.id }, bot, bot], targetRank: 14 }, 400, "bad_request"],
    [{ clubId, seats: [{ userId: mei.id }, bot, bot, { bot: "genius" }], targetRank: 14 }, 400, "bad_request"],
    [{ clubId, seats: [{ userId: mei.id }, bot, bot, bot], targetRank: 7 }, 400, "bad_request"],
    [{ clubId, seats: [{ userId: mei.id }, { userId: sam.id }, bot, bot], targetRank: 14 }, 400, "bad_request"],
    [{ clubId, seats: [{ userId: lin.id }, bot, bot, bot], targetRank: 14 }, 400, "bad_request"],
    [{ clubId, seats: [{ userId: mei.id }, { userId: mei.id }, bot, bot] }, 400, "bad_request"],
    [{ clubId: "c_nope", seats: [{ userId: mei.id }, bot, bot, bot] }, 400, "bad_request"],
    [{ clubId, seats: [{ userId: mei.id, bot: "standard" }, bot, bot, bot] }, 400, "bad_request"],
    ["not an object", 400, "bad_request"],
  ];
  for (const [body, status, code] of cases) {
    const reply = await cloud.call("POST", "/v1/games", { token: mei.token, body });
    assert.equal(reply.status, status, JSON.stringify(body));
    assert.equal(reply.body.error, code);
    assert.equal(typeof reply.body.message, "string");
  }
  const outsider = await cloud.call("POST", "/v1/games", {
    token: sam.token,
    body: { clubId, seats: [{ userId: sam.id }, bot, bot, bot] },
  });
  assert.equal(outsider.status, 404, "only members can start games in a club");

  const reply = await cloud.call("POST", "/v1/games", {
    token: lin.token,
    body: { clubId, seats: [{ userId: mei.id }, bot, { userId: lin.id }, { bot: "beginner" }] },
  });
  assert.equal(reply.status, 200);
  const game = reply.body.game as GameSummary;
  assert.deepEqual(
    { phase: game.phase, turn: game.turn, yourTurn: game.yourTurn, targetRank: game.targetRank, roundNumber: game.roundNumber },
    { phase: "bidding", turn: 0, yourTurn: true, targetRank: 14, roundNumber: 1 },
    "the creator (Lin, seat 2) bids first",
  );
  assert.deepEqual(game.players.map((p) => p.name), ["Lin", "Dragon Bot", "Mei", "Tiger Bot"]);
  assert.equal(game.lastEvent, "You started the game");
  const forMei = await read(cloud, mei, game.id);
  assert.equal(forMei.game.lastEvent, "Lin started the game");
  assert.equal(forMei.view.phase, "bidding");
  assert.equal(forMei.view.bidding?.turn, 2);
  assert.deepEqual(forMei.view.bidding?.available, [], "only the bidder is offered declarations");
  assert.equal(forMei.view.hand.length, 25);
  assert.deepEqual(forMei.view.handCounts, [25, 25, 25, 25]);
  assert.equal(forMei.view.kitty, null);
  assert.equal(forMei.version, 1);
});

test("a whole round with bots: bidding, burying, 25 tricks, then the next round is dealt at once", async () => {
  const cloud = makeCloud({ seed: 42 });
  const mei = await cloud.signIn("Mei");
  const clubId = await clubOf(cloud, mei, []);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { bot: "standard" }, { bot: "standard" }, { bot: "beginner" }]);
  const phases = new Set<string>();
  const { moves, last } = await drive(cloud, [mei], gameId, (t) => {
    phases.add(t.view.phase);
    return t.view.roundNumber === 2;
  });
  assert.ok(moves >= 25 && moves < 40, `${moves} moves`);
  assert.deepEqual([...phases].sort(), ["bidding", "burying", "playing"].filter((p) => phases.has(p)).sort());
  assert.ok(phases.has("playing"));
  const summary = last.view.lastRoundSummary;
  assert.ok(summary !== null, "the finished round's summary is shown in the next round");
  assert.equal(summary.result.kitty.length, 8);
  assert.match(summary.explanation, /^The defenders scored \d+ points/);
  assert.equal(last.view.phase, "bidding", "round 2 bidding opens at once");
  assert.equal(last.view.dealer, summary.nextDealer, "bidding starts at the next dealer");
  // Bidding opened at the next dealer; the bots before Mei have already had their turn.
  const history = last.view.bidding?.history ?? [];
  assert.equal(history.length > 0 ? history[0].player : last.view.bidding?.turn, summary.nextDealer);
  assert.equal(last.view.bidding?.turn, 0);
  assert.match(last.game.lastEvent ?? "", /^Round 1: (your team|Tiger Bot and Dragon Bot) (kept|took over) the deal/);

  // The room logged every change with consecutive versions, including a deal for round 2.
  const log = cloud.rooms.get(gameId)!.service.log();
  assert.deepEqual(log.map((e) => e.version), Array.from({ length: last.version }, (_, i) => i + 1));
  assert.equal(log.filter((e) => e.kind === "deal").length, 1);
  assert.equal(log.filter((e) => e.kind === "action").length, moves);
  assert.ok(log.filter((e) => e.kind === "bot").length > 60);
  assert.ok((cloud.broadcasts.get(gameId) ?? 0) >= moves, "live updates after every change");

  const listed = await cloud.call("GET", "/v1/games", { token: mei.token });
  assert.equal(listed.body.games[0].id, gameId);
  assert.equal(listed.body.games[0].roundNumber, 2);
});

test("stale versions, illegal moves, wrong phase, out-of-turn and unseated players", async () => {
  const cloud = makeCloud({ seed: 7 });
  const [mei, lin, sam] = [await cloud.signIn("Mei"), await cloud.signIn("Lin"), await cloud.signIn("Sam")];
  const clubId = await clubOf(cloud, mei, [lin, sam]);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }]);
  const act = (p: Player, body: unknown) => cloud.call("POST", `/v1/games/${gameId}/actions`, { token: p.token, body });

  let t = await read(cloud, mei, gameId);
  const outOfTurn = await act(lin, { version: t.version, action: { type: "pass" } });
  assert.deepEqual([outOfTurn.status, outOfTurn.body.error], [403, "not_your_turn"]);
  const wrongPhase = await act(mei, { version: t.version, action: { type: "bury", cards: t.view.hand.slice(0, 8) } });
  assert.deepEqual([wrongPhase.status, wrongPhase.body], [400, { error: "illegal", message: "You can't do that at this point in the round." }]);
  const notMine = await act(mei, {
    version: t.version,
    action: { type: "bid", declaration: { player: 2, cards: [0], suit: 0, strength: 1 } },
  });
  assert.equal(notMine.status, 400);
  const badBid = await act(mei, { version: t.version, action: { type: "bid", declaration: { cards: [53, 107], strength: 2, suit: 1 } } });
  assert.deepEqual([badBid.status, badBid.body.error], [400, "illegal"]);
  assert.match(badBid.body.message, /^You can't declare that right now/);
  const unseated = await act(sam, { version: t.version, action: { type: "pass" } });
  assert.deepEqual([unseated.status, unseated.body.error], [403, "not_seated"]);
  const unseatedRead = await cloud.call("GET", `/v1/games/${gameId}`, { token: sam.token });
  assert.equal(unseatedRead.status, 403);
  for (const body of [{}, { version: -1, action: { type: "pass" } }, { version: 1, action: { type: "fold" } }, { version: 1, action: { type: "play", cards: [108] } }, { version: 1.5, action: { type: "pass" } }]) {
    const reply = await act(mei, body);
    assert.deepEqual([reply.status, reply.body.error], [400, "bad_request"], JSON.stringify(body));
  }
  assert.equal((await read(cloud, mei, gameId)).version, t.version, "refused actions change nothing");

  // Pass, then try again with the old version: 409 with the current table.
  const passed = await act(mei, { version: t.version, action: { type: "pass" } });
  assert.equal(passed.status, 200);
  const stale = await act(mei, { version: t.version, action: { type: "pass" } });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error, "stale");
  assert.equal(stale.body.version, passed.body.version);
  assert.deepEqual(stale.body.view, passed.body.view);
  assert.deepEqual(stale.body.game.id, gameId);

  // Play on until Mei must follow and can break the follow-suit rule; the reply carries the
  // engine's explanation word for word.
  let checked = false;
  for (let i = 0; i < 400 && !checked; i++) {
    const tables = [await read(cloud, mei, gameId), await read(cloud, lin, gameId)];
    const who = tables.findIndex((x) => isMyTurn(x.view));
    t = tables[who];
    const v = t.view;
    if (who === 0 && v.phase === "playing" && v.currentTrick.length > 0) {
      const lead = v.currentTrick[0].cards;
      const offSuit = v.hand.filter((card) => E.groupOf(v.trump, card) !== E.groupOf(v.trump, lead[0]));
      const attempt = [...offSuit.slice(0, lead.length)];
      const violation = attempt.length === lead.length ? E.validateFollow(attempt, v.hand, lead, v.trump) : null;
      if (violation !== null && violation.case === "mustFollowSuit") {
        const reply = await act(mei, { version: t.version, action: { type: "play", cards: attempt } });
        assert.deepEqual(reply.body, { error: "illegal", message: E.followViolationExplanation(violation) });
        assert.equal(reply.status, 400);
        assert.match(reply.body.message, /were led and you still have/);
        checked = true;
        break;
      }
    }
    const reply = await act([mei, lin][who], { version: t.version, action: moveFrom(v) });
    assert.equal(reply.status, 200, JSON.stringify(reply.body));
  }
  assert.ok(checked, "never got a chance to break the follow-suit rule");
});

test("a failed throw is played as its forced part and reported with a viewer-relative blocker", async () => {
  // Round 1, rank 2. Mei (seat 0) holds A♠ Q♠ and East (seat 1, a bot) holds K♠, so the throw
  // A♠ Q♠ fails on Q♠. The kitty has no 2 and no joker: nobody declares, hearts are trump by the
  // kitty flip (A♥ is its highest card), and Mei, the first bidder, deals.
  const c = (rank: E.Rank, suit: E.Suit, copy = 0): Card => E.makeCard(rank, suit, copy);
  const kitty = [c(14, 1), c(3, 2), c(4, 2), c(6, 3), c(7, 3), c(8, 3), c(9, 2), c(3, 3)];
  const meiCards = [c(14, 0), c(12, 0), ...[3, 4, 6, 7, 8, 9].map((r) => c(r as E.Rank, 2, 1))];
  const deck = buildDeck([meiCards, [c(13, 0), c(13, 0, 1)], [], []], kitty, 0, 5);
  // Keep every 2 and joker out of Mei's hand so that she cannot declare: move them to seat 3.
  const cloud = makeCloud({ decks: [deck] });
  const mei = await cloud.signIn("Mei");
  const clubId = await clubOf(cloud, mei, []);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { bot: "beginner" }, { bot: "beginner" }, { bot: "beginner" }]);
  let t = await read(cloud, mei, gameId);
  const act = (body: unknown) => cloud.call("POST", `/v1/games/${gameId}/actions`, { token: mei.token, body });
  // Everyone passes (beginner bots never declare).
  let reply = await act({ version: t.version, action: { type: "pass" } });
  assert.equal(reply.status, 200);
  t = reply.body;
  assert.equal(t.view.phase, "burying");
  assert.equal(t.view.dealer, 0);
  assert.deepEqual(t.view.trump, { rank: 2, suit: 1 });
  assert.equal(t.view.trumpFromKitty, c(14, 1));
  assert.deepEqual(t.view.kitty, kitty, "the dealer sees the kitty she picked up");
  const bury = t.view.hand.filter((card) => !meiCards.slice(0, 2).includes(card) && E.groupOf(t.view.trump, card) !== 1).slice(0, 8);
  reply = await act({ version: t.version, action: { type: "bury", cards: bury } });
  assert.equal(reply.status, 200);
  t = reply.body;
  assert.equal(t.view.phase, "playing");
  assert.deepEqual(t.view.kitty?.slice().sort((a, b) => a - b), bury.slice().sort((a, b) => a - b));
  reply = await act({ version: t.version, action: { type: "play", cards: [c(14, 0), c(12, 0)] } });
  assert.equal(reply.status, 200);
  assert.deepEqual(reply.body.outcome, { type: "throwFailed", forced: [c(12, 0)], blocker: 1 });
  assert.deepEqual(reply.body.view.tricks.length + reply.body.view.currentTrick.length >= 1, true);
  const firstPlay = reply.body.view.tricks.length > 0 ? reply.body.view.tricks[0].plays[0] : reply.body.view.currentTrick[0];
  assert.deepEqual(firstPlay, { player: 0, cards: [c(12, 0)] });
  assert.ok(reply.body.view.hand.includes(c(14, 0)), "the rest of the throw goes back to the hand");
});

test("turns pass between people with pushes; round over, nudges, and game over notify the others", async () => {
  const cloud = makeCloud({ seed: 3 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const clubId = await clubOf(cloud, mei, [lin], "Friday Tractor");
  for (const [p, token] of [[mei, "aa"], [lin, "bb"]] as const) {
    const r = await cloud.call("POST", "/v1/devices", { token: p.token, body: { platform: "ios", token: token.repeat(32), environment: "sandbox" } });
    assert.equal(r.status, 204);
  }
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }], 5);

  // Nudges: Lin reminds Mei (whose turn it is); not twice in 10 minutes; not yourself.
  assert.equal((await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: mei.token })).status, 400);
  assert.equal((await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token })).status, 204);
  await cloud.settle();
  assert.deepEqual(cloud.push.sent.map((m) => [m.token, m.title, m.body, m.badge, m.gameId]), [
    ["aa".repeat(32), "Your turn", "Lin is waiting for you in Friday Tractor.", 1, gameId],
  ]);
  const again = await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token });
  assert.deepEqual([again.status, again.body.error], [429, "too_soon"]);
  cloud.clock.now += 10 * 60 * 1000;
  assert.equal((await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token })).status, 204);
  await cloud.settle();
  cloud.push.sent.length = 0;

  // Mei acts: if the turn reaches Lin, Lin (only) gets "Your turn" naming what happened.
  let t = await read(cloud, mei, gameId);
  const reply = await cloud.call("POST", `/v1/games/${gameId}/actions`, { token: mei.token, body: { version: t.version, action: moveFrom(t.view) } });
  assert.equal(reply.status, 200);
  await cloud.settle();
  const linTable = await read(cloud, lin, gameId);
  assert.ok(cloud.push.sent.every((m) => m.token !== "aa".repeat(32)), "nobody is told about their own move");
  if (isMyTurn(linTable.view)) {
    assert.equal(cloud.push.sent.length, 1);
    assert.equal(cloud.push.sent[0].title, "Your turn");
    assert.ok(cloud.push.sent[0].body.endsWith(" in Friday Tractor."), cloud.push.sent[0].body);
    assert.equal(cloud.push.sent[0].body, `${linTable.game.lastEvent} in Friday Tractor.`);
  }

  // Play to the end of the game (target 5): everyone else hears "Game over".
  let roundPushes = 0;
  let sawRoundOver = false;
  for (let moves = 0; ; moves++) {
    assert.ok(moves < 4000, "the game did not finish");
    const tables = [await read(cloud, mei, gameId), await read(cloud, lin, gameId)];
    if (tables[0].game.status === "finished") {
      t = tables[0];
      break;
    }
    const who = tables.findIndex((x) => isMyTurn(x.view));
    assert.ok(who >= 0);
    cloud.push.sent.length = 0;
    const r = await cloud.call("POST", `/v1/games/${gameId}/actions`, {
      token: [mei, lin][who].token,
      body: { version: tables[who].version, action: moveFrom(tables[who].view) },
    });
    assert.equal(r.status, 200);
    await cloud.settle();
    const actorDevice = who === 0 ? "aa".repeat(32) : "bb".repeat(32);
    assert.ok(cloud.push.sent.every((m) => m.token !== actorDevice));
    assert.ok(cloud.push.sent.length <= 1);
    for (const m of cloud.push.sent) {
      if (/^Round \d+: /.test(m.body)) {
        roundPushes++;
        if (m.title === "Friday Tractor") sawRoundOver = true;
      }
    }
    if (r.body.game.status === "finished") {
      const other = cloud.push.sent.find((m) => m.token !== actorDevice);
      assert.ok(other !== undefined, "the other player hears the game is over");
      assert.equal(other.title, "Game over");
      assert.match(other.body, /won the game in Friday Tractor/);
    }
  }
  assert.ok(roundPushes > 0, "round results reach the other player");
  assert.ok(sawRoundOver || roundPushes > 0);
  assert.equal(t.game.status, "finished");
  assert.equal(t.view.phase, "finished");
  assert.notEqual(t.view.gameWinnerTeam, null);
  assert.equal(t.view.lastRoundSummary?.gameWinner, t.view.gameWinnerTeam);
  assert.equal(t.view.roundNumber, t.game.roundNumber);
  assert.ok(t.view.roundNumber >= 2, "a game to 5 takes several rounds");
  assert.ok(t.view.kitty !== null && t.view.kitty.length === 8, "everyone sees the kitty of a finished round");
  assert.match(t.game.lastEvent ?? "", /won the game$/);
  assert.equal(t.game.turn, null);
  assert.equal(t.game.yourTurn, false);
  const late = await cloud.call("POST", `/v1/games/${gameId}/actions`, { token: mei.token, body: { version: t.version, action: { type: "pass" } } });
  assert.deepEqual([late.status, late.body], [403, { error: "not_your_turn", message: "The game is over." }]);
  const nudge = await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token });
  assert.equal(nudge.status, 400);
  const listed = await cloud.call("GET", "/v1/games", { token: lin.token });
  assert.deepEqual(listed.body.games.map((g: GameSummary) => [g.id, g.status]), [[gameId, "finished"]]);
});

test("club pages list club games for members; renames reach the seats; only the creator deletes", async () => {
  const cloud = makeCloud({ seed: 11 });
  const [mei, lin, sam, kim] = [await cloud.signIn("Mei"), await cloud.signIn("Lin"), await cloud.signIn("Sam"), await cloud.signIn("Kim")];
  const clubId = await clubOf(cloud, mei, [lin, sam]);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { bot: "standard" }, { userId: lin.id }, { bot: "standard" }]);

  const page = await cloud.call("GET", `/v1/clubs/${clubId}`, { token: sam.token });
  assert.equal(page.status, 200);
  assert.deepEqual(page.body.games.map((g: GameSummary) => [g.id, g.yourTurn]), [[gameId, false]]);
  assert.equal(page.body.games[0].players[0].name, "Mei", "someone not seated sees the table from seat 0");
  assert.equal(page.body.games[0].lastEvent, "Mei started the game");
  assert.equal((await cloud.call("GET", `/v1/clubs/${clubId}`, { token: kim.token })).status, 404);
  assert.deepEqual((await cloud.call("GET", "/v1/games", { token: sam.token })).body.games, []);

  const renamed = await cloud.call("PATCH", "/v1/me", { token: lin.token, body: { displayName: "  Lin   Wei " } });
  assert.deepEqual(renamed.body, { user: { id: lin.id, displayName: "Lin Wei" } });
  await cloud.settle();
  const forMei = await read(cloud, mei, gameId);
  assert.equal(forMei.view.players[2].name, "Lin Wei");
  assert.equal(forMei.game.players[2].name, "Lin Wei");
  const list = await cloud.call("GET", "/v1/games", { token: mei.token });
  assert.equal(list.body.games[0].players[2].name, "Lin Wei", "the Hub's index has the new name too");

  const notCreator = await cloud.call("DELETE", `/v1/games/${gameId}`, { token: lin.token });
  assert.deepEqual([notCreator.status, notCreator.body.error], [403, "forbidden"]);
  assert.equal((await cloud.call("DELETE", `/v1/games/${gameId}`, { token: sam.token })).status, 403);
  assert.equal((await cloud.call("DELETE", `/v1/games/${gameId}`, { token: mei.token })).status, 204);
  assert.ok(cloud.closed.has(gameId), "live sockets are closed");
  assert.equal((await cloud.call("GET", `/v1/games/${gameId}`, { token: mei.token })).status, 404);
  assert.equal((await cloud.call("POST", `/v1/games/${gameId}/actions`, { token: mei.token, body: { version: 1, action: { type: "pass" } } })).status, 404);
  assert.deepEqual((await cloud.call("GET", "/v1/games", { token: lin.token })).body.games, []);
  assert.deepEqual((await cloud.call("GET", `/v1/clubs/${clubId}`, { token: mei.token })).body.games, []);
  assert.equal((await cloud.call("DELETE", `/v1/games/${gameId}`, { token: mei.token })).status, 404);
});

test("a rename is a change like any other: the version grows, so clients that keep only newer versions see it", async () => {
  // The app keeps an update only when its version is newer than the one it has (HTTP replies and
  // WebSocket updates can arrive in any order), so a new name under the same version never shows.
  const cloud = makeCloud({ seed: 12 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const clubId = await clubOf(cloud, mei, [lin]);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { bot: "standard" }, { userId: lin.id }, { bot: "standard" }]);
  const before = await read(cloud, mei, gameId);
  const broadcasts = cloud.broadcasts.get(gameId) ?? 0;
  assert.equal((await cloud.call("PATCH", "/v1/me", { token: lin.token, body: { displayName: "Lin Wei" } })).status, 200);
  await cloud.settle();
  const after = await read(cloud, mei, gameId);
  assert.equal(after.view.players[2].name, "Lin Wei");
  assert.ok(after.version > before.version, `version ${after.version} after the rename, ${before.version} before`);
  assert.equal(cloud.broadcasts.get(gameId), broadcasts + 1, "connected players get the new name");
  const listed = (await cloud.call("GET", "/v1/games", { token: mei.token })).body.games[0] as GameSummary;
  assert.equal(listed.players[2].name, "Lin Wei");
  const log = cloud.rooms.get(gameId)!.service.log();
  assert.equal(log.at(-1)?.version, after.version);
  assert.equal(log.at(-1)?.kind, "rename");
  // The old version is stale now; the same name again changes nothing.
  const stale = await cloud.call("POST", `/v1/games/${gameId}/actions`, {
    token: mei.token,
    body: { version: before.version, action: moveFrom(before.view) },
  });
  assert.equal(stale.status, 409);
  assert.equal((await cloud.call("PATCH", "/v1/me", { token: lin.token, body: { displayName: "Lin Wei" } })).status, 200);
  await cloud.settle();
  assert.equal((await read(cloud, mei, gameId)).version, after.version);
});

test("an accepted move is answered and pushed even when the games index can't be updated right then", async () => {
  const cloud = makeCloud({ seed: 13 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const clubId = await clubOf(cloud, mei, [lin]);
  await cloud.call("POST", "/v1/devices", { token: lin.token, body: { platform: "ios", token: "bb".repeat(32), environment: "sandbox" } });
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }]);
  const original = cloud.hub.gameChanged.bind(cloud.hub);
  let failures = 0;
  cloud.hub.gameChanged = async () => {
    failures++;
    throw new Error("Durable Object reset because its code was updated");
  };
  const t = await read(cloud, mei, gameId);
  const reply = await cloud.call("POST", `/v1/games/${gameId}/actions`, { token: mei.token, body: { version: t.version, action: { type: "pass" } } });
  assert.equal(reply.status, 200, "the move was made; the reply says so");
  assert.ok(failures >= 1);
  await cloud.settle();
  assert.equal(cloud.push.sent.length, 1, "Lin still hears it is her turn");
  assert.equal(cloud.push.sent[0].title, "Your turn");
  assert.ok(cloud.logs.some((line) => line.includes("games index")), "the failure is logged");
  // The index catches up with the next change.
  cloud.hub.gameChanged = original;
  const linTable = await read(cloud, lin, gameId);
  const next = await cloud.call("POST", `/v1/games/${gameId}/actions`, {
    token: lin.token,
    body: { version: linTable.version, action: { type: "pass" } },
  });
  assert.equal(next.status, 200);
  const listed = (await cloud.call("GET", "/v1/games", { token: mei.token })).body.games as GameSummary[];
  const current = await read(cloud, mei, gameId);
  assert.deepEqual(listed, [current.game]);
});

test("a Hub that was reset is reached again at once: a room never keeps a broken Hub stub", async () => {
  // workerd breaks a stub for good once the object behind it is reset (checked in wrangler dev):
  // every later call on it fails the same way. A room that kept one Hub stub retried on it in
  // vain, and until the room was evicted no move reached the game lists and every delete was 500.
  const cloud = makeCloud({ seed: 16 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const clubId = await clubOf(cloud, mei, [lin]);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }]);
  const listed = async (player: Player) => (await cloud.call("GET", "/v1/games", { token: player.token })).body.games as GameSummary[];

  // The Hub is reset while it handles the index update of Mei's move: the retry gets through.
  const original = cloud.hub.gameChanged.bind(cloud.hub);
  let calls = 0;
  cloud.hub.gameChanged = async (snapshot) => {
    calls++;
    if (calls === 1) {
      cloud.resetHub();
      throw new Error(HUB_RESET_ERROR);
    }
    return original(snapshot);
  };
  const t = await read(cloud, mei, gameId);
  const moved = await cloud.call("POST", `/v1/games/${gameId}/actions`, { token: mei.token, body: { version: t.version, action: { type: "pass" } } });
  assert.equal(moved.status, 200);
  assert.equal(calls, 2);
  assert.deepEqual(await listed(lin), [(await read(cloud, lin, gameId)).game], "Lin's list shows it is her turn");
  assert.ok(!cloud.logs.some((line) => line.includes("games index")), cloud.logs.join("\n"));

  // Reset again between requests: the next move and the delete reach the new Hub.
  cloud.resetHub();
  const linTable = await read(cloud, lin, gameId);
  const next = await cloud.call("POST", `/v1/games/${gameId}/actions`, { token: lin.token, body: { version: linTable.version, action: { type: "pass" } } });
  assert.equal(next.status, 200);
  assert.deepEqual(await listed(mei), [(await read(cloud, mei, gameId)).game]);
  cloud.resetHub();
  assert.equal((await cloud.call("DELETE", `/v1/games/${gameId}`, { token: mei.token })).status, 204);
  assert.deepEqual(await listed(lin), []);
  assert.ok(!cloud.logs.some((line) => line.includes("games index")), cloud.logs.join("\n"));
});

test("deleting a game while the Hub can't be reached leaves no ghost in anyone's list", async () => {
  const cloud = makeCloud({ seed: 14 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const clubId = await clubOf(cloud, mei, [lin]);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }]);
  const original = cloud.hub.gameDeleted.bind(cloud.hub);
  cloud.hub.gameDeleted = async () => {
    throw new Error("Hub overloaded");
  };
  const failed = await cloud.call("DELETE", `/v1/games/${gameId}`, { token: mei.token });
  assert.equal(failed.status, 500);
  assert.equal((await cloud.call("GET", `/v1/games/${gameId}`, { token: lin.token })).status, 200, "nothing was deleted");
  assert.ok(!cloud.closed.has(gameId));
  cloud.hub.gameDeleted = original;
  assert.equal((await cloud.call("DELETE", `/v1/games/${gameId}`, { token: mei.token })).status, 204, "trying again works");
  assert.deepEqual((await cloud.call("GET", "/v1/games", { token: lin.token })).body.games, []);
  assert.equal((await cloud.call("GET", `/v1/games/${gameId}`, { token: lin.token })).status, 404);
});

test("a nudge refused as too soon says when the next one is allowed (retry-after)", async () => {
  const cloud = makeCloud({ seed: 15 });
  const [mei, lin] = [await cloud.signIn("Mei"), await cloud.signIn("Lin")];
  const clubId = await clubOf(cloud, mei, [lin]);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { userId: lin.id }, { bot: "standard" }, { bot: "standard" }]);
  assert.equal((await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token })).status, 204);
  const soon = await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token });
  assert.deepEqual([soon.status, soon.body.error, soon.headers.get("retry-after")], [429, "too_soon", "600"]);
  cloud.clock.now += 7 * 60 * 1000 + 500;
  const later = await cloud.call("POST", `/v1/games/${gameId}/nudge`, { token: lin.token });
  assert.deepEqual([later.status, later.headers.get("retry-after")], [429, "180"]);
});

test("bot turns left over by an interrupted request run on the next read", async () => {
  const cloud = makeCloud({ seed: 5 });
  const mei = await cloud.signIn("Mei");
  const clubId = await clubOf(cloud, mei, []);
  const gameId = await newGame(cloud, mei, clubId, [{ userId: mei.id }, { bot: "standard" }, { bot: "standard" }, { bot: "standard" }]);
  const room = cloud.rooms.get(gameId)!;
  // Simulate a stop right after Mei's pass: the stored state has East (a bot) to bid.
  const state = room.service.load()!;
  const broken = structuredClone(state);
  E.bid(broken.round, 0, "pass");
  broken.version += 1;
  (room.service as unknown as { save(s: unknown, l: unknown[]): void }).save(broken, [
    { version: broken.version, seat: 0, kind: "action", data: { type: "pass" } },
  ]);
  const t = await read(cloud, mei, gameId);
  assert.ok(t.version > broken.version, "the bots caught up");
  assert.ok(isMyTurn(t.view) || t.view.phase !== "bidding", "the game waits for Mei again");
});
