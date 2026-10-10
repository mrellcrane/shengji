// One seat's view of the table for the bots, built from a SeatView alone. Port of
// ShengjiCore/Sources/ShengjiCore/Bots: BotTuning.swift, CardOrder and BotTable (BotTable.swift) and
// BotKnowledge (Bot.swift). Seats are viewer-relative: the viewer is 0, its partner 2, the opponents
// 1 (next to play) and 3.

import { DECK_SIZE, cardPoints, faceOf, suitOf } from "../engine/cards.ts";
import type { Card, Face } from "../engine/cards.ts";
import { groupOfCards } from "../engine/combos.ts";
import type { ComboShape, Component } from "../engine/combos.ts";
import { canBeat, partnerOf, teamOf } from "../engine/rules.ts";
import type { Play } from "../engine/rules.ts";
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
    for (let card = 0; card < DECK_SIZE; card++) {
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
 * full deck minus its hand, every played card and the kitty it buried; a kitty shown to everyone
 * once the round is finished does not count) and which players have shown out of which groups.
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
    const known: boolean[] = new Array<boolean>(DECK_SIZE).fill(false);
    const mark = (cards: readonly Card[]): void => {
      for (const card of cards) if (card >= 0 && card < DECK_SIZE) known[card] = true;
    };
    mark(view.hand);
    for (const trick of view.tricks) for (const play of trick.plays) mark(play.cards);
    for (const play of view.currentTrick) mark(play.cards);
    mark(buriedKitty);
    this.unseen = [];
    for (let card = 0; card < DECK_SIZE; card++) if (!known[card]) this.unseen.push(card);

    this.voids = [0, 1, 2, 3].map(() => new Set<SuitGroup>());
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

// MARK: The table

/** A seat's own cards of one group as one card per face (lowest copy) and the faces held twice. */
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
  readonly partner: number;
  readonly trump: Trump;
  readonly order: CardOrder;
  /** Own hand, lowest first in display order. */
  readonly hand: Card[];
  readonly knowledge: BotKnowledge;
  /** True if the viewer's team is the declaring (dealer's) team. */
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
  private readonly values: number[] = new Array<number>(DECK_SIZE).fill(-1);

  constructor(view: SeatView, tuning: Readonly<BotTuning> = DEFAULT_TUNING) {
    this.view = view;
    this.tuning = tuning;
    const trump = view.trump;
    this.trump = trump;
    this.partner = partnerOf(0);
    this.order = cardOrder(trump);
    this.hand = this.order.sorted(view.hand);
    this.knowledge = new BotKnowledge(view);
    this.isDeclarer = view.dealer !== null && teamOf(view.dealer) === teamOf(0);

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

  /** The two opponents, the one after the viewer first. */
  get opponents(): number[] {
    return [(this.seat + 1) % 4, (this.seat + 3) % 4];
  }

  isOpponent(player: number): boolean {
    return teamOf(player) !== teamOf(this.seat);
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

  /** Own cards of a group as one card per face and the faces held twice, lowest first. */
  pieces(group: SuitGroup): Pieces {
    const singles: Card[] = [];
    const pairs: Card[][] = [];
    let previous: Card | null = null;
    for (const card of this.cards(group)) {
      if (previous !== null && faceOf(previous) === faceOf(card)) pairs.push([previous, card]);
      else singles.push(card);
      previous = card;
    }
    return { singles, pairs };
  }

  /** Some unseen component of that shape and group is stronger (`canBeat` against the unseen cards). */
  unseenCanBeat(shape: ComboShape, group: SuitGroup, top: number): boolean {
    switch (shape.type) {
      case "single":
        return (this.topUnseen.get(group) ?? -1) > top;
      case "pair":
        return (this.topUnseenPair.get(group) ?? -1) > top;
      case "tractor":
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
