// One deal ("round") from dealing to scoring. Port of Engine/Round.swift, plus the online
// turn-based bidding variant (DESIGN.md, Online multiplayer), which has no Swift counterpart.
//
// A `Round` is plain JSON-serialisable data (it is stored in Durable Object storage). The
// functions below mutate it in place, like the Swift mutating methods, and never change it when
// they report an error: every check runs before the first mutation. Use `cloneRound` for a copy.

import {
  BIG_JOKER_FACE,
  MAX_DECKS,
  SMALL_JOKER_FACE,
  TABLE_FOUR,
  cardDescription,
  containsAll,
  faceOf,
  isCard,
  isFullDeck,
  isJoker,
  isSuit,
  rankOf,
  regularFace,
  removeCards,
  shortText,
  suitOf,
  suitSymbol,
  tableCardCount,
  tableHandSize,
  tableKittySize,
  tableSize,
  totalPoints,
} from "./cards.ts";
import type { Card, Rank, Suit, TableSize } from "./cards.ts";
import {
  HUMAN_SEAT,
  checkThrow,
  countWord,
  followViolationExplanation,
  isThrow,
  leadViolationExplanation,
  nextSeat,
  normalizeSeat,
  seatName,
  teamOf,
  validateFollow,
  validateLead,
  winningIndex,
} from "./rules.ts";
import type { FollowViolation, LeadViolation, Play } from "./rules.ts";
import { kittyMultiplier, scoreOutcome } from "./scoring.ts";
import type { LevelOutcome } from "./scoring.ts";
import type { Trump } from "./trump.ts";

/** Kitty and hand sizes of the classic 4-player, 2-deck game (`kittySizeOf` and `handSizeOf` give a round's own). */
export const KITTY_SIZE = 8;
export const HAND_SIZE = 25;

// MARK: Declarations

/** A bid for trump made by revealing cards (亮主). */
export interface Declaration {
  player: number;
  /** The revealed cards: trump-rank cards of one suit, or identical jokers (two or more). */
  cards: Card[];
  /** Trump suit chosen; null = no trump suit (jokers). */
  suit: Suit | null;
  /**
   * 1 = single rank card, 2 = pair of rank cards, 3 = pair of small jokers, 4 = pair of big jokers.
   * With three or more decks more cards beat fewer: 5 = three rank cards, 6 = three small jokers,
   * 7 = three big jokers, then 8 to 10 for four of each (see `declarationStrength`).
   */
  strength: number;
}

/** What a declaration shows (Swift `Declaration.Kind`): 0 rank cards of one suit, 1 small jokers, 2 big jokers. */
export type DeclarationKind = 0 | 1 | 2;
export const RANK_CARDS = 0 as const;
export const SMALL_JOKERS = 1 as const;
export const BIG_JOKERS = 2 as const;

/**
 * Strength of showing `count` identical cards of `kind` (jokers need at least two): one rank card 1;
 * two: rank 2, small jokers 3, big jokers 4; three: 5, 6, 7; four: 8, 9, 10.
 */
export function declarationStrength(count: number, kind: DeclarationKind): number {
  if (count <= 1) return 1;
  return 3 * count - 4 + kind;
}

/** Cards shown for a strength (1 -> 1, 2...4 -> 2, 5...7 -> 3, 8...10 -> 4). */
export function declarationCardCount(strength: number): number {
  return strength <= 1 ? 1 : Math.trunc((strength + 4) / 3);
}

/** The kind of cards shown for a strength. */
export function declarationKind(strength: number): DeclarationKind {
  return strength <= 1 ? RANK_CARDS : ((((strength + 4) % 3) + 3) % 3) as DeclarationKind;
}

/** The cards shown, e.g. "one 2♥", "pair of 2♥", "three small jokers" (Swift `Declaration.detail`). */
export function declarationDetail(declaration: Declaration): string {
  const shown = declaration.cards.length > 0 ? cardDescription(declaration.cards[0]) : null;
  const strength = declaration.strength;
  switch (strength) {
    case 1:
      return shown === null ? "one trump-rank card" : `one ${shown}`;
    case 2:
      return shown === null ? "pair of trump-rank cards" : `pair of ${shown}`;
    case 3:
      return "pair of small jokers";
    case 4:
      return "pair of big jokers";
  }
  if (strength >= 5) {
    const count = countWord(declarationCardCount(strength));
    switch (declarationKind(strength)) {
      case RANK_CARDS:
        return shown === null ? `${count} trump-rank cards` : `${count} ${shown}`;
      case SMALL_JOKERS:
        return `${count} small jokers`;
      case BIG_JOKERS:
        return `${count} big jokers`;
    }
  }
  return shortText(declaration.cards);
}

