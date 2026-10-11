// Checks on SeatView JSON as a client receives it, used by the unit tests and by the smoke test
// (which only sees what the server sends, so it checks structure and cross-checks two players).

import { tableCardCount, tableKittySize } from "../src/engine/cards.ts";
import { viewTable } from "../src/engine/seatview.ts";
import type { SeatView } from "../src/engine/seatview.ts";

/** The exact key set of a SeatView (the Swift Codable). Nothing else may travel in a view. */
export const SEAT_VIEW_KEYS = [
  "players",
  "teamLevels",
  "targetRank",
  "roundNumber",
  "phase",
  "trump",
  "trumpFromKitty",
  "dealer",
  "hand",
  "handCounts",
  "declaration",
  "declarationHistory",
  "bidding",
  "kitty",
  "currentTrick",
  "leader",
  "turn",
  "tricks",
  "defenderTrickPoints",
  "result",
  "lastRoundSummary",
  "gameWinnerTeam",
].sort();

/** Cards revealed by the rules this round: declarations, bids, the kitty flip, everything played. */
export function publicCardsOf(view: SeatView): Set<number> {
  const out = new Set<number>();
  for (const d of view.declarationHistory) for (const c of d.cards) out.add(c);
  if (view.declaration) for (const c of view.declaration.cards) out.add(c);
  for (const b of view.bidding?.history ?? []) for (const c of b.declaration?.cards ?? []) out.add(c);
  if (view.trumpFromKitty !== null && view.trumpFromKitty !== undefined) out.add(view.trumpFromKitty);
  for (const p of view.currentTrick) for (const c of p.cards) out.add(c);
  for (const t of view.tricks) for (const p of t.plays) for (const c of p.cards) out.add(c);
  return out;
}

/** Every card id the view mentions for the current round (not the previous round's summary). */
export function roundCardsOf(view: SeatView): number[] {
  const out = [...view.hand, ...(view.kitty ?? []), ...publicCardsOf(view)];
  for (const d of view.bidding?.available ?? []) out.push(...d.cards);
  if (view.result) out.push(...view.result.kitty);
  return out;
}

/** Problems with one view on its own: shape, counts, and the kitty only where allowed. */
export function checkSeatView(view: SeatView): string[] {
  const problems: string[] = [];
  const keys = Object.keys(view).sort();
  if (keys.join(",") !== SEAT_VIEW_KEYS.join(",")) problems.push(`unexpected keys: ${keys.join(",")}`);
  if (view.hand.length !== view.handCounts[0]) problems.push("hand size differs from handCounts[0]");
  if (![4, 6, 8].includes(view.handCounts.length) || view.players.length !== view.handCounts.length) {
    problems.push(`${view.players.length} players and ${view.handCounts.length} hand counts`);
  }
  const table = viewTable(view);
  const cardCount = tableCardCount(table);
  if (new Set(view.hand).size !== view.hand.length) problems.push("a card appears twice in the hand");
  const kittyAllowed =
    view.phase === "finished" || ((view.phase === "burying" || view.phase === "playing") && view.dealer === 0);
  if (view.kitty !== null && view.kitty !== undefined && !kittyAllowed) problems.push(`kitty visible in ${view.phase}`);
  const played = new Set<number>();
  for (const t of view.tricks) for (const p of t.plays) for (const c of p.cards) played.add(c);
  for (const p of view.currentTrick) for (const c of p.cards) played.add(c);
  for (const card of view.hand) if (played.has(card)) problems.push(`card ${card} is both in hand and played`);
  // Every card is somewhere: in a hand (counted), played, or in the kitty (8, or 6 with 6 players;
  // none while the dealer holds it during burying).
  const inHands = view.handCounts.reduce((a, b) => a + b, 0);
  const kittySize = view.phase === "burying" ? 0 : tableKittySize(table);
  if (view.phase !== "finished" && inHands + played.size + kittySize !== cardCount) {
    problems.push(`cards do not add up: ${inHands} in hands, ${played.size} played`);
  }
  if (view.bidding !== null && view.bidding !== undefined && view.bidding.turn !== 0 && view.bidding.available.length > 0) {
    problems.push("bids offered when it is not the viewer's turn");
  }
  for (const card of roundCardsOf(view)) {
    if (!Number.isInteger(card) || card < 0 || card >= cardCount) problems.push(`bad card id ${card}`);
  }
  return problems;
}

/**
 * Problems between two players' views of the same moment: neither may show any card the other
 * holds, except cards both can see by the rules (declared ones are public).
 */
export function crossCheck(a: SeatView, b: SeatView): string[] {
  const problems: string[] = [];
  const check = (viewer: SeatView, other: SeatView, label: string) => {
    const shown = new Set(viewer.hand);
    for (const card of viewer.kitty ?? []) shown.add(card);
    for (const d of viewer.bidding?.available ?? []) for (const c of d.cards) shown.add(c);
    const publicCards = publicCardsOf(viewer);
    for (const card of other.hand) {
      if (shown.has(card) && !publicCards.has(card)) problems.push(`${label} sees card ${card} from the other hand`);
    }
  };
  check(a, b, "first");
  check(b, a, "second");
  return problems;
}
