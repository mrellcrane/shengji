// One seat's view of the table for the bots, built from a SeatView alone. Port of
// ShengjiCore/Sources/ShengjiCore/Bots: BotTuning.swift, CardOrder, BotTable and FriendsPlan
// (BotTable.swift) and BotKnowledge (Bot.swift). Seats are viewer-relative: the viewer is 0, its
// partner 2, the opponents 1 (next to play) and 3. With 6 or 8 players the partners are every even
// seat and the opponents every odd one. With Finding Friends (an odd number of players) the partners
// are the players this seat knows share its side (`FriendsPlan`); everyone else counts as an opponent.

import { MAX_CARD_COUNT, cardPoints, deckCards, faceOf, suitOf } from "../engine/cards.ts";
import type { Card, Face } from "../engine/cards.ts";
import { componentsOf, groupOfCards, longestSetRun, maxCopies, setShape, setTractorShape } from "../engine/combos.ts";
import type { ComboShape, Component } from "../engine/combos.ts";
import { canBeat, normalizeSeat, opponentsOf, partnerOf, teamOf, teammatesOf } from "../engine/rules.ts";
import type { Play } from "../engine/rules.ts";
import type { FriendCall } from "../engine/friends.ts";
import { viewDeclarers, viewFindsFriends, viewFriendsToFind, viewIsDeclarer, viewPlayedCards, viewTable } from "../engine/seatview.ts";
import type { SeatView } from "../engine/seatview.ts";
import {
  BIG_JOKER_STRENGTH,
  OFF_SUIT_RANK_STRENGTH,
  SMALL_JOKER_STRENGTH,
  TRUMP_SUIT_RANK_STRENGTH,
  groupOf,
  isTrump,
  plainSuitOrder,
  strength,
} from "../engine/trump.ts";
import type { SuitGroup, Trump } from "../engine/trump.ts";

/**
 * Knobs for the standard strategy (Swift `BotTuning`). The app and the server always use the
 * defaults; Swift tests compare variants in duplicate matches.
 */
export interface BotTuning {
  /** Declaring: trump share needed after 6 cards, easing to `declareLate` by the end of the deal. */
  declareEarly: number;
  declareLate: number;
  /** Trump share needed to override an opponent's declaration with a suit. */
  overrideShare: number;
  /** Declarers with many trumps lead them (top pairs, else low singles). */
  drawTrumps: boolean;
  /** Declarers draw trumps before cashing plain sure winners. */
  drawBeforeCashing: boolean;
  /** Smallest trick value worth a ruff, for defenders and for declarers (late: the defenders' stake). */
  defenderRuffStake: number;
  declarerRuffStake: number;
  /** Smallest trick value worth contesting with a card that might be beaten. */
  defenderContestStake: number;
  declarerContestStake: number;
  /** Points the third player expects the last player (an opponent) to add if the trick is left to them. */
  lastPlayerThreat: number;
}

export const DEFAULT_TUNING: Readonly<BotTuning> = Object.freeze({
  declareEarly: 0.3,
  declareLate: 0.25,
  overrideShare: 0.4,
  drawTrumps: true,
  drawBeforeCashing: false,
  defenderRuffStake: 5,
  declarerRuffStake: 10,
  defenderContestStake: 10,
  declarerContestStake: 15,
  lastPlayerThreat: 10,
});

/** Counts how often a bot fell back to the plain rules-built play (Swift `BotDiagnostics`). */
export const botDiagnostics = { fallbacks: 0 };

export function noteFallback(): void {
  botDiagnostics.fallbacks += 1;
}

// MARK: Card order

/** The display order of `sortKey` with every card's key worked out once (Swift `CardOrder`). */
export class CardOrder {
  readonly trump: Trump;
  private readonly keys: number[];

