// Privacy (DESIGN.md): nothing a player receives may reveal a card they cannot see: other hands,
// or the kitty unless they are the dealer holding or having buried it, or the round is over.
// Checked over many random games (any mix of people and bots, random legal moves including failing
// throws), for every state a client can receive and every seat (tables of 4, 6 and 8), in every message: the action
// replies, the WebSocket updates (view and game summary), the summaries in game lists (also for a
// club member who is not seated) and their lastEvent text. The strongest check: shuffling the cards
// a seat cannot see among their hidden places never changes what that seat receives.

import assert from "node:assert/strict";
import { test } from "node:test";
import * as E from "../src/engine/index.ts";
import type { Card, Round } from "../src/engine/index.ts";
import { actingSeat, playersOf, snapshotOf } from "../src/game/online.ts";
import type { OnlineGame, SeatAction, SeatAssignment } from "../src/game/online.ts";
import { summarize } from "../src/game/summary.ts";
import { RoomService } from "../src/room/service.ts";
import { checkSeatView } from "../scripts/viewcheck.ts";
import { randomFollow, randomLead } from "./play.ts";
import { seededRandom } from "./support.ts";
import type { Rng } from "./support.ts";
import { seededSource } from "./cloud.ts";
import { memorySql } from "./sqlite.ts";

/** Cards revealed by the rules this round: declarations, bids, the kitty flip card, all plays. */
function publicCards(round: Round): Set<Card> {
  const cards = new Set<Card>();
  for (const d of round.declarationHistory) for (const c of d.cards) cards.add(c);
  for (const b of round.bidding?.bids ?? []) for (const c of b.declaration?.cards ?? []) cards.add(c);
  if (round.trumpFromKitty !== null) cards.add(round.trumpFromKitty);
  for (const c of E.playedCards(round)) cards.add(c);
  return cards;
}

/** The cards absolute seat `seat` must not learn about. */
function hiddenFrom(round: Round, seat: number): Set<Card> {
  const hidden = new Set<Card>();
  round.hands.forEach((hand, s) => {
    if (s !== seat) for (const c of hand) hidden.add(c);
  });
  for (const c of round.undealt) hidden.add(c);
  if (!E.kittyVisibleTo(round, seat)) for (const c of round.kitty) hidden.add(c);
  for (const c of round.hands[seat]) hidden.delete(c);
  for (const c of publicCards(round)) hidden.delete(c);
  return hidden;
}

const CARD_LISTS = new Set(["hand", "kitty", "cards", "forced"]);

/** Card ids anywhere in a message, except the previous round's summary (another deal). */
function cardsIn(value: unknown, out: Card[] = []): Card[] {
  if (Array.isArray(value)) {
    for (const item of value) cardsIn(item, out);
  } else if (value !== null && typeof value === "object") {
    for (const [key, v] of Object.entries(value)) {
      if (key === "lastRoundSummary") continue;
      if (CARD_LISTS.has(key) && Array.isArray(v)) {
        for (const c of v) if (typeof c === "number") out.push(c);
      } else if (key === "trumpFromKitty" && typeof v === "number") {
        out.push(v);
      } else {
        cardsIn(v, out);
      }
    }
  }
  return out;
}

const CARD_TEXT = /(10|[2-9JQKA])([♠♥♣♦])|SJ|BJ/gu;
const SUITS = "♠♥♣♦";
const RANKS: Record<string, number> = { J: 11, Q: 12, K: 13, A: 14 };

/** Faces named in a text ("K♠ K♠" -> the face of K♠). */
function facesInText(text: string): number[] {
  const faces: number[] = [];
  for (const match of text.matchAll(CARD_TEXT)) {
    if (match[0] === "SJ") faces.push(52);
    else if (match[0] === "BJ") faces.push(53);
    else faces.push(SUITS.indexOf(match[2]) * 13 + ((RANKS[match[1]] ?? Number(match[1])) - 2));
  }
  return faces;
}