/**
 * e.g. "East declares ♥ (one 2♥)", "You declare no trump (pair of big jokers)", "Northeast declares
 * ♠ (three 2♠)". Names are as seen from `viewer` at a table of `players` (default seat 0 and 4
 * players, which is exactly Swift `Declaration.description`; `description(players:)` with more).
 */
export function declarationDescription(declaration: Declaration, viewer = HUMAN_SEAT, players = 4): string {
  const who =
    declaration.player === viewer ? "You declare" : `${seatName(declaration.player, viewer, players)} declares`;
  const what = declaration.suit === null ? "no trump" : suitSymbol(declaration.suit);
  return `${who} ${what} (${declarationDetail(declaration)})`;
}

/**
 * Parses an untrusted value (e.g. a client message) into a well-formed Declaration, or null.
 * Only the shape is checked; `declare` and `bid` check that it is allowed. A missing `suit` means
 * no trump suit, as in the Swift app's JSON (its Codable leaves out nil optionals).
 */
export function parseDeclaration(value: unknown): Declaration | null {
  if (typeof value !== "object" || value === null) return null;
  const v = value as Record<string, unknown>;
  if (typeof v.player !== "number" || !Number.isInteger(v.player)) return null;
  if (!Array.isArray(v.cards) || v.cards.length > MAX_DECKS || !v.cards.every(isCard)) return null;
  const suit = v.suit === undefined ? null : v.suit;
  if (suit !== null && !isSuit(suit)) return null;
  if (typeof v.strength !== "number" || !Number.isInteger(v.strength)) return null;
  return { player: v.player, cards: (v.cards as Card[]).slice(), suit, strength: v.strength };
}

// MARK: Round data

export type RoundPhase =
  /** Cards are being dealt (offline) or bid on (online); players may declare trump. */
  | "dealing"
  /** Dealer has picked up the kitty and must bury as many cards (8, or 6 with 6 players). */
  | "burying"
  | "playing"
  | "finished";

export interface TrickRecord {
  plays: Play[];
  /** Player who won the trick. */
  winner: number;
  /** Point value of all cards in the trick. */
  points: number;
}

export function trickLeader(trick: TrickRecord): number {
  return trick.plays.length > 0 ? trick.plays[0].player : trick.winner;
}

export interface RoundResult {
  dealer: number;
  declarerTeam: number;
  trump: Trump;
  /** Points the defenders captured in tricks. */
  trickPoints: number;
  /** Raw point value of the buried kitty. */
  kittyPoints: number;
  /** 0 if the declarers won the last trick; otherwise 2/4/8/... (see kittyMultiplier). */
  kittyMultiplier: number;
  /** trickPoints + kittyPoints * kittyMultiplier. */
  defenderPoints: number;
  outcome: LevelOutcome;
  kitty: Card[];
  lastTrickWinner: number;
}

/** Outcome of a successful `play`. */
export type PlayOutcome =
  | { type: "played" }
  /** The lead was a throw that failed; only `forced` was played. `blocker` could beat part of it. */
  | { type: "throwFailed"; forced: Card[]; blocker: number };

export type RoundError =
  | { case: "wrongPhase" }
  | { case: "notYourTurn" }
  | { case: "illegalLead"; violation: LeadViolation }
  | { case: "illegalFollow"; violation: FollowViolation }
  | { case: "invalidDeclaration" }
  | { case: "invalidBury"; reason: string };

/** Learner-facing explanation. */
export function roundErrorExplanation(error: RoundError): string {
  switch (error.case) {
    case "wrongPhase":
      return "You can't do that at this point in the round.";
    case "notYourTurn":
      return "Wait for your turn.";
    case "illegalLead":
      return leadViolationExplanation(error.violation);
    case "illegalFollow":
      return followViolationExplanation(error.violation);
    case "invalidDeclaration":
      return (
        "You can't declare that right now. A declaration must beat the current one, " +
        "and if the current one is yours you can only strengthen it with more of the same card."
      );
    case "invalidBury":
      return error.reason;
  }
}