  constructor(trump: Trump) {
    this.trump = trump;
    const suitIndex = [4, 4, 4, 4];
    plainSuitOrder(trump).forEach((suit, position) => {
      suitIndex[suit] = position;
    });
    this.keys = [];
    for (let card = 0; card < MAX_CARD_COUNT; card++) {
      const suit = suitOf(card);
      const groupIndex = isTrump(trump, card) ? 4 : suit !== null ? suitIndex[suit] : 4;
      const tiebreak = suit === null ? 0 : 3 - suit;
      this.keys.push(groupIndex * 1000 + strength(trump, card) * 10 + tiebreak);
    }
  }

  /** Same value as `sortKey(trump, card)`. */
  key(card: Card): number {
    return this.keys[card];
  }

  /** Same order as `sortCards(trump, cards)`. */
  sorted(cards: readonly Card[]): Card[] {
    return cards.slice().sort((a, b) => this.keys[a] - this.keys[b] || a - b);
  }
}

const orders = new Map<string, CardOrder>();

/** The (cached) card order of a trump context. */
export function cardOrder(trump: Trump): CardOrder {
  const id = `${trump.rank}:${trump.suit}`;
  let order = orders.get(id);
  if (order === undefined) {
    order = new CardOrder({ rank: trump.rank, suit: trump.suit });
    orders.set(id, order);
  }
  return order;
}

// MARK: Knowledge

/**
 * What the viewer knows (Swift `BotKnowledge(view:)`): the cards whose place is unknown to it (the
 * table's full deck minus its hand, every played card and the kitty it buried; a kitty shown to
 * everyone once the round is finished does not count) and which players have shown out of which
 * groups.
 */
export class BotKnowledge {
  readonly trump: Trump;
  /** Unseen cards in id order. */
  readonly unseen: Card[];
  /** voids[player] = groups that player is known to be out of. */
  readonly voids: Set<SuitGroup>[];

  constructor(view: SeatView) {
    this.trump = view.trump;
    const buried = view.phase === "playing" || view.phase === "finished";
    const buriedKitty = buried && view.dealer === 0 ? (view.kitty ?? []) : [];
    const table = viewTable(view);
    const deck = deckCards(table.decks);
    const known: boolean[] = new Array<boolean>(deck.length).fill(false);
    const mark = (cards: readonly Card[]): void => {
      for (const card of cards) if (card >= 0 && card < deck.length) known[card] = true;
    };
    mark(view.hand);
    for (const trick of view.tricks) for (const play of trick.plays) mark(play.cards);
    for (const play of view.currentTrick) mark(play.cards);
    mark(buriedKitty);
    this.unseen = [];
    for (const card of deck) if (!known[card]) this.unseen.push(card);

    this.voids = Array.from({ length: table.players }, () => new Set<SuitGroup>());
    for (const trick of view.tricks) noteVoids(trick.plays, view.trump, this.voids);
    noteVoids(view.currentTrick, view.trump, this.voids);
  }

  /** True if `player` has shown out of `group`. */
  isVoid(player: number, group: SuitGroup): boolean {
    return player >= 0 && player < this.voids.length && this.voids[player].has(group);
  }
}

/** A player whose play held fewer cards of the led group than the lead is out of that group. */
export function noteVoids(plays: readonly Play[], trump: Trump, voids: Set<SuitGroup>[]): void {
  if (plays.length === 0 || plays[0].cards.length === 0) return;
  const lead = plays[0].cards;
  const group = groupOfCards(lead, trump) ?? groupOf(trump, lead[0]);
  for (let index = 1; index < plays.length; index++) {
    const play = plays[index];
    if (play.player < 0 || play.player >= voids.length) continue;
    let inGroup = 0;
    for (const card of play.cards) if (groupOf(trump, card) === group) inGroup++;
    if (inGroup < lead.length) voids[play.player].add(group);
  }
}

// MARK: Finding Friends

/**
 * Finding Friends: the sides as one seat (the viewer, seat 0) can work them out (Swift `FriendsPlan`).
 * The dealer and the friends found so far are on the dealer's side. A player holding the card that
 * answers a call not found yet is a hidden friend: they know they are on the dealer's side before
 * anyone else does. Everyone else is a defender, but a defender can only be sure who plays with them
 * once every called card has been played, so until then they count only themselves.
 */
