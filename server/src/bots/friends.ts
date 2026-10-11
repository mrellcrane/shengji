// Finding Friends: the friends a dealer calls when burying (DESIGN.md §Finding Friends). Port of
// ShengjiCore/Sources/ShengjiCore/Bots/BotFriends.swift (`BotFriends.calls`), choices only.
//
// For each plain suit, the highest card the dealer holds no copy of (so someone else answers the
// call), one suit per friend: suits the dealer still holds cards of first (they can lead one low and
// let the friend win it), shortest first, then in suit order. If that is not enough, the next card
// down in the same order; failing that, the second copy of the cards already called.

import { ALL_RANKS, ALL_SUITS, faceOf, regularFace, suitOf, tableFriendCount, without } from "../engine/cards.ts";
import type { Card, Face, Rank, Suit } from "../engine/cards.ts";
import { friendCall } from "../engine/friends.ts";
import type { FriendCall } from "../engine/friends.ts";
import { viewTable } from "../engine/seatview.ts";
import type { SeatView } from "../engine/seatview.ts";
import { isTrump } from "../engine/trump.ts";

/**
 * The friends the dealer viewing `view` (phase "burying") calls when burying `buried`: exactly
 * `tableFriendCount` calls, all legal; empty at a table of fixed teams. Swift `Bot.friendCalls(view:buried:)`.
 */
export function friendCalls(view: SeatView, buried: readonly Card[]): FriendCall[] {
  const table = viewTable(view);
  const needed = tableFriendCount(table);
  if (needed <= 0) return [];
  const hand = without(view.hand, buried);
  const trump = view.trump;
  const counts = new Map<Face, number>();
  for (const card of hand) counts.set(faceOf(card), (counts.get(faceOf(card)) ?? 0) + 1);
  const held = (suit: Suit, rank: Rank): number => counts.get(regularFace(rank, suit)) ?? 0;
  const ranks = ALL_RANKS.slice().reverse().filter((rank) => rank !== trump.rank);
  const suits = ALL_SUITS.filter((suit) => suit !== trump.suit);
  const length = [0, 0, 0, 0];
  for (const card of hand) {
    if (isTrump(trump, card)) continue;
    const suit = suitOf(card);
    if (suit !== null) length[suit] += 1;
  }
  // Suits still held first, then shortest first, then in suit order.
  const ordered = suits.slice().sort((a, b) => {
    const la = length[a];
    const lb = length[b];
    if ((la === 0) !== (lb === 0)) return la !== 0 ? -1 : 1;
    if (la !== lb) return la - lb;
    return a - b;
  });

  const calls: FriendCall[] = [];
  // One unheld card per suit, highest first; then the next unheld card down, suit by suit.
  for (let depth = 0; calls.length < needed && depth < ranks.length; depth++) {
    for (const suit of ordered) {
      if (calls.length >= needed) break;
      const unheld = ranks.filter((rank) => held(suit, rank) === 0);
      if (depth >= unheld.length) continue;
      calls.push(friendCall(regularFace(unheld[depth], suit)));
    }
  }
  // The dealer holds every card: call later copies of the top cards.
  for (let ordinal = 2; calls.length < needed && ordinal <= Math.max(table.decks, 1); ordinal++) {
    for (const suit of ordered) {
      if (calls.length >= needed || ranks.length === 0) break;
      calls.push(friendCall(regularFace(ranks[0], suit), ordinal));
    }
  }
  return calls;
}