export type PlayResult = { ok: true; outcome: PlayOutcome } | { ok: false; error: RoundError };

/** One turn of online bidding: a declaration, or a pass (declaration null). */
export interface Bid {
  seat: number;
  declaration: Declaration | null;
}

/** State of the online turn-based declaring (see `startBidding`). */
export interface Bidding {
  /** Seat that bid first: the dealer, or the game creator's seat in round 1. */
  firstBidder: number;
  /** Seat to act next; null once bidding has ended. */
  turn: number | null;
  /** Passes in a row since the last declaration (or since bidding began). */
  passes: number;
  /** Every bid in order. */
  bids: Bid[];
}

/**
 * The complete state of one deal, from dealing to scoring. Field meanings match the Swift `Round`.
 * The table (4, 6 or 8 players) is the number of hands (`roundTable`).
 */
export interface Round {
  /** Trump rank for this round (the dealer team's level). */
  trumpRank: Rank;
  /** Dealer (庄家). Null only during the first round's deal, before anyone has declared. */
  dealer: number | null;
  phase: RoundPhase;
  /** One hand per seat (4, 6 or 8), indexed by seat. Not kept sorted; use `sortCards` for display. */
  hands: Card[][];
  /** Cards still to be dealt (dealing phase). */
  undealt: Card[];
  /**
   * During dealing and burying: the original kitty cards (face down; 8, or 6 with 6 players).
   * After burying: the cards the dealer buried.
   */
  kitty: Card[];
  /** Current winning declaration, if any. */
  declaration: Declaration | null;
  /** Every declaration in order. */
  declarationHistory: Declaration[];
  /** Trump context. During dealing `suit` reflects the current declaration (null if none yet). */
  trump: Trump;
  /** Seat that receives the next dealt card. */
  nextToReceive: number;
  /** Plays so far in the trick in progress (empty between tricks). */
  currentTrick: Play[];
  tricks: TrickRecord[];
  /** Seat that leads the current trick. */
  leader: number;
  /** Points captured by the defenders in tricks so far. */
  defenderTrickPoints: number;
  /** If nobody declared, the kitty card that fixed the trump suit. */
  trumpFromKitty: Card | null;
  /** Set when phase is "finished". */
  result: RoundResult | null;
  /** Online turn-based declaring; null in the offline deal-and-declare flow. */
  bidding: Bidding | null;
}

/**
 * A new round at `table` (default 4 players with 2 decks). `deck` must be every card of the table's
 * decks in dealing order (108 for 4 players): all but the kitty are dealt one at a time starting
 * with `dealer ?? 0`, the last `kittySize` are the kitty. A dealer outside the seats is taken modulo
 * the players, as in Swift. Throws a RangeError if `deck` is not a permutation of the table's cards
 * (Swift only checks the count; a deck from `shuffledDeck` always passes) or if `dealer` is not an
 * integer.
 */
export function newRound(trumpRank: Rank, dealer: number | null, deck: readonly Card[], table: TableSize = TABLE_FOUR): Round {
  const size = tableSize(table.players);
  const count = tableCardCount(size);
  if (!isFullDeck(deck, size.decks)) {
    throw new RangeError(`A Shengji deal for ${size.players} players needs all ${count} cards (${size.decks} decks with jokers).`);
  }
  if (dealer !== null && !Number.isInteger(dealer)) throw new RangeError(`dealer must be an integer, got ${dealer}`);
  const seat = dealer === null ? null : normalizeSeat(dealer, size.players);
  const dealtCount = count - tableKittySize(size);
  return {
    trumpRank,
    dealer: seat,
    phase: "dealing",
    hands: Array.from({ length: size.players }, () => []),
    undealt: deck.slice(0, dealtCount),
    kitty: deck.slice(dealtCount),
    declaration: null,
    declarationHistory: [],
    trump: { rank: trumpRank, suit: null },
    nextToReceive: seat ?? 0,
    currentTrick: [],
    tricks: [],
    leader: seat ?? 0,
    defenderTrickPoints: 0,
    trumpFromKitty: null,
    result: null,
    bidding: null,
  };
}

/** Players and decks at this round's table (from its number of hands: 4, 6 or 8). */
export function roundTable(round: Round): TableSize {
  return tableSize(round.hands.length);
}

/** Number of seats at the round's table. */
export function roundPlayers(round: Round): number {
  return roundTable(round).players;
}