export class FriendsPlan {
  /** The viewer is the dealer, a friend found, or a hidden friend. */
  readonly onDealerSide: boolean;
  /**
   * Hidden friend: the call this seat answers and the cards that answer it (the copies still needed
   * to reach the called one, lowest ids first).
   */
  readonly reveal: { call: FriendCall; cards: Card[] } | null;
  /** Seats known to share the viewer's side (never the viewer). */
  readonly allies: Set<number>;

  constructor(view: SeatView, hand: readonly Card[]) {
    const n = viewTable(view).players;
    const calls = view.friendCalls ?? [];
    let reveal: { call: FriendCall; cards: Card[] } | null = null;
    if (view.dealer !== null && !viewIsDeclarer(view, 0)) {
      const played = viewPlayedCards(view);
      for (const call of calls) {
        if (call.friend !== null) continue;
        let before = 0;
        for (const card of played) if (faceOf(card) === call.face) before++;
        const need = call.ordinal - before;
        const mine = hand.filter((card) => faceOf(card) === call.face).sort((a, b) => a - b);
        if (need >= 1 && mine.length >= need) {
          reveal = { call, cards: mine.slice(0, need) };
          break;
        }
      }
    }
    this.reveal = reveal;
    const onDealerSide = viewIsDeclarer(view, 0) || reveal !== null;
    this.onDealerSide = onDealerSide;
    if (onDealerSide) {
      this.allies = new Set(viewDeclarers(view).filter((seat) => seat !== 0));
    } else if (view.dealer !== null && viewFriendsToFind(view) === 0 && calls.length > 0) {
      const allies = new Set<number>();
      for (let seat = 1; seat < n; seat++) if (!viewIsDeclarer(view, seat)) allies.add(seat);
      this.allies = allies;
    } else {
      this.allies = new Set<number>();
    }
  }
}

// MARK: The table

/** A seat's own cards of one group as one card per face (lowest copy) and the faces held at least twice. */
export interface Pieces {
  singles: Card[];
  pairs: Card[][];
}

/**
 * The viewer's table plus the card values the strategies share (Swift `BotTable`). Built only from
 * what the viewer may know: its hand, the cards played, its own buried kitty and the voids shown.
 */
export class BotTable {
  readonly view: SeatView;
  /** Always 0: the viewer. */
  readonly seat = 0;
  /** Seats at the table (4 to 9). */
  readonly players: number;
  /** The partner opposite with 4 players (seat 2); with more, the first partner after this seat. */
  readonly partner: number;
  /** Every partner, in play order after this seat (just seat 2 with 4 players). */
  readonly teammates: number[];
  /** Finding Friends: which side this seat is on and how it can show it (null at tables of fixed teams). */
  readonly friends: FriendsPlan | null;
  readonly trump: Trump;
  readonly order: CardOrder;
  /** Own hand, lowest first in display order. */
  readonly hand: Card[];
  readonly knowledge: BotKnowledge;
  /** True if the viewer's team is the declaring (dealer's) team (with Finding Friends: the viewer's side). */
  readonly isDeclarer: boolean;
  readonly tuning: Readonly<BotTuning>;
  /** Faces held twice. */
  readonly pairFaces: Set<Face>;
  /** Faces held twice next to another held pair of the same group (part of a tractor). */
  readonly tractorFaces: Set<Face>;
  private readonly handGroups = new Map<SuitGroup, Card[]>();
  private readonly unseenGroups = new Map<SuitGroup, Card[]>();
  /** Highest unseen strength per group, and highest unseen pair (both copies unseen). */
  private readonly topUnseen = new Map<SuitGroup, number>();
  private readonly topUnseenPair = new Map<SuitGroup, number>();
  private readonly values: number[] = new Array<number>(MAX_CARD_COUNT).fill(-1);

