// Standard-level leading. Port of ShengjiCore/Sources/ShengjiCore/Bots/BotLead.swift (StandardLead,
// LeadCheck), choices only (the learner-facing texts stay in the app). In priority order:
// 1. a throw that is guaranteed to stand, in a plain suit no opponent has shown out of;
// 2. a sure-winning plain tractor, pair or single;
// 3. declarers with many trumps draw trumps (top pairs, else low singles);
// 4. a suit the partner is out of, so the partner can ruff;
// 5. a low non-point card (or low pair) from a short plain suit; last resort, the lowest trump.

import { ALL_SUITS, cardPoints, faceOf, isJoker, rankOf } from "../engine/cards.ts";
import type { Card } from "../engine/cards.ts";
import { PAIR, SINGLE, componentsOf, decompose, longestRun, pairsIn, tractorShape } from "../engine/combos.ts";
import type { ComboShape, Component } from "../engine/combos.ts";
import { checkThrowAgainstPool, isThrow, validateLead } from "../engine/rules.ts";
import { strength } from "../engine/trump.ts";
import type { SuitGroup, Trump } from "../engine/trump.ts";
import { CostModel, cheapest, cheapestFirst } from "./builder.ts";
import { noteFallback, points } from "./table.ts";
import type { BotTable } from "./table.ts";

/** The standard bot's lead. */
export function standardLead(table: BotTable): Card[] {
  return leadCheck(new StandardLead(table).choose(), table);
}

/** Final safety check for leads: legal, and a throw only if it is guaranteed against the unseen cards. */
export function leadCheck(cards: Card[], table: BotTable): Card[] {
  if (validateLead(cards, table.hand, table.trump) === null) {
    if (!isThrow(cards, table.trump) || checkThrowAgainstPool(cards, table.knowledge.unseen, table.trump).type === "ok") {
      return cards;
    }
  }
  noteFallback();
  return cheapest(table.hand, 1, new CostModel(table, "dump"));
}

class StandardLead {
  private readonly table: BotTable;

  constructor(table: BotTable) {
    this.table = table;
  }

  choose(): Card[] {
    const tuning = this.table.tuning;
    return (
      this.throwLead() ??
      (tuning.drawBeforeCashing ? this.drawTrumps() : null) ??
      this.sureWinnerLead() ??
      this.drawTrumps() ??
      this.partnerVoidLead() ??
      this.lowLead() ??
      this.lastResort()
    );
  }

  private get trump(): Trump {
    return this.table.trump;
  }

  /** No opponent has shown out of the plain group, and enough of it is still out that an unseen void is unlikely. */
  private safeToCash(group: SuitGroup): boolean {
    for (const opponent of this.table.opponents) if (this.table.mayRuff(opponent, group)) return false;
    return !this.table.isRunningOut(group, 1, 2);
  }

  // MARK: 1. Throws

  private throwLead(): Card[] | null {
    const { table, trump } = this;
    let best: { cards: Card[]; score: number } | null = null;
    for (const suit of ALL_SUITS) {
      const group: SuitGroup = suit;
      const mine = table.cards(group);
      if (mine.length < 2 || !this.mightThrow(group) || !this.safeToCash(group)) continue;
      const cards: Card[] = [];
      let parts = 0;
      for (const component of decompose(mine, trump)) {
        if (table.unseenCanBeatComponent(component)) continue;
        cards.push(...component.cards);
        parts += 1;
      }
      if (parts < 2 || !isThrow(cards, trump) || checkThrowAgainstPool(cards, table.knowledge.unseen, trump).type !== "ok") {
        continue;
      }
      const score = 10 * cards.length + points(cards);
      if (best !== null && best.score >= score) continue;
      best = { cards, score };
    }
    return best === null ? null : best.cards;
  }

  // MARK: 2. Sure winners

  /** Quick check before decomposing a suit: at least two of its pieces could be unbeatable. */
  private mightThrow(group: SuitGroup): boolean {
    const { table, trump } = this;
    const pieces = table.pieces(group);
    let solid = 0;
    for (const card of pieces.singles) if (!table.unseenCanBeat(SINGLE, group, strength(trump, card))) solid += 1;
    for (const pair of pieces.pairs) if (!table.unseenCanBeat(PAIR, group, strength(trump, pair[0]))) solid += 1;
    const hasTractor = pieces.pairs.some((pair) => table.tractorFaces.has(faceOf(pair[0])));
    return solid >= 2 || hasTractor;
  }

  private sureWinnerLead(): Card[] | null {
    const { table, trump } = this;
    let best: { component: Component; score: number } | null = null;
    const consider = (component: Component): void => {
      if (table.unseenCanBeatComponent(component)) return;
      let score = 100 * component.cards.length + 3 * points(component.cards);
      if (component.shape.type === "single" && table.pairPenalty(component.cards[0]) > 0) score -= 50;
      if (best !== null && best.score >= score) return;
      best = { component, score };
    };
    for (const suit of ALL_SUITS) {
      const group: SuitGroup = suit;
      const mine = table.cards(group);
      if (mine.length === 0 || !this.safeToCash(group)) continue;
      const pieces = table.pieces(group);
      for (const card of pieces.singles) {
        consider({ shape: SINGLE, cards: [card], group, topStrength: strength(trump, card) });
      }
      for (const pair of pieces.pairs) {
        consider({ shape: PAIR, cards: pair, group, topStrength: strength(trump, pair[0]) });
      }
      if (!pieces.pairs.some((pair) => table.tractorFaces.has(faceOf(pair[0])))) continue;
      const run = longestRun(mine, trump);
      for (let length = 2; length <= run; length++) {
        for (const component of componentsOf(tractorShape(length), mine, trump)) consider(component);
      }
    }
    const pick = best as { component: Component; score: number } | null;
    return pick === null ? null : pick.component.cards;
  }

