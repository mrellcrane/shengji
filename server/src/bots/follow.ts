// Standard-level following. Port of ShengjiCore/Sources/ShengjiCore/Bots/BotFollow.swift (TrickJudge,
// StandardFollow), choices only. Every play is built by `FollowBuilder` (owed structure first, then
// filler chosen by cost) and checked with `validateFollow`.
//  - Partner winning safely (this seat is last, or nobody after can beat them): feed points.
//  - Partner winning but beatable: overtake with a sure winner if points are at risk, else duck low.
//  - Opponent winning: win cheaply when it is worth it, ruff when out of the suit and points are at
//    stake (high enough when a later opponent may overruff), otherwise duck low.
//  - Third seat: the last player is an opponent, so a trick left to them is worth more than the
//    points on the table.

import type { Card } from "../engine/cards.ts";
import { SINGLE, groupOfCards } from "../engine/combos.ts";
import type { ComboShape } from "../engine/combos.ts";
import { isThrow, leadFormat, structureKeyForFormat } from "../engine/rules.ts";
import type { LeadFormat, Play } from "../engine/rules.ts";
import { TOP_PLAIN_STRENGTH, groupOf } from "../engine/trump.ts";
import type { SuitGroup, Trump } from "../engine/trump.ts";
import { CostModel, FollowBuilder } from "./builder.ts";
import { noteFallback, points, sameCards } from "./table.ts";
import type { BotTable } from "./table.ts";

interface Challenge {
  isTrump: boolean;
  key: number;
}

/** The play's comparison key if it can compete at all (all led group or all trump, same structure). */
function challenge(cards: readonly Card[], ledGroup: SuitGroup, format: LeadFormat, trump: Trump): Challenge | null {
  const group = groupOfCards(cards, trump);
  if (group === null || !(group === ledGroup || group === "trump")) return null;
  const key = structureKeyForFormat(cards, format, trump);
  return key === null ? null : { isTrump: group === "trump", key };
}

/**
 * Reads a trick in progress once and answers "would this play take the lead?" with exactly the
 * rules of `winningIndex`. Swift `TrickJudge`.
 */
export class TrickJudge {
  readonly trump: Trump;
  readonly format: LeadFormat;
  readonly ledGroup: SuitGroup;
  /** True when the lead has more than one component (a throw that stood). */
  readonly isThrowLead: boolean;
  /** Index into the trick of the play winning so far. */
  readonly winnerIndex: number;
  private readonly bestIsTrump: boolean;
  private readonly bestKey: number;

  constructor(trick: readonly Play[], trump: Trump) {
    this.trump = trump;
    const lead = trick.length > 0 ? trick[0].cards : [];
    const format = leadFormat(lead, trump);
    this.format = format;
    this.isThrowLead = isThrow(lead, trump);
    const group = groupOfCards(lead, trump) ?? (lead.length > 0 ? groupOf(trump, lead[0]) : "trump");
    this.ledGroup = group;
    let index = 0;
    let bestIsTrump = group === "trump";
    let key = structureKeyForFormat(lead, format, trump) ?? format.largest?.topStrength ?? 0;
    for (let position = 1; position < trick.length; position++) {
      const challenger = challenge(trick[position].cards, group, format, trump);
      if (challenger === null) continue;
      if (challenger.isTrump && !bestIsTrump) {
        index = position;
        bestIsTrump = true;
        key = challenger.key;
      } else if (challenger.isTrump === bestIsTrump && challenger.key > key) {
        index = position;
        key = challenger.key;
      }
    }
    this.winnerIndex = index;
    this.bestIsTrump = bestIsTrump;
    this.bestKey = key;
  }

  /** True if `cards`, played next, would be winning the trick. */
  wins(cards: readonly Card[]): boolean {
    const challenger = challenge(cards, this.ledGroup, this.format, this.trump);
    if (challenger === null) return false;
    if (challenger.isTrump && !this.bestIsTrump) return true;
    return challenger.isTrump === this.bestIsTrump && challenger.key > this.bestKey;
  }

  /** The play's comparison key if it can compete at all. */
  key(cards: readonly Card[]): number | null {
    return challenge(cards, this.ledGroup, this.format, this.trump)?.key ?? null;
  }
}

