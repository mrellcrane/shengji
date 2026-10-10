// Cards, suits and ranks. Port of ShengjiCore/Sources/ShengjiCore/Engine/Card.swift.
//
// Wire format (DESIGN.md, Online multiplayer): a card is its Swift `Card.id`, an integer 0...107
// equal to `face index + copy * 54`. Face indices are 0...51 for regular cards
// (suit * 13 + rank - 2), 52 for the small joker and 53 for the big joker. Every face exists twice
// (copy 0 and copy 1). Because face indices are also the ids of the copy-0 cards, every function
// below that takes a card also accepts a face index.

/** Suit raw values as in Swift: 0 = spades, 1 = hearts, 2 = clubs, 3 = diamonds. */
export type Suit = 0 | 1 | 2 | 3;

/** Natural rank 2...14 (11 = jack, 12 = queen, 13 = king, 14 = ace), as Swift `Rank.rawValue`. */
export type Rank = 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14;

/** A physical card: its id 0...107. */
export type Card = number;

/** What is printed on a card, ignoring the copy: 0...53. Two cards with the same face form a pair. */
export type Face = number;

export const SPADES: Suit = 0;
export const HEARTS: Suit = 1;
export const CLUBS: Suit = 2;
export const DIAMONDS: Suit = 3;
export const ALL_SUITS: readonly Suit[] = [0, 1, 2, 3];

export const JACK: Rank = 11;
export const QUEEN: Rank = 12;
export const KING: Rank = 13;
export const ACE: Rank = 14;
export const ALL_RANKS: readonly Rank[] = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14];

export const SMALL_JOKER_FACE: Face = 52;
export const BIG_JOKER_FACE: Face = 53;
export const FACE_COUNT = 54;
export const DECK_SIZE = 108;

// MARK: Suits

const SUIT_SYMBOLS = ["♠", "♥", "♣", "♦"] as const;
const SUIT_NAMES = ["Spades", "Hearts", "Clubs", "Diamonds"] as const;
const SUIT_SINGULAR = ["spade", "heart", "club", "diamond"] as const;

export function isSuit(value: unknown): value is Suit {
  return value === 0 || value === 1 || value === 2 || value === 3;
}

/** "♠", "♥", "♣", "♦". */
export function suitSymbol(suit: Suit): string {
  return SUIT_SYMBOLS[suit];
}

/** "Spades", "Hearts", ... */
export function suitName(suit: Suit): string {
  return SUIT_NAMES[suit];
}

/** Singular name, e.g. "spade". */
export function suitSingularName(suit: Suit): string {
  return SUIT_SINGULAR[suit];
}

export function isRedSuit(suit: Suit): boolean {
  return suit === HEARTS || suit === DIAMONDS;
}

// MARK: Ranks

export function isRank(value: unknown): value is Rank {
  return typeof value === "number" && Number.isInteger(value) && value >= 2 && value <= 14;
}

/** Short label used on card faces: "2"..."10", "J", "Q", "K", "A". */
export function rankLabel(rank: Rank): string {
  switch (rank) {
    case 11:
      return "J";
    case 12:
      return "Q";
    case 13:
      return "K";
    case 14:
      return "A";
    default:
      return String(rank);
  }
}

/** "2"..."10", "Jack", "Queen", "King", "Ace". */
export function rankName(rank: Rank): string {
  switch (rank) {
    case 11:
      return "Jack";
    case 12:
      return "Queen";
    case 13:
      return "King";
    case 14:
      return "Ace";
    default:
      return String(rank);
  }
}

/** Point value of a card of this rank: 5s are worth 5, 10s and Kings are worth 10. */
export function rankPoints(rank: Rank): number {
  if (rank === 5) return 5;
  if (rank === 10 || rank === 13) return 10;
  return 0;
}

/** The rank `steps` levels above `rank`, capped at `cap` (never below `rank`). Swift `Rank.advanced(by:cap:)`. */
export function advanceRank(rank: Rank, steps: number, cap: Rank = ACE): Rank {
  const target = Math.min(rank + Math.max(0, steps), cap);
  return Math.max(target, rank) as Rank;
}

// MARK: Faces and cards

export function isCard(value: unknown): value is Card {
  return typeof value === "number" && Number.isInteger(value) && value >= 0 && value < DECK_SIZE;
}