/** Cards the dealer picks up and buries: 8 with 4 or 8 players, 6 with 6. */
export function kittySizeOf(round: Round): number {
  return tableKittySize(roundTable(round));
}

/** Cards dealt to each player: 25 with 4 players, 26 with 6 or 8. */
export function handSizeOf(round: Round): number {
  return tableHandSize(roundTable(round));
}

/** A deep copy of the round. */
export function cloneRound(round: Round): Round {
  return structuredClone(round);
}

function isSeat(round: Round, player: number): boolean {
  return Number.isInteger(player) && player >= 0 && player < round.hands.length;
}

function copyDeclaration(d: Declaration): Declaration {
  return { player: d.player, cards: d.cards.slice(), suit: d.suit, strength: d.strength };
}

// MARK: Dealing & declaring

export function isDealingComplete(round: Round): boolean {
  return round.undealt.length === 0;
}

/** Deals one card to `nextToReceive`. Returns null when every card but the kitty is dealt. */
export function dealNext(round: Round): { player: number; card: Card } | null {
  if (round.phase !== "dealing" || round.undealt.length === 0) return null;
  const card = round.undealt.shift() as Card;
  const player = round.nextToReceive;
  round.hands[player].push(card);
  round.nextToReceive = nextSeat(player, roundPlayers(round));
  return { player, card };
}

export function dealAll(round: Round): void {
  while (dealNext(round) !== null) {
    // keep dealing
  }
}

/**
 * Declarations `player` could make right now with the cards in hand. A new declaration must be
 * strictly stronger than the current one; a player who holds the current declaration may only
 * strengthen it with more of the same card (single -> pair, and with three or more decks pair ->
 * triple). Partners may override each other.
 */
export function availableDeclarations(round: Round, player: number): Declaration[] {
  if (round.phase !== "dealing" || !isSeat(round, player)) return [];
  const hand = round.hands[player].slice().sort((a, b) => a - b);
  const options: Declaration[] = [];
  for (const suit of [0, 1, 2, 3] as const) {
    const face = regularFace(round.trumpRank, suit);
    const rankCards = hand.filter((card) => faceOf(card) === face);
    for (let count = 1; count <= rankCards.length; count++) {
      options.push({ player, cards: rankCards.slice(0, count), suit, strength: declarationStrength(count, RANK_CARDS) });
    }
  }
  const jokerKinds: [number, DeclarationKind][] = [
    [SMALL_JOKER_FACE, SMALL_JOKERS],
    [BIG_JOKER_FACE, BIG_JOKERS],
  ];
  for (const [face, kind] of jokerKinds) {
    const jokers = hand.filter((card) => faceOf(card) === face);
    for (let count = 2; count <= jokers.length; count++) {
      options.push({ player, cards: jokers.slice(0, count), suit: null, strength: declarationStrength(count, kind) });
    }
  }

  options.sort((a, b) => (a.strength !== b.strength ? a.strength - b.strength : (a.suit ?? 9) - (b.suit ?? 9)));
  const current = round.declaration;
  if (current === null) return options;
  if (current.player === player) {
    // Holding the current declaration: only more of the same card (a single becomes a pair).
    return options.filter(
      (option) =>
        declarationKind(option.strength) === declarationKind(current.strength) &&
        option.suit === current.suit &&
        declarationCardCount(option.strength) > declarationCardCount(current.strength),
    );
  }
  return options.filter((option) => option.strength > current.strength);
}

/** True if `cards` are exactly what a declaration of that suit and strength reveals. */
export function cardsMatchDeclaration(cards: readonly Card[], suit: Suit | null, strength: number, rank: Rank): boolean {
  if (strength < 1 || cards.length !== declarationCardCount(strength) || new Set(cards).size !== cards.length) {
    return false;
  }
  switch (declarationKind(strength)) {
    case RANK_CARDS:
      return suit !== null && cards.every((card) => !isJoker(card) && suitOf(card) === suit && rankOf(card) === rank);
    case SMALL_JOKERS:
      return suit === null && cards.length >= 2 && cards.every((card) => faceOf(card) === SMALL_JOKER_FACE);
    case BIG_JOKERS:
      return suit === null && cards.length >= 2 && cards.every((card) => faceOf(card) === BIG_JOKER_FACE);
  }
}

