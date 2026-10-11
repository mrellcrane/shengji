// A whole game: rounds while the teams climb from the start level to the target. Port of
// Engine/Game.swift. `GameState` is plain JSON-serialisable data; `recordRound` mutates it in place.

import { ACE, TABLE_FOUR, advanceRank, rankLabel, tableSize } from "./cards.ts";
import type { Card, Rank, TableSize } from "./cards.ts";
import { HUMAN_SEAT, normalizeSeat, seatName, teamOf } from "./rules.ts";
import { newRound, startBidding } from "./round.ts";
import type { Round, RoundResult } from "./round.ts";
import { levelPhrase, takeoverThreshold } from "./scoring.ts";

export interface GameSettings {
  /** Both teams start here. */
  startRank: Rank;
  /**
   * A team wins by holding the deal as declarers while at this level. Levels gained are capped
   * here ("you must defend your last level").
   */
  targetRank: Rank;
  /**
   * Players and decks: 4 with 2 decks (the classic game), 6 with 3 or 8 with 4. Absent in games
   * stored before bigger tables existed, which are for 4 players.
   */
  table?: TableSize;
}

export function defaultGameSettings(): GameSettings {
  return { startRank: 2, targetRank: ACE, table: { ...TABLE_FOUR } };
}

/** Players and decks of the game's table. */
export function gameTable(game: GameState): TableSize {
  return tableSize(game.settings.table?.players ?? 4);
}

/** Players at the game's table (4, 6 or 8). */
export function gamePlayers(game: GameState): number {
  return gameTable(game).players;
}

/** What changed after a round, for the results screen. */
export interface RoundSummary {
  result: RoundResult;
  /** Team whose level went up (null if nobody advanced). */
  advancingTeam: number | null;
  levelsGained: number;
  levelsBefore: Rank[];
  levelsAfter: Rank[];
  nextDealer: number;
  /** Set when this round ended the game. */
  gameWinner: number | null;
  /** Two or three plain-English sentences explaining what happened and why (seen from seat 0). */
  explanation: string;
}

export interface GameState {
  settings: GameSettings;
  /** Level per team (team 0 = the even seats, 0 and 2 with 4 players; team 1 = the odd seats). */
  levels: Rank[];
  /** Dealer of the next round; null before the first round (decided by declaring). */
  nextDealer: number | null;
  /** Number of rounds completed. */
  roundsPlayed: number;
  winner: number | null;
  history: RoundSummary[];
}

export function newGame(settings: GameSettings = defaultGameSettings()): GameState {
  const table = tableSize(settings.table?.players ?? 4);
  return {
    settings: { startRank: settings.startRank, targetRank: settings.targetRank, table },
    levels: [settings.startRank, settings.startRank],
    nextDealer: null,
    roundsPlayed: 0,
    winner: null,
    history: [],
  };
}

/** Trump rank of the next round: the dealer team's level (startRank in the first round). */
export function nextTrumpRank(game: GameState): Rank {
  if (game.nextDealer === null) return game.settings.startRank;
  const team = teamOf(game.nextDealer);
  return team >= 0 && team < game.levels.length ? game.levels[team] : game.settings.startRank;
}

/** The next round, dealt from `deck` (use `shuffledDeck(gameTable(game))` for real games). */
export function makeRound(game: GameState, deck: readonly Card[]): Round {
  return newRound(nextTrumpRank(game), game.nextDealer, deck, gameTable(game));
}

/**
 * The next round of an online game: dealt from `deck` with turn-based bidding open at the dealer,
 * or at `creatorSeat` in round 1 when the dealer is not known yet (DESIGN.md, Online multiplayer).
 */
export function startOnlineRound(game: GameState, deck: readonly Card[], creatorSeat: number): Round {
  const round = makeRound(game, deck);
  const error = startBidding(round, game.nextDealer ?? creatorSeat);
  if (error !== null) throw new Error(`could not open bidding: ${error.case}`);
  return round;
}

/**
 * Applies a finished round. Next dealer: if the declarers hold, the dealer's next teammate (two
 * seats on: the partner with 4 players); otherwise the player after the dealer (a defender).
 * Winner: declarers holding while at targetRank.
 */