/** The round with the cards hidden from `seat` swapped among their places at random. */
function permuteHidden(round: Round, seat: number, rng: Rng): Round {
  const hidden = Array.from(hiddenFrom(round, seat)).sort((a, b) => a - b);
  const image = rng.shuffle(hidden);
  const map = new Map(hidden.map((c, i) => [c, image[i]]));
  const swap = (c: Card) => map.get(c) ?? c;
  const copy = E.cloneRound(round);
  copy.hands = copy.hands.map((hand, s) => (s === seat ? hand : hand.map(swap)));
  copy.undealt = copy.undealt.map(swap);
  copy.kitty = copy.kitty.map(swap);
  return copy;
}

interface Tally {
  states: number;
  messages: number;
  phases: Set<string>;
  failedThrows: number;
  kittyShown: number;
}

function checkState(service: RoomService, state: OnlineGame, rng: Rng, tally: Tally, extra: { seat: number; message: unknown }[] = []): void {
  const round = state.round;
  const publicFaces = new Set(Array.from(publicCards(round), (c) => c % 54));
  tally.states++;
  for (let seat = 0; seat < state.seats.length; seat++) {
    const hidden = hiddenFrom(round, seat);
    const update = service.update(seat);
    assert.ok(update !== null);
    const messages: unknown[] = [JSON.parse(JSON.stringify(update)), ...extra.filter((e) => e.seat === seat).map((e) => e.message)];
    const snapshot = snapshotOf(state);
    messages.push(summarize(snapshot, seat), summarize(snapshot, null), snapshot);
    for (const message of messages) {
      tally.messages++;
      for (const card of cardsIn(message)) {
        assert.ok(!hidden.has(card), `seat ${seat} received hidden card ${E.cardDescription(card)} (${card}) in ${round.phase}`);
      }
    }
    // The view on its own is consistent, and the kitty appears exactly when allowed.
    const view = update.view;
    assert.deepEqual(checkSeatView(view), []);
    assert.equal(view.kitty !== null, E.kittyVisibleTo(round, seat));
    if (view.kitty !== null && round.phase !== "finished") tally.kittyShown++;
    tally.phases.add(view.phase);
    // The previous round's summary only shows that round's (public) kitty.
    const last = state.game.history.at(-1);
    assert.deepEqual(view.lastRoundSummary?.result.kitty ?? null, last?.result.kitty ?? null);
    // Last event lines only name public cards.
    for (const text of [update.game.lastEvent, summarize(snapshot, null).lastEvent]) {
      for (const face of facesInText(text ?? "")) {
        assert.ok(publicFaces.has(face), `lastEvent "${text}" names a card that is not public`);
      }
    }
    // Shuffling what this seat cannot see changes nothing it receives.
    const permuted = permuteHidden(round, seat, rng);
    const again = E.toSeatView(state.game, permuted, seat, playersOf(state));
    assert.deepEqual(again, view, `seat ${seat}'s view depends on hidden cards (${round.phase})`);
  }
}

function randomAction(round: Round, seat: number, rng: Rng): SeatAction {
  if (E.biddingTurn(round) === seat) {
    const options = E.availableBids(round, seat);
    if (options.length > 0 && rng.chance(35)) return { type: "bid", declaration: { ...rng.pick(options), player: 0 } };
    return { type: "pass" };
  }
  if (round.phase === "burying") return { type: "bury", cards: rng.sample(round.hands[seat], E.kittySizeOf(round)) };
  const hand = round.hands[seat];
  if (round.currentTrick.length === 0) return { type: "play", cards: randomLead(hand, round.trump, rng) };
  return { type: "play", cards: randomFollow(hand, E.currentLead(round), round.trump, rng) };
}