  constructor(view: SeatView, tuning: Readonly<BotTuning> = DEFAULT_TUNING) {
    this.view = view;
    this.tuning = tuning;
    const trump = view.trump;
    this.trump = trump;
    const players = viewTable(view).players;
    this.players = players;
    this.partner = partnerOf(0);
    this.order = cardOrder(trump);
    this.hand = this.order.sorted(view.hand);
    const friends = viewFindsFriends(view) ? new FriendsPlan(view, this.hand) : null;
    this.friends = friends;
    this.teammates =
      friends === null
        ? teammatesOf(0, players)
        : Array.from({ length: players - 1 }, (_, i) => i + 1).filter((seat) => friends.allies.has(seat));
    this.knowledge = new BotKnowledge(view);
    this.isDeclarer = friends !== null ? friends.onDealerSide : view.dealer !== null && teamOf(view.dealer) === teamOf(0);

    const counts = new Map<Face, number>();
    for (const card of this.hand) {
      const group = groupOf(trump, card);
      const list = this.handGroups.get(group);
      if (list) list.push(card);
      else this.handGroups.set(group, [card]);
      const face = faceOf(card);
      counts.set(face, (counts.get(face) ?? 0) + 1);
    }
    this.pairFaces = new Set<Face>();
    for (const [face, count] of counts) if (count >= 2) this.pairFaces.add(face);
    this.tractorFaces = new Set<Face>();
    for (const face of this.pairFaces) {
      const group = groupOf(trump, face);
      const level = strength(trump, face);
      for (const other of this.pairFaces) {
        if (other !== face && groupOf(trump, other) === group && Math.abs(strength(trump, other) - level) === 1) {
          this.tractorFaces.add(face);
        }
      }
    }

    const faceSeen: boolean[] = new Array<boolean>(54).fill(false);
    for (const card of this.knowledge.unseen) {
      const group = groupOf(trump, card);
      const level = strength(trump, card);
      const list = this.unseenGroups.get(group);
      if (list) list.push(card);
      else this.unseenGroups.set(group, [card]);
      this.topUnseen.set(group, Math.max(this.topUnseen.get(group) ?? -1, level));
      const face = faceOf(card);
      if (faceSeen[face]) this.topUnseenPair.set(group, Math.max(this.topUnseenPair.get(group) ?? -1, level));
      faceSeen[face] = true;
    }
  }

  get isLeading(): boolean {
    return this.view.currentTrick.length === 0;
  }

  /** The opponents, in play order after this seat (two with 4 players: East, then West). */
  get opponents(): number[] {
    const friends = this.friends;
    if (friends === null) return opponentsOf(this.seat, this.players);
    return Array.from({ length: this.players - 1 }, (_, i) => i + 1).filter((seat) => !friends.allies.has(seat));
  }

  isOpponent(player: number): boolean {
    if (this.friends === null) return teamOf(player) !== teamOf(this.seat);
    const p = normalizeSeat(player, this.players);
    return p !== this.seat && !this.friends.allies.has(p);
  }

  /** A partner of this seat (not this seat itself). */
  isTeammate(player: number): boolean {
    const p = normalizeSeat(player, this.players);
    if (this.friends !== null) return this.friends.allies.has(p);
    return p !== this.seat && teamOf(p) === teamOf(this.seat);
  }

  /** Own cards of a group, lowest first. */
  cards(group: SuitGroup): Card[] {
    return this.handGroups.get(group) ?? [];
  }

  unseen(group: SuitGroup): Card[] {
    return this.unseenGroups.get(group) ?? [];
  }

  get trumps(): Card[] {
    return this.cards("trump");
  }

  /** Late in the round: few cards left in hand. */
  get isLate(): boolean {
    return this.hand.length <= 8;
  }

  /**
   * Own cards of a group as one card per face (lowest copy) and the faces held at least twice (their
   * two lowest copies), lowest first.
   */
  pieces(group: SuitGroup): Pieces {
    const singles: Card[] = [];
    const pairs: Card[][] = [];
    let previous: Card | null = null;
    let run = 0;
    for (const card of this.cards(group)) {
      if (previous !== null && faceOf(previous) === faceOf(card)) {
        run += 1;
        if (run === 2) pairs.push([previous, card]);
      } else {
        singles.push(card);
        run = 1;
      }
      previous = card;
    }
    return { singles, pairs };
  }

