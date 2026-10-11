// Level changes after a round and the kitty multiplier. Port of Engine/Scoring.swift.

import type { Card } from "./cards.ts";
import { decompose, shapeCardCount } from "./combos.ts";
import type { Trump } from "./trump.ts";

/** What happens to the levels after a round. */
export interface LevelOutcome {
  /** True if the declarers (dealer's team) kept the deal (defenders < 80). */
  declarersHold: boolean;
  /** Levels gained by the side that benefits (declarers if they hold, else defenders). May be 0. */
  levels: number;
  /** e.g. "Defenders scored 85 (80 or more): they take over the deal but don't go up a level." */
  summary: string;
}

/** Two decks (the classic game). Every deck adds 100 points, and the lines scale with it. */
export const TOTAL_POINTS = 200;
export const TAKEOVER_THRESHOLD = 80;
export const STEP_SIZE = 40;

/** Points in all the cards: 100 per deck. */
export function totalPointsFor(decks: number): number {
  return 100 * Math.max(decks, 1);
}

/** Defenders take over the deal from 40 points per deck: 80 with 2 decks, 120 with 3, 160 with 4. */
export function takeoverThreshold(decks: number): number {
  return 40 * Math.max(decks, 1);
}

/** Each level is worth 20 points per deck: 40 with 2 decks, 60 with 3, 80 with 4. */
export function stepSize(decks: number): number {
  return 20 * Math.max(decks, 1);
}

/** "1 level", "2 levels". */
export function levelPhrase(levels: number): string {
  return levels === 1 ? "1 level" : `${levels} levels`;
}

/**
 * Standard table (two decks):
 *   0 -> declarers +3 · 5 to 35 -> declarers +2 · 40 to 75 -> declarers +1
 *   80 to 115 -> defenders take over (+0) · 120 to 155 -> take over +1 · 160 to 195 -> +2 ·
 *   200+ -> +3, each further 40 -> +1
 * With more decks the same table scales (`decks`): with 3 decks 5 to 55 -> declarers +2, 60 to 115
 * -> +1, 120 to 175 -> take over, then +1 for every further 60.
 */
export function scoreOutcome(defenderPoints: number, decks = 2): LevelOutcome {
  const points = Math.max(0, defenderPoints);
  const threshold = takeoverThreshold(decks);
  const step = stepSize(decks);
  if (points < threshold) {
    let levels: number;
    let scored: string;
    if (points === 0) {
      levels = 3;
      scored = "Defenders scored 0";
    } else if (points < step) {
      levels = 2;
      scored = `Defenders scored ${points} (under ${step})`;
    } else {
      levels = 1;
      scored = `Defenders scored ${points} (under ${threshold})`;
    }
    return {
      declarersHold: true,
      levels,
      summary: `${scored}: the declarers keep the deal and go up ${levelPhrase(levels)}.`,
    };
  }
  const levels = Math.trunc((points - threshold) / step);
  const line = threshold + levels * step;
  const effect =
    levels === 0
      ? "they take over the deal but don't go up a level."
      : `they take over the deal and go up ${levelPhrase(levels)}.`;
  return { declarersHold: false, levels, summary: `Defenders scored ${points} (${line} or more): ${effect}` };
}

/**
 * Finding Friends: a dealer's side that keeps the deal with fewer players than it could have had (the
 * dealer played a card they called, or a called card was never played) goes up 1 more level.
 * `declarers` = players on the dealer's side at the end, `fullSide` = the dealer plus every friend
 * called. Swift `Scoring.findingFriendsOutcome`.
 */
export function findingFriendsOutcome(outcome: LevelOutcome, declarers: number, fullSide: number): LevelOutcome {
  if (!outcome.declarersHold || declarers >= fullSide) return { ...outcome };
  const levels = outcome.levels + 1;
  let summary = outcome.summary;
  if (summary.endsWith(".")) summary = summary.slice(0, -1);
  summary += `, plus 1 for playing short-handed (${declarers} of ${fullSide}): ${levelPhrase(levels)} in all.`;
  return { declarersHold: true, levels, summary };
}

/**
 * Kitty multiplier when the defenders win the last trick: 2 x the number of cards in the largest
 * component of the last trick's lead (single x2, pair x4, triple x6, 2-pair tractor x8, 3-pair x12).
 */
export function kittyMultiplier(lastLead: readonly Card[], trump: Trump): number {
  const components = decompose(lastLead, trump);
  let largest = 1;
  if (components.length > 0) {
    largest = Math.max(...components.map((component) => shapeCardCount(component.shape)));
  }
  return 2 * largest;
}