/** The declaration error, or null if `d` may be declared now (ignores online bidding turns). */
function declarationError(round: Round, d: Declaration): RoundError | null {
  if (round.phase !== "dealing" || !isSeat(round, d.player)) return { case: "invalidDeclaration" };
  const allowed = availableDeclarations(round, d.player).some((o) => o.suit === d.suit && o.strength === d.strength);
  if (
    !allowed ||
    !cardsMatchDeclaration(d.cards, d.suit, d.strength, round.trumpRank) ||
    !containsAll(round.hands[d.player], d.cards)
  ) {
    return { case: "invalidDeclaration" };
  }
  return null;
}

function applyDeclaration(round: Round, d: Declaration): void {
  const stored = copyDeclaration(d);
  round.declaration = stored;
  round.declarationHistory.push(copyDeclaration(stored));
  round.trump.suit = d.suit;
}

function isBidding(round: Round): boolean {
  return round.phase === "dealing" && round.bidding !== null && round.bidding.turn !== null;
}

/**
 * Offline-style declaring at any moment of the deal. Returns invalidDeclaration unless `d` is in
 * `availableDeclarations(d.player)` (compared by player, suit and strength; the cards must be the
 * right ones and in hand). During online bidding use `bid` instead (this returns wrongPhase).
 */
export function declare(round: Round, d: Declaration): RoundError | null {
  if (isBidding(round)) return { case: "wrongPhase" };
  // A malformed value (e.g. straight from a client) is refused, never thrown on.
  const parsed = parseDeclaration(d);
  if (parsed === null) return { case: "invalidDeclaration" };
  const error = declarationError(round, parsed);
  if (error !== null) return error;
  applyDeclaration(round, parsed);
  return null;
}

/**
 * Closes the declaration window (requires dealing complete). Fixes the trump suit (from the
 * declaration, else from the kitty), fixes the dealer (first round: the winning declarer, else
 * seat 0), gives the kitty to the dealer, and moves to "burying". Does nothing if dealing is still
 * in progress, the window is already closed, or online bidding is still open.
 */
export function finishDealing(round: Round): void {
  if (round.phase !== "dealing" || !isDealingComplete(round) || isBidding(round)) return;
  closeDeclaring(round);
}

function closeDeclaring(round: Round): void {
  const current = round.declaration;
  if (current !== null) {
    round.trump.suit = current.suit;
    round.trumpFromKitty = null;
  } else {
    const flip = kittyFlip(round.kitty, round.trumpRank);
    round.trump.suit = flip.suit;
    round.trumpFromKitty = flip.card;
  }
  const seat = round.dealer ?? current?.player ?? 0;
  round.dealer = seat;
  round.leader = seat;
  round.hands[seat].push(...round.kitty);
  round.phase = "burying";
}

/**
 * Nobody declared: flip the kitty card by card. The first trump-rank card fixes its suit, a joker
 * seen first means no trump suit; failing both, the suit of the highest card (first if tied).
 */
export function kittyFlip(kitty: readonly Card[], rank: Rank): { suit: Suit | null; card: Card | null } {
  for (const card of kitty) {
    if (isJoker(card)) return { suit: null, card };
    if (rankOf(card) === rank) return { suit: suitOf(card), card };
  }
  let best: { card: Card; rank: Rank } | null = null;
  for (const card of kitty) {
    const cardRank = rankOf(card);
    if (cardRank === null) continue;
    if (best !== null && cardRank <= best.rank) continue;
    best = { card, rank: cardRank };
  }
  return best === null ? { suit: null, card: null } : { suit: suitOf(best.card), card: best.card };
}

// MARK: Online bidding (no Swift counterpart)
//
// Declaring online is turn-based (DESIGN.md, Online multiplayer):
//  - `startBidding` deals every card but the kitty at once (100 with 4 players, 156 with 6, 208
//    with 8) and opens bidding at `firstBidder` (the dealer, or the game creator's seat in round 1,
//    when the dealer is not known yet).
//  - On their turn a player either declares one of `availableBids` (exactly the offline
//    `availableDeclarations` strength rules) or passes. Turns go round the table: 0 -> 1 -> ... -> 0.
//  - A declaration resets the pass count. Bidding ends when every other player has passed since
//    the last declaration (three with 4 players, five with 6, seven with 8), or when everyone
//    passes with no declaration at all (then the kitty flip rule sets trump, exactly as offline).
//  - When bidding ends the declaration window closes as in `finishDealing`: trump is fixed and
//    the dealer takes the kitty. Round 1 (dealer null): the winning declarer deals; if nobody
//    declared, the first bidder deals (offline it would be seat 0).
//  - Because a pass from every other player after a declaration ends the bidding, the current
//    declarer never gets another turn while still holding the declaration: a player who declared a
//    single cannot later reinforce it, so declaring a pair straight away is the stronger bid.
//    A player whose declaration was overridden may override back when their turn comes, with
//    anything strictly stronger than the current declaration.