export function faceOf(card: Card): Face {
  return card % FACE_COUNT;
}

/** 0 or 1: which of the two decks the card came from. */
export function copyOf(card: Card): number {
  return card < FACE_COUNT ? 0 : 1;
}

export function regularFace(rank: Rank, suit: Suit): Face {
  return suit * 13 + (rank - 2);
}

/** The card with the given face and copy (0 or 1). */
export function cardOf(face: Face, copy = 0): Card {
  return face + copy * FACE_COUNT;
}

export function makeCard(rank: Rank, suit: Suit, copy = 0): Card {
  return cardOf(regularFace(rank, suit), copy);
}

export function smallJoker(copy = 0): Card {
  return cardOf(SMALL_JOKER_FACE, copy);
}

export function bigJoker(copy = 0): Card {
  return cardOf(BIG_JOKER_FACE, copy);
}

/** Suit of a regular card, null for jokers. */
export function suitOf(card: Card): Suit | null {
  const face = faceOf(card);
  return face < 52 ? (Math.floor(face / 13) as Suit) : null;
}

/** Rank of a regular card, null for jokers. */
export function rankOf(card: Card): Rank | null {
  const face = faceOf(card);
  return face < 52 ? ((face % 13) + 2) as Rank : null;
}

export function isJoker(card: Card): boolean {
  return faceOf(card) >= 52;
}

export function cardPoints(card: Card): number {
  const rank = rankOf(card);
  return rank === null ? 0 : rankPoints(rank);
}

/** Total point value of the cards. */
export function totalPoints(cards: readonly Card[]): number {
  let sum = 0;
  for (const card of cards) sum += cardPoints(card);
  return sum;
}

/** Short text such as "10♥", "A♠", "SJ" (small joker) or "BJ" (big joker). */
export function cardDescription(card: Card): string {
  const face = faceOf(card);
  if (face === SMALL_JOKER_FACE) return "SJ";
  if (face === BIG_JOKER_FACE) return "BJ";
  return rankLabel(rankOf(card) as Rank) + suitSymbol(suitOf(card) as Suit);
}

/** Spoken-style name, e.g. "ten of hearts", "small joker". */
export function cardLongName(card: Card): string {
  const face = faceOf(card);
  if (face === SMALL_JOKER_FACE) return "small joker";
  if (face === BIG_JOKER_FACE) return "big joker";
  return `${rankName(rankOf(card) as Rank).toLowerCase()} of ${suitName(suitOf(card) as Suit).toLowerCase()}`;
}

/** Readable list like "A♠ A♠ K♠". */
export function shortText(cards: readonly Card[]): string {
  return cards.map(cardDescription).join(" ");
}

// MARK: Card lists

/**
 * `hand` without `cards` (each removed once, by identity, keeping the order of the rest),
 * or null if any card is missing. Swift `Array.remove(cards:)`.
 */
export function removeCards(hand: readonly Card[], cards: readonly Card[]): Card[] | null {
  const copy = hand.slice();
  for (const card of cards) {
    const index = copy.indexOf(card);
    if (index < 0) return null;
    copy.splice(index, 1);
  }
  return copy;
}

/** `hand` without `cards`, or `hand` unchanged (copied) if any card is missing. */
export function without(hand: readonly Card[], cards: readonly Card[]): Card[] {
  return removeCards(hand, cards) ?? hand.slice();
}

/** True if every card in `cards` is present in `hand` (counting repeats). */
export function containsAll(hand: readonly Card[], cards: readonly Card[]): boolean {
  return removeCards(hand, cards) !== null;
}

/** Two full decks including four jokers: 108 cards in the fixed Swift `Deck.double()` order (ids 0...107). */
export function doubleDeck(): Card[] {
  const cards: Card[] = [];
  for (let id = 0; id < DECK_SIZE; id++) cards.push(id);
  return cards;
}

/** True if `deck` holds each of the 108 cards exactly once. */
export function isFullDeck(deck: readonly unknown[]): deck is Card[] {
  if (deck.length !== DECK_SIZE) return false;
  const seen = new Set<number>();
  for (const card of deck) {
    if (!isCard(card) || seen.has(card)) return false;
    seen.add(card);
  }
  return true;
}
