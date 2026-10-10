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

export const TOTAL_POINTS = 200;
export const TAKEOVER_THRESHOLD = 80;
export const STEP_SIZE = 40;

/** "1 level", "2 levels". */
export function levelPhrase(levels: number): string {
  return levels === 1 ? "1 level" : `${levels} levels`;
}

/**
 * Standard table (two decks):
 *   0 -> declarers +3 · 5 to 35 -> declarers +2 · 40 to 75 -> declarers +1
 *   80 to 115 -> defenders take over (+0) · 120 to 155 -> take over +1 · 160 to 195 -> +2 ·
 *   200+ -> +3, each further 40 -> +1
 */
export function scoreOutcome(defenderPoints: number): LevelOutcome {
  const points = Math.max(0, defenderPoints);
  if (points < TAKEOVER_THRESHOLD) {
    let levels: number;
    let scored: string;
    if (points === 0) {
      levels = 3;
      scored = "Defenders scored 0";
    } else if (points < STEP_SIZE) {
      levels = 2;
      scored = `Defenders scored ${points} (under ${STEP_SIZE})`;
    } else {
      levels = 1;
      scored = `Defenders scored ${points} (under ${TAKEOVER_THRESHOLD})`;
    }
    return {
      declarersHold: true,
      levels,
      summary: `${scored}: the declarers keep the deal and go up ${levelPhrase(levels)}.`,
    };
  }
  const levels = Math.trunc((points - TAKEOVER_THRESHOLD) / STEP_SIZE);
  const line = TAKEOVER_THRESHOLD + levels * STEP_SIZE;
  const effect =
    levels === 0
      ? "they take over the deal but don't go up a level."
      : `they take over the deal and go up ${levelPhrase(levels)}.`;
  return { declarersHold: false, levels, summary: `Defenders scored ${points} (${line} or more): ${effect}` };
}

/**
 * Kitty multiplier when the defenders win the last trick: 2 x the number of cards in the largest
 * component of the last trick's lead (single x2, pair x4, 2-pair tractor x8, 3-pair x12).
 */
export function kittyMultiplier(lastLead: readonly Card[], trump: Trump): number {
  const components = decompose(lastLead, trump);
  let largest = 1;
  if (components.length > 0) {
    largest = Math.max(...components.map((component) => shapeCardCount(component.shape)));
  }
  return 2 * largest;
}