/** Plays random games through a RoomService and checks every state; returns what was seen. */
function randomGames(games: number, seed: number, players: (g: number) => number, rounds: number): Tally {
  const tally: Tally = { states: 0, messages: 0, phases: new Set(), failedThrows: 0, kittyShown: 0 };
  for (let g = 0; g < games; g++) {
    const rng = seededRandom(seed + g);
    const all = E.allSeats(players(g));
    const humans = 1 + rng.below(Math.min(4, all.length));
    const humanSeats = rng.sample(all, humans);
    const seats: SeatAssignment[] = all.map((s) =>
      humanSeats.includes(s)
        ? { userId: `u_player${s}`, bot: null, name: `P${s}` }
        : { userId: null, bot: rng.chance(50) ? "standard" : "beginner", name: `Bot ${s}` },
    );
    let now = Date.UTC(2026, 3, 1);
    const service = new RoomService(memorySql(), { deck: (table) => E.shuffle(E.deckCards(table.decks), seededSource(g * 7 + 1)), now: () => new Date((now += 1000)) });
    const creator = seats[humanSeats[0]].userId as string;
    assert.ok(service.create({ id: `g_${g}`, clubId: "c_club", clubName: "Club", createdBy: creator, seats, targetRank: rng.pick([5, 10, 14] as E.Rank[]) }).ok);
    for (let step = 0; step < 80 * rounds; step++) {
      const state = service.load() as OnlineGame;
      if (state.status === "finished" || state.game.roundsPlayed >= rounds) {
        checkState(service, state, rng, tally);
        break;
      }
      const seat = actingSeat(state.round) as number;
      const userId = state.seats[seat].userId;
      assert.ok(userId !== null, "the stored state always waits for a person");
      const action = randomAction(state.round, seat, rng);
      const result = service.act(userId, { version: state.version, action });
      assert.ok(result.ok, result.ok ? "" : result.message);
      if (result.value.body.outcome?.type === "throwFailed") tally.failedThrows++;
      checkState(service, service.load() as OnlineGame, rng, tally, [{ seat, message: JSON.parse(JSON.stringify(result.value.body)) }]);
    }
  }
  return tally;
}

test("no message ever reveals a hidden card, for any seat, over many random games", () => {
  const tally = randomGames(36, 9100, () => 4, 2);
  assert.ok(tally.states > 1500, `${tally.states} states`);
  assert.deepEqual([...tally.phases].sort(), ["bidding", "burying", "finished", "playing"].filter((p) => tally.phases.has(p)));
  for (const phase of ["bidding", "burying", "playing"]) assert.ok(tally.phases.has(phase), `never saw ${phase}`);
  assert.ok(tally.failedThrows > 0, "no failed throw was exercised");
  assert.ok(tally.kittyShown > 0, "the dealer never saw the kitty");
});

test("tables of 6 and 8: no message reveals a hidden card to any of the seats", () => {
  const tally = randomGames(10, 9600, (g) => (g % 2 === 0 ? 6 : 8), 1);
  assert.ok(tally.states > 300, `${tally.states} states`);
  for (const phase of ["bidding", "burying", "playing"]) assert.ok(tally.phases.has(phase), `never saw ${phase}`);
  assert.ok(tally.kittyShown > 0, "the dealer never saw the kitty");
});

test("the privacy check itself catches a leak (a hand card planted in another seat's view)", () => {
  const rng = seededRandom(1);
  const seats: SeatAssignment[] = [0, 1, 2, 3].map((s) => ({ userId: `u_p${s}`, bot: null, name: `P${s}` }));
  const service = new RoomService(memorySql(), { deck: (table) => E.shuffle(E.deckCards(table.decks), seededSource(3)), now: () => new Date(0) });
  assert.ok(service.create({ id: "g_x", clubId: "c", clubName: "C", createdBy: "u_p0", seats, targetRank: 14 }).ok);
  const state = service.load() as OnlineGame;
  const leaked = JSON.parse(JSON.stringify(service.update(1))) as { view: { hand: Card[] } };
  leaked.view.hand.push(state.round.hands[2][0]);
  assert.throws(() => checkState(service, state, rng, { states: 0, messages: 0, phases: new Set(), failedThrows: 0, kittyShown: 0 }, [{ seat: 1, message: leaked }]));
  const planted = E.cloneRound(state.round);
  assert.notDeepEqual(permuteHidden(planted, 0, rng).hands[1], planted.hands[1]);
});