  // MARK: 3. Draw trumps

  private drawTrumps(): Card[] | null {
    const { table, trump } = this;
    if (!table.isDeclarer || !table.tuning.drawTrumps) return null;
    const mine = table.trumps;
    if (mine.length < 4 || !(mine.length >= 8 || 2 * mine.length >= table.hand.length) || table.unseen("trump").length === 0) {
      return null;
    }
    if (!table.opponents.some((opponent) => !table.knowledge.isVoid(opponent, "trump"))) return null;

    // Top pairs or tractors nobody can beat.
    const component = this.sureTrumpCombo();
    if (component !== null) return component.cards;

    // A low single: no points, not from a pair, not a joker or trump-rank card.
    let low: Card | null = null;
    for (const card of mine) {
      if (cardPoints(card) !== 0 || table.pairFaces.has(faceOf(card)) || isJoker(card) || rankOf(card) === trump.rank) continue;
      if (low !== null && table.value(low) <= table.value(card)) continue;
      low = card;
    }
    return low === null ? null : [low];
  }

  // MARK: 4. Partner's void

  private partnerVoidLead(): Card[] | null {
    const { table } = this;
    if (table.knowledge.isVoid(table.partner, "trump")) return null;
    let best: { card: Card; score: number } | null = null;
    for (const suit of ALL_SUITS) {
      const group: SuitGroup = suit;
      if (!table.knowledge.isVoid(table.partner, group)) continue;
      if (table.opponents.some((opponent) => table.mayRuff(opponent, group))) continue;
      for (const card of table.cards(group)) {
        const score = table.value(card) + table.pairPenalty(card) + 2 * cardPoints(card);
        if (best !== null && best.score <= score) continue;
        best = { card, score };
      }
    }
    return best === null ? null : [best.card];
  }

  // MARK: 5. Low lead

  private lowLead(): Card[] | null {
    const { table, trump } = this;
    let best: { cards: Card[]; score: number } | null = null;
    for (const suit of ALL_SUITS) {
      const group: SuitGroup = suit;
      const mine = table.cards(group);
      if (mine.length === 0) continue;
      const ruffRisk = table.opponents.some((opponent) => table.mayRuff(opponent, group)) ? 25 : 0;
      const base = 3 * mine.length + ruffRisk;
      for (const card of mine) {
        if (cardPoints(card) !== 0 || table.pairFaces.has(faceOf(card))) continue;
        const score = base + 2 * strength(trump, card) + (table.isTopUnseen(card) ? 20 : 0);
        if (best !== null && best.score <= score) continue;
        best = { cards: [card], score };
      }
      for (const pair of pairsIn(mine, trump)) {
        if (pair.length === 0 || cardPoints(pair[0]) !== 0) continue;
        const linked = table.tractorFaces.has(faceOf(pair[0])) ? 20 : 0;
        const score = base + 2 * strength(trump, pair[0]) + 6 + linked;
        if (best !== null && best.score <= score) continue;
        best = { cards: pair, score };
      }
    }
    return best === null ? null : best.cards;
  }

  // MARK: Last resort

  private lastResort(): Card[] {
    const { table, trump } = this;
    const costs = new CostModel(table, "dump");
    const combo = this.sureTrumpCombo();
    if (combo !== null) return combo.cards;
    const loose = table.trumps.filter((card) => !table.pairFaces.has(faceOf(card)));
    const trumpPairs = cheapestFirst(pairsIn(table.trumps, trump), costs);
    // Never lead a point card that can be beaten while a lead without points is possible:
    // first a loose trump without points (or one nobody can beat), then a pair without points.
    const safeLoose = loose.filter((card) => cardPoints(card) === 0 || table.isTopUnseen(card));
    const safePairs = trumpPairs.filter((pair) => points(pair) === 0);
    const card = cheapest(safeLoose, 1, costs)[0];
    if (card !== undefined) return [card];
    if (safePairs.length > 0) return safePairs[0];
    const any = cheapest(loose, 1, costs)[0];
    if (any !== undefined) return [any];
    if (trumpPairs.length > 0) return trumpPairs[0];
    return cheapest(table.hand, 1, costs);
  }

  /** A trump pair or tractor nobody can beat (longest first, then the lowest such). */
  private sureTrumpCombo(): Component | null {
    const { table, trump } = this;
    const mine = table.trumps;
    const pieces = table.pieces("trump");
    if (pieces.pairs.length === 0) return null;
    const shapes: ComboShape[] = [PAIR];
    if (pieces.pairs.some((pair) => table.tractorFaces.has(faceOf(pair[0])))) {
      const run = longestRun(mine, trump);
      for (let length = 2; length <= run; length++) shapes.push(tractorShape(length));
    }
    let best: Component | null = null;
    for (const shape of shapes) {
      for (const component of componentsOf(shape, mine, trump)) {
        if (table.unseenCanBeatComponent(component)) continue;
        if (best !== null) {
          if (component.cards.length < best.cards.length) continue;
          if (component.cards.length === best.cards.length && component.topStrength >= best.topStrength) continue;
        }
        best = component;
      }
    }
    return best;
  }
}