/** The standard bot's follow. */
export function standardFollow(table: BotTable): Card[] {
  return new StandardFollow(table).decide();
}

interface Candidate {
  cards: Card[];
  /** Value of the cards given up (points ignored). */
  cost: number;
  sure: boolean;
  key: number;
}

class StandardFollow {
  private readonly table: BotTable;
  private readonly builder: FollowBuilder;
  private readonly judge: TrickJudge;
  private readonly lead: Card[];
  private readonly count: number;
  private readonly leadShape: ComboShape;
  private readonly winner: number;
  private readonly winningCards: Card[];
  private readonly onTable: number;
  private readonly laterOpponents: number[];
  private readonly partnerLater: boolean;
  private readonly isLast: boolean;
  /** Third seat only: the points the last player is expected to add if the trick is left to them. */
  private readonly lastPlayerThreat: number;

  constructor(table: BotTable) {
    this.table = table;
    const trick = table.view.currentTrick;
    const lead = trick.length > 0 ? trick[0].cards : [];
    this.lead = lead;
    this.count = lead.length;
    this.builder = new FollowBuilder(table.hand, lead, table.trump);
    this.judge = new TrickJudge(trick, table.trump);
    this.leadShape = this.judge.format.largest?.shape ?? SINGLE;
    const index = this.judge.winnerIndex;
    const winning = index >= 0 && index < trick.length ? trick[index] : (trick[0] ?? null);
    this.winner = winning?.player ?? table.view.leader;
    this.winningCards = winning?.cards ?? lead;
    let onTable = 0;
    for (const play of trick) onTable += points(play.cards);
    this.onTable = onTable;
    const position = trick.length;
    const later: number[] = [];
    for (let step = 1; step <= 3 - position; step++) later.push((table.seat + step) % 4);
    this.laterOpponents = later.filter((player) => table.isOpponent(player));
    this.partnerLater = later.includes(table.partner);
    this.isLast = position >= 3;
    this.lastPlayerThreat = position === 2 ? table.tuning.lastPlayerThreat : 0;
  }

  private get ledGroup(): SuitGroup {
    return this.builder.ledGroup;
  }

  decide(): Card[] {
    const cards = this.winner === this.table.partner ? this.partnerWinning() : this.opponentWinning();
    if (this.builder.isLegal(cards)) return cards;
    noteFallback();
    return this.builder.fallback();
  }

  // MARK: Trick reading

  /** True if, as far as this seat can tell, no opponent still to play can beat `play`. */
  private holds(play: readonly Card[]): boolean {
    const { table, laterOpponents, ledGroup } = this;
    if (laterOpponents.length === 0) return true;
    const group = groupOfCards(play, table.trump);
    const key = group === null ? null : this.judge.key(play);
    if (group === null || key === null) return false;
    // A throw that stood can't be beaten in its own suit (nobody held a higher part), only trumped.
    const standingThrow = this.judge.isThrowLead && sameCards(play, this.lead);
    const higherOut = !standingThrow && table.unseenCanBeat(this.leadShape, group, key);
    const ruffThreat =
      laterOpponents.some((player) => table.mayRuff(player, ledGroup)) ||
      table.isRunningOut(ledGroup, this.count, laterOpponents.length);
    if (group === "trump" && ledGroup !== "trump") {
      // A ruff: only an opponent who is also out of the led suit can trump over it.
      return !(ruffThreat && higherOut);
    }
    if (higherOut) return false;
    return group === "trump" || !ruffThreat;
  }

  /** Plays that would win the trick right now, cheapest first (point cards count as cheap: they come back). */
  private winningPlays(): Candidate[] {
    const { table } = this;
    const win = new CostModel(table, "win");
    const plays = this.builder.held.length === 0 ? this.builder.ruffs(win) : this.builder.inSuitShapes();
    const keep = new CostModel(table, "keep");
    const scored: { candidate: Candidate; order: number; tiebreak: number }[] = [];
    for (const play of plays) {
      if (!this.judge.wins(play)) continue;
      const candidate: Candidate = { cards: play, cost: keep.costOf(play), sure: this.holds(play), key: this.judge.key(play) ?? 0 };
      let tiebreak = 0;
      const first = table.order.sorted(play)[0];
      if (first !== undefined) tiebreak = table.order.key(first) * 200 + first;
      scored.push({ candidate, order: win.costOf(play), tiebreak });
    }
    scored.sort((a, b) => a.order - b.order || a.candidate.key - b.candidate.key || a.tiebreak - b.tiebreak);
    return scored.map((s) => s.candidate);
  }