/**
 * Starts online bidding: deals every remaining card and gives the first turn to `firstBidder`.
 * Returns wrongPhase unless the round is still dealing with no declaration and no bidding yet.
 * Throws a RangeError if `firstBidder` is not a seat of the table.
 */
export function startBidding(round: Round, firstBidder: number): RoundError | null {
  if (!isSeat(round, firstBidder)) {
    throw new RangeError(`firstBidder must be a seat 0...${round.hands.length - 1}, got ${firstBidder}`);
  }
  if (round.phase !== "dealing" || round.bidding !== null || round.declarationHistory.length > 0) {
    return { case: "wrongPhase" };
  }
  dealAll(round);
  round.bidding = { firstBidder, turn: firstBidder, passes: 0, bids: [] };
  return null;
}

/** Seat whose turn it is to bid, or null when no bidding is open. */
export function biddingTurn(round: Round): number | null {
  return isBidding(round) ? (round.bidding as Bidding).turn : null;
}

/** Declarations `seat` may bid now: `availableDeclarations` on their turn, otherwise none. */
export function availableBids(round: Round, seat: number): Declaration[] {
  return biddingTurn(round) === seat ? availableDeclarations(round, seat) : [];
}

/**
 * One bidding turn: `choice` is a declaration (its player must be `seat`) or "pass".
 * Errors: wrongPhase (no bidding open), notYourTurn, invalidDeclaration.
 * When this bid ends the bidding, the round moves on to "burying" (see above).
 */
export function bid(round: Round, seat: number, choice: Declaration | "pass"): RoundError | null {
  if (!isBidding(round)) return { case: "wrongPhase" };
  const bidding = round.bidding as Bidding;
  if (seat !== bidding.turn) return { case: "notYourTurn" };
  if (choice === "pass") {
    bidding.passes += 1;
    bidding.bids.push({ seat, declaration: null });
  } else {
    // A malformed value (e.g. straight from a client) is refused, never thrown on.
    const parsed = parseDeclaration(choice);
    if (parsed === null || parsed.player !== seat) return { case: "invalidDeclaration" };
    const error = declarationError(round, parsed);
    if (error !== null) return error;
    applyDeclaration(round, parsed);
    bidding.passes = 0;
    bidding.bids.push({ seat, declaration: copyDeclaration(parsed) });
  }
  const players = roundPlayers(round);
  const finished = round.declaration !== null ? bidding.passes >= players - 1 : bidding.passes >= players;
  if (!finished) {
    bidding.turn = nextSeat(seat, players);
    return null;
  }
  bidding.turn = null;
  if (round.dealer === null && round.declaration === null) round.dealer = bidding.firstBidder;
  closeDeclaring(round);
  return null;
}

// MARK: Burying

/**
 * Dealer buries exactly `kittySizeOf(round)` cards (8 from 33 with 4 players) -> "playing", dealer
 * leads. When `player` is given (online), it must be the dealer (else notYourTurn).
 */
export function bury(round: Round, cards: readonly Card[], player?: number): RoundError | null {
  const seat = round.dealer;
  if (round.phase !== "burying" || seat === null) return { case: "wrongPhase" };
  if (player !== undefined && player !== seat) return { case: "notYourTurn" };
  const size = kittySizeOf(round);
  if (cards.length !== size) {
    return {
      case: "invalidBury",
      reason: `Choose exactly ${size} cards to bury (you chose ${cards.length}).`,
    };
  }
  if (new Set(cards).size !== cards.length) {
    return { case: "invalidBury", reason: "Each card can only be buried once." };
  }
  const left = removeCards(round.hands[seat], cards);
  if (left === null) {
    return { case: "invalidBury", reason: "You can only bury cards from your own hand." };
  }
  round.hands[seat] = left;
  round.kitty = cards.slice();
  round.phase = "playing";
  round.leader = seat;
  return null;
}

// MARK: Playing

