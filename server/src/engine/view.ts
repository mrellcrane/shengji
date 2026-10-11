// The per-seat view of a round in absolute seats: everything one player is allowed to see (DESIGN.md,
// Privacy). The wire format the server sends is `SeatView` in seatview.ts (viewer-relative, Swift shape).
//
// Hidden from a seat: the other hands, the undealt cards, and the kitty, except that the dealer
// sees the kitty while holding it (burying) and after burying it, and everyone sees it once the
// round is finished. Public by the rules, and therefore in every view: cards revealed to declare
// (declarations and bids), the kitty card turned up to fix trump when nobody declared
// (`trumpFromKitty`), every play of the current and past tricks, the friends the dealer called
// (Finding Friends, once buried) with whoever has played a called card, and the result.

import type { Card, Rank } from "./cards.ts";
import { copyCall } from "./friends.ts";
import type { FriendCall } from "./friends.ts";
import type { Play } from "./rules.ts";
import { availableBids, declarerTeam, declarers, friendCallsOf, turn } from "./round.ts";
import type { Bid, Declaration, Round, RoundPhase, RoundResult, TrickRecord } from "./round.ts";
import { sortCards } from "./trump.ts";
import type { Trump } from "./trump.ts";

export interface BiddingView {
  firstBidder: number;
  /** Seat to bid next; null once bidding has ended. */
  turn: number | null;
  passes: number;
  bids: Bid[];
}

export interface RoundView {
  /** The seat this view belongs to. */
  seat: number;
  phase: RoundPhase;
  trumpRank: Rank;
  trump: Trump;
  /** Null only before the first round's dealer is known. */
  dealer: number | null;
  declarerTeam: number | null;
  /**
   * Seats of the declaring team (dealer first, then in play order); empty while unknown. With
   * Finding Friends the dealer and the friends found so far.
   */
  declarers: number[];
  /** Finding Friends: the friends the dealer called (empty before burying and at tables of fixed teams). */
  friendCalls: FriendCall[];
  /** This seat's own cards, in display order. */
  hand: Card[];
  /** Number of cards in each seat's hand. */
  handCounts: number[];
  undealtCount: number;
  kittyCount: number;
  /**
   * The kitty when this seat may see it: the dealer during burying (the cards picked up) and after
   * burying (the cards buried); everyone once the round is finished. Otherwise null.
   */
  kitty: Card[] | null;
  declaration: Declaration | null;
  declarationHistory: Declaration[];
  /** If nobody declared, the kitty card turned up that fixed trump (shown to everyone). */
  trumpFromKitty: Card | null;
  bidding: BiddingView | null;
  /** Declarations this seat may bid right now (empty unless it is their bidding turn). */
  availableBids: Declaration[];
  /** Seat to play next (null outside "playing"). */
  turn: number | null;
  /** Seat leading the current trick. */
  leader: number;
  currentTrick: Play[];
  tricks: TrickRecord[];
  /** Points the defenders have captured in tricks so far. */
  defenderPoints: number;
  /** Set when the round is finished. */
  result: RoundResult | null;
}

/** True if `seat` may see the kitty now. */
export function canSeeKitty(round: Round, seat: number): boolean {
  if (round.phase === "finished") return true;
  if (round.phase === "burying" || round.phase === "playing") return round.dealer === seat;
  return false;
}

function copyPlays(plays: readonly Play[]): Play[] {
  return plays.map((p) => ({ player: p.player, cards: p.cards.slice() }));
}

function copyDeclaration(d: Declaration): Declaration {
  return { player: d.player, cards: d.cards.slice(), suit: d.suit, strength: d.strength };
}

/** The view of `round` for `seat` (0...3, or up to 8 at a bigger table). Shares no objects with `round`. */
export function viewFor(round: Round, seat: number): RoundView {
  if (!Number.isInteger(seat) || seat < 0 || seat >= round.hands.length) {
    throw new RangeError(`seat must be 0...${round.hands.length - 1}, got ${seat}`);
  }
  const team = declarerTeam(round);
  return {
    seat,
    phase: round.phase,
    trumpRank: round.trumpRank,
    trump: { rank: round.trump.rank, suit: round.trump.suit },
    dealer: round.dealer,
    declarerTeam: team,
    declarers: declarers(round),
    friendCalls: friendCallsOf(round).map(copyCall),
    hand: sortCards(round.trump, round.hands[seat]),
    handCounts: round.hands.map((hand) => hand.length),
    undealtCount: round.undealt.length,
    kittyCount: round.kitty.length,
    kitty: canSeeKitty(round, seat) ? round.kitty.slice() : null,
    declaration: round.declaration === null ? null : copyDeclaration(round.declaration),
    declarationHistory: round.declarationHistory.map(copyDeclaration),
    trumpFromKitty: round.trumpFromKitty,
    bidding:
      round.bidding === null
        ? null
        : {
            firstBidder: round.bidding.firstBidder,
            turn: round.bidding.turn,
            passes: round.bidding.passes,
            bids: round.bidding.bids.map((b) => ({
              seat: b.seat,
              declaration: b.declaration === null ? null : copyDeclaration(b.declaration),
            })),
          },
    availableBids: availableBids(round, seat).map(copyDeclaration),
    turn: turn(round),
    leader: round.leader,
    currentTrick: copyPlays(round.currentTrick),
    tricks: round.tricks.map((t) => ({ plays: copyPlays(t.plays), winner: t.winner, points: t.points })),
    defenderPoints: round.defenderTrickPoints,
    result: round.result === null ? null : structuredClone(round.result),
  };
}