export function recordRound(game: GameState, result: RoundResult): RoundSummary {
  while (game.levels.length < 2) {
    // Only reachable with damaged saved data: restore a level for each team.
    game.levels.push(game.settings.startRank);
  }
  // Swift's RoundResult is a value type: the history keeps its own copy, so later changes to the
  // round's result (or to the returned summary) never rewrite it.
  result = structuredClone(result);
  const players = gamePlayers(game);
  const dealer = normalizeSeat(result.dealer, players);
  const declarers = teamOf(dealer);
  const defenders = 1 - declarers;
  const outcome = result.outcome;
  const before = game.levels.slice();
  const target = game.settings.targetRank;

  const benefiting = outcome.declarersHold ? declarers : defenders;
  const gameWinner = outcome.declarersHold && before[declarers] >= target ? declarers : null;
  const newLevel = advanceRank(before[benefiting], outcome.levels, target);
  const gained = newLevel - before[benefiting];
  game.levels[benefiting] = newLevel;
  const next = normalizeSeat(dealer + (outcome.declarersHold ? 2 : 1), players);

  game.nextDealer = next;
  game.roundsPlayed += 1;
  if (game.winner === null) game.winner = gameWinner;

  const explanation = explainRound({
    result,
    team: benefiting,
    nominal: outcome.levels,
    gained,
    newLevel,
    gameWinner,
    target,
    nextDealer: next,
    nextLevel: game.levels[teamOf(next)],
    players,
  });
  const summary: RoundSummary = {
    result,
    advancingTeam: gained > 0 ? benefiting : null,
    levelsGained: gained,
    levelsBefore: before,
    levelsAfter: game.levels.slice(),
    nextDealer: next,
    gameWinner,
    explanation,
  };
  game.history.push(structuredClone(summary));
  return summary;
}

/** Inputs of the round explanation (see `explainRound`). */
export interface RoundExplanationInput {
  result: RoundResult;
  /** Team that benefits (declarers if they hold, else defenders). */
  team: number;
  /** Levels the score table awards before the cap. */
  nominal: number;
  /** Levels actually gained. */
  gained: number;
  newLevel: Rank;
  gameWinner: number | null;
  target: Rank;
  nextDealer: number;
  nextLevel: Rank;
  /** Players at the table (default 4). */
  players?: number;
}

/**
 * Two or three sentences explaining a round. Seen from `viewer` (default seat 0, which is exactly
 * the Swift text stored in `RoundSummary.explanation`); online, pass the viewer's seat so their own
 * team is "Your team".
 */
export function explainRound(input: RoundExplanationInput, viewer = HUMAN_SEAT): string {
  const { result } = input;
  const players = input.players ?? 4;
  const threshold = takeoverThreshold(tableSize(players).decks);
  const points = result.defenderPoints;
  const kittyBonus = result.kittyPoints * result.kittyMultiplier;
  const scored =
    kittyBonus > 0
      ? `The defenders scored ${points} points (including ${kittyBonus} from the kitty)`
      : `The defenders scored ${points} points`;
  const sentences: string[] = [];
  if (result.outcome.declarersHold) {
    sentences.push(`${scored}, short of ${threshold}, so the declarers keep the deal.`);
  } else {
    sentences.push(`${scored}, reaching ${threshold}, so they take over the deal.`);
  }

  const viewerTeam = teamOf(viewer);
  const subjectOf = (team: number): { name: string; plural: boolean } => {
    if (team === viewerTeam) return { name: "Your team", plural: false };
    return players > 4 ? { name: "The other team", plural: false } : { name: "East and West", plural: true };
  };
  const subject = subjectOf(input.team);
  if (input.gameWinner !== null) {
    const ending = input.gameWinner === viewerTeam ? "so you win the game!" : "so they win the game.";
    sentences.push(`${subjectOf(input.gameWinner).name} held the deal at level ${rankLabel(input.target)}, ${ending}`);
    return sentences.join(" ");
  }
  if (input.nominal === 0) {
    sentences.push("Nobody goes up a level this time.");
  } else if (input.gained === 0) {
    sentences.push(
      `${subject.name} ${subject.plural ? "stay" : "stays"} at level ${rankLabel(input.newLevel)}, the top level.`,
    );
  } else {
    const verb = subject.plural ? "go" : "goes";
    const levelsText = levelPhrase(input.gained);
    const capNote = input.gained < input.nominal ? ` (levels stop at ${rankLabel(input.target)})` : "";
    sentences.push(`${subject.name} ${verb} up ${levelsText}, to ${rankLabel(input.newLevel)}${capNote}.`);
  }
  const dealerVerb = input.nextDealer === viewer ? "deal" : "deals";
  sentences.push(`${seatName(input.nextDealer, viewer, players)} ${dealerVerb} next at level ${rankLabel(input.nextLevel)}.`);
  return sentences.join(" ");
}

/** The explanation of a recorded round as seen from `viewer` (seat 0 gives `summary.explanation`). */
export function summaryExplanation(game: GameState, summary: RoundSummary, viewer = HUMAN_SEAT): string {
  const players = gamePlayers(game);
  const declarers = teamOf(normalizeSeat(summary.result.dealer, players));
  const team = summary.result.outcome.declarersHold ? declarers : 1 - declarers;
  const newLevel = summary.levelsAfter[team];
  return explainRound(
    {
      result: summary.result,
      team,
      nominal: summary.result.outcome.levels,
      gained: summary.levelsGained,
      newLevel,
      gameWinner: summary.gameWinner,
      target: game.settings.targetRank,
      nextDealer: summary.nextDealer,
      nextLevel: summary.levelsAfter[teamOf(summary.nextDealer)],
      players,
    },
    viewer,
  );
}