  /** The first candidate (cheapest first) that passes `test` and costs at most `limit` more than ducking. */
  private firstAffordable(
    candidates: readonly Candidate[],
    dumpCost: number,
    limit: number,
    test: (candidate: Candidate) => boolean,
  ): Candidate | null {
    for (const candidate of candidates) {
      if (test(candidate) && candidate.cost - dumpCost <= limit) return candidate;
    }
    return null;
  }

  /** Defenders chase points; declarers fight hardest for points late in the round. */
  private worthContesting(stake: number): boolean {
    const { tuning } = this.table;
    if (this.table.isDeclarer) {
      return stake >= tuning.declarerContestStake || (this.table.isLate && stake >= tuning.defenderContestStake);
    }
    return stake >= tuning.defenderContestStake;
  }

  private worthRuffing(stake: number): boolean {
    const { tuning } = this.table;
    if (this.table.isDeclarer) {
      return stake >= tuning.declarerRuffStake || (this.table.isLate && stake >= tuning.defenderRuffStake);
    }
    return stake >= tuning.defenderRuffStake;
  }

  // MARK: Partner winning

  private partnerWinning(): Card[] {
    if (this.isLast || this.holds(this.winningCards)) return this.builder.build(new CostModel(this.table, "feed"));
    const dump = this.builder.build(new CostModel(this.table, "guarded"));
    // Points at risk: the trick so far, any points this seat would have to throw in, and what the
    // last player adds if they take the trick.
    const stake = this.onTable + points(dump) + this.lastPlayerThreat;
    if (stake >= 10) {
      const dumpCost = new CostModel(this.table, "keep").costOf(dump);
      const sure = this.firstAffordable(this.winningPlays(), dumpCost, 20 + 4 * stake, (c) => c.sure);
      if (sure !== null) return sure.cards;
    }
    return dump;
  }

  // MARK: Opponent winning

  private opponentWinning(): Card[] {
    const dump = this.builder.build(new CostModel(this.table, "dump"));
    const dumpCost = new CostModel(this.table, "keep").costOf(dump);
    const candidates = this.winningPlays();
    const stake = this.onTable + points(dump) + this.lastPlayerThreat;

    if (this.builder.held.length === 0 && this.ledGroup !== "trump") {
      return this.chooseRuff(candidates, stake, dumpCost)?.cards ?? dump;
    }
    if (this.isLast) {
      const limit = stake > 0 ? 10 + 4 * stake : 10;
      return this.firstAffordable(candidates, dumpCost, limit, () => true)?.cards ?? dump;
    }
    let sureLimit = stake > 0 ? 20 + 4 * stake : 10;
    if (this.partnerLater) sureLimit += 20;
    const sure = this.firstAffordable(candidates, dumpCost, sureLimit, (c) => c.sure);
    if (sure !== null) return sure.cards;
    if (this.worthContesting(stake)) {
      const best = this.firstAffordable(candidates, dumpCost, 10 + 2 * stake, (c) => points(c.cards) === 0);
      if (best !== null) return best.cards;
    }
    return dump;
  }

  private chooseRuff(candidates: readonly Candidate[], stake: number, dumpCost: number): Candidate | null {
    const { table, laterOpponents, ledGroup } = this;
    if (!this.worthRuffing(stake)) return null;
    const limit = 20 + 4 * stake;
    const threatened =
      !this.isLast &&
      (laterOpponents.some((player) => table.mayRuff(player, ledGroup)) ||
        table.isRunningOut(ledGroup, this.count, laterOpponents.length));
    if (!threatened) return this.firstAffordable(candidates, dumpCost, limit, () => true);
    const sure = this.firstAffordable(candidates, dumpCost, 40 + 4 * stake, (c) => c.sure);
    if (sure !== null) return sure;
    const high = this.firstAffordable(candidates, dumpCost, 30 + 4 * stake, (c) => c.key >= TOP_PLAIN_STRENGTH - 1);
    if (high !== null) return high;
    if (stake < 15) return null;
    return this.firstAffordable(candidates, dumpCost, limit, () => true);
  }
}