/** Whose turn it is to play (null outside "playing"). */
export function turn(round: Round): number | null {
  if (round.phase !== "playing") return null;
  return (round.leader + round.currentTrick.length) % roundPlayers(round);
}

/** Team of the dealer (null before the dealer is known). */
export function declarerTeam(round: Round): number | null {
  return round.dealer === null ? null : teamOf(round.dealer);
}

export function isDefender(round: Round, player: number): boolean {
  const team = declarerTeam(round);
  if (team === null) return false;
  return teamOf(player) !== team;
}

/** Cards of the lead of the current trick (empty if none yet). */
export function currentLead(round: Round): Card[] {
  return round.currentTrick.length > 0 ? round.currentTrick[0].cards : [];
}

/** Validation without side effects. For leads, does NOT run the throw check. */
export function legalityError(round: Round, cards: readonly Card[], player: number): RoundError | null {
  if (round.phase !== "playing") return { case: "wrongPhase" };
  if (turn(round) !== player || !isSeat(round, player)) return { case: "notYourTurn" };
  const hand = round.hands[player];
  if (round.currentTrick.length === 0) {
    const violation = validateLead(cards, hand, round.trump);
    if (violation !== null) return { case: "illegalLead", violation };
  } else {
    const violation = validateFollow(cards, hand, currentLead(round), round.trump);
    if (violation !== null) return { case: "illegalFollow", violation };
  }
  return null;
}

/**
 * Plays cards for the player whose turn it is. Leads that are throws are checked against the
 * other hands; a failing throw plays only the forced component. When the last play lands the trick
 * is scored and appended to `tricks`, `currentTrick` is emptied and the winner leads. After the
 * last trick the round is scored (`result`, phase "finished").
 */
export function play(round: Round, cards: readonly Card[], player: number): PlayResult {
  const error = legalityError(round, cards, player);
  if (error !== null) return { ok: false, error };

  let played = cards.slice();
  let outcome: PlayOutcome = { type: "played" };
  if (round.currentTrick.length === 0 && isThrow(cards, round.trump)) {
    const check = checkThrow(cards, player, round.hands, round.trump);
    if (check.type === "fails") {
      played = check.forced.cards.slice();
      outcome = { type: "throwFailed", forced: check.forced.cards.slice(), blocker: check.blocker };
    }
  }

  round.hands[player] = removeCards(round.hands[player], played) ?? round.hands[player];
  round.currentTrick.push({ player, cards: played });
  if (round.currentTrick.length === roundPlayers(round)) completeTrick(round);
  return { ok: true, outcome };
}

/** All cards played so far (completed tricks plus the trick in progress). */
export function playedCards(round: Round): Card[] {
  const cards: Card[] = [];
  for (const trick of round.tricks) for (const p of trick.plays) cards.push(...p.cards);
  for (const p of round.currentTrick) cards.push(...p.cards);
  return cards;
}

export function lastTrick(round: Round): TrickRecord | null {
  return round.tricks.length > 0 ? round.tricks[round.tricks.length - 1] : null;
}

function completeTrick(round: Round): void {
  const plays = round.currentTrick;
  const winner = plays[winningIndex(plays, round.trump)].player;
  let points = 0;
  for (const p of plays) points += totalPoints(p.cards);
  if (isDefender(round, winner)) round.defenderTrickPoints += points;
  const lead = plays[0].cards;
  round.tricks.push({ plays, winner, points });
  round.currentTrick = [];
  round.leader = winner;
  if (round.hands.every((hand) => hand.length === 0)) finishRound(round, lead, winner);
}

function finishRound(round: Round, lastLead: readonly Card[], lastWinner: number): void {
  const kittyPoints = totalPoints(round.kitty);
  const multiplier = isDefender(round, lastWinner) ? kittyMultiplier(lastLead, round.trump) : 0;
  const defenderPoints = round.defenderTrickPoints + kittyPoints * multiplier;
  const seat = round.dealer ?? 0;
  round.result = {
    dealer: seat,
    declarerTeam: teamOf(seat),
    trump: { rank: round.trump.rank, suit: round.trump.suit },
    trickPoints: round.defenderTrickPoints,
    kittyPoints,
    kittyMultiplier: multiplier,
    defenderPoints,
    outcome: scoreOutcome(defenderPoints, roundTable(round).decks),
    kitty: round.kitty.slice(),
    lastTrickWinner: lastWinner,
  };
  round.phase = "finished";
}