  /**
   * Own sets of three or more identical cards in a group (triples, four of a kind) and tractors of
   * them, widest first, then lowest first. Empty with two decks.
   */
  sets(group: SuitGroup): Component[] {
    const mine = this.cards(group);
    const widest = maxCopies(mine);
    if (widest < 3) return [];
    const out: Component[] = [];
    for (let width = widest; width >= 3; width--) {
      out.push(...componentsOf(setShape(width), mine, this.trump));
      const run = longestSetRun(mine, width, this.trump);
      for (let length = 2; length <= run; length++) {
        out.push(...componentsOf(setTractorShape(width, length), mine, this.trump));
      }
    }
    return out;
  }

  /** Some unseen component of that shape and group is stronger (`canBeat` against the unseen cards). */
  unseenCanBeat(shape: ComboShape, group: SuitGroup, top: number): boolean {
    switch (shape.type) {
      case "single":
        return (this.topUnseen.get(group) ?? -1) > top;
      case "pair":
        return (this.topUnseenPair.get(group) ?? -1) > top;
      case "tractor":
      case "set":
      case "setTractor":
        return canBeat({ shape, cards: [], group, topStrength: top }, this.unseen(group), this.trump);
    }
  }

  unseenCanBeatComponent(component: Component): boolean {
    return this.unseenCanBeat(component.shape, component.group, component.topStrength);
  }

  /** No unseen card of the same group is stronger (a tie still holds: the earlier play wins). */
  isTopUnseen(card: Card): boolean {
    return strength(this.trump, card) >= (this.topUnseen.get(groupOf(this.trump, card)) ?? -1);
  }

  /** `player` has shown out of the plain group and may still hold trumps to ruff it with. */
  mayRuff(player: number, group: SuitGroup): boolean {
    if (group === "trump") return false;
    return this.knowledge.isVoid(player, group) && !this.knowledge.isVoid(player, "trump");
  }

  /** So few cards of a plain group are left outside this hand that `players` others likely can't all follow `count`. */
  isRunningOut(group: SuitGroup, count: number, players: number): boolean {
    if (group === "trump" || players <= 0) return false;
    return this.unseen(group).length < Math.max(1, count * players);
  }

  /**
   * How useful a card is to keep (higher = more useful later), ignoring its points. Units: 4 per
   * point. Trumps rise steeply: a low trump is worth about 8 points, a trump-rank card about 24.
   */
  value(card: Card): number {
    const cached = this.values[card];
    if (cached >= 0) return cached;
    const level = strength(this.trump, card);
    let value: number;
    if (!isTrump(this.trump, card)) {
      value = 2 * level + (this.isTopUnseen(card) ? 16 : 0);
    } else if (level === BIG_JOKER_STRENGTH) {
      value = 140;
    } else if (level === SMALL_JOKER_STRENGTH) {
      value = 125;
    } else if (level === TRUMP_SUIT_RANK_STRENGTH) {
      value = 108;
    } else if (level === OFF_SUIT_RANK_STRENGTH) {
      value = 96;
    } else {
      value = 32 + Math.trunc((level * level) / 4) + 2 * level;
    }
    this.values[card] = value;
    return value;
  }

  /** Extra cost of playing one card of a held pair on its own (breaking the pair). */
  pairPenalty(card: Card): number {
    const face = faceOf(card);
    if (!this.pairFaces.has(face)) return 0;
    return 16 + strength(this.trump, card) + (this.tractorFaces.has(face) ? 10 : 0);
  }
}

/** Total points of the cards (Swift `[Card].points`). */
export function points(cards: readonly Card[]): number {
  let total = 0;
  for (const card of cards) total += cardPoints(card);
  return total;
}

/** Swift `==` on card arrays: the same cards in the same order. */
export function sameCards(a: readonly Card[], b: readonly Card[]): boolean {
  return a.length === b.length && a.every((card, index) => card === b[index]);
}
