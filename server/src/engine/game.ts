// A whole game: rounds while the teams climb from the start level to the target. Port of
// Engine/Game.swift (and `RoundSummary.rotated` from Engine/SeatView.swift). `GameState` is plain
// JSON-serialisable data; `recordRound` mutates it in place. With Finding Friends (an odd number of
// players) everyone climbs on their own: one level per seat.

import { ACE, TABLE_FOUR, advanceRank, rankLabel, tableFindsFriends, tableSize, tableTeamSize } from "./cards.ts";
import type { Card, Rank, TableSize } from "./cards.ts";
import { HUMAN_SEAT, nextSeat, normalizeSeat, seatName, teamOf } from "./rules.ts";
import { newRound, resultTeamRotation, rotateResult, startBidding } from "./round.ts";
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
   * Players and decks: 4 with 2 decks (the classic game), up to 9 with 5. Odd tables play Finding
   * Friends. Absent in games stored before bigger tables existed, which are for 4 players.
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

/** Players at the game's table (4 to 9). */
export function gamePlayers(game: GameState): number {
  return gameTable(game).players;
}

/** True when everyone keeps their own level and the dealer calls friends (an odd number of players). */
export function gameFindsFriends(game: GameState): boolean {
  return tableFindsFriends(gameTable(game));
}

/** Levels kept: one per team, or one per seat with Finding Friends. */
export function levelCount(table: TableSize): number {
  return tableFindsFriends(table) ? table.players : 2;
}

/** The level `seat` plays at: their team's, or with Finding Friends their own. Swift `GameState.level(of:)`. */
export function levelOf(game: GameState, seat: number): Rank {
  const index = gameFindsFriends(game) ? normalizeSeat(seat, gamePlayers(game)) : teamOf(seat);
  return index >= 0 && index < game.levels.length ? game.levels[index] : game.settings.startRank;
}

/** What changed after a round, for the results screen. */
export interface RoundSummary {
  result: RoundResult;
  /** Team whose level went up (null if nobody advanced). With Finding Friends: 0 if seat 0's side went up. */
  advancingTeam: number | null;
  /** Levels gained (with Finding Friends, the most any one player gained: levels stop at the target). */
  levelsGained: number;
  /** Levels per team, or with Finding Friends per seat. */
  levelsBefore: Rank[];
  levelsAfter: Rank[];
  nextDealer: number;
  /**
   * Set when this round ended the game: the winning team (with Finding Friends 0 if seat 0 was on
   * the dealer's side, which won; the winners are `result.declarers`).
   */
  gameWinner: number | null;
  /** Two or three plain-English sentences explaining what happened and why (seen from seat 0). */
  explanation: string;
}

export interface GameState {
  settings: GameSettings;
  /**
   * Level per team (team 0 = the even seats, 0 and 2 with 4 players; team 1 = the odd seats). With
   * Finding Friends: one level per seat.
   */
  levels: Rank[];
  /** Dealer of the next round; null before the first round (decided by declaring). */
  nextDealer: number | null;
  /** Number of rounds completed. */
  roundsPlayed: number;
  /**
   * The team that won the game. With Finding Friends: 0 if seat 0 was on the winning side, else 1
   * (the winners are the last round's `result.declarers`).
   */
  winner: number | null;
  history: RoundSummary[];
}

export function newGame(settings: GameSettings = defaultGameSettings()): GameState {
  const table = tableSize(settings.table?.players ?? 4);
  return {
    settings: { startRank: settings.startRank, targetRank: settings.targetRank, table },
    levels: Array.from({ length: levelCount(table) }, () => settings.startRank),
    nextDealer: null,
    roundsPlayed: 0,
    winner: null,
    history: [],
  };
}

/** Trump rank of the next round: the dealer's level (startRank in the first round). */
export function nextTrumpRank(game: GameState): Rank {
  if (game.nextDealer === null) return game.settings.startRank;
  return levelOf(game, game.nextDealer);
}

/**
 * The seats that won the game (absolute), or null while it goes on: the winning team's seats, or
 * with Finding Friends the dealer's side of the last round (which won by holding the deal).
 */
export function gameWinners(game: GameState): number[] | null {
  if (game.winner === null) return null;
  const players = gamePlayers(game);
  const last = game.history.length > 0 ? game.history[game.history.length - 1] : null;
  if (gameFindsFriends(game) && last !== null) {
    const side = new Set((last.result.declarers ?? []).map((seat) => normalizeSeat(seat, players)));
    side.add(normalizeSeat(last.result.dealer, players));
    return [...side].sort((a, b) => a - b);
  }
  return Array.from({ length: players }, (_, seat) => seat).filter((seat) => teamOf(seat) === game.winner);
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
  if (gameFindsFriends(game)) return recordFindingFriends(game, result);
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

/**
 * Finding Friends: everyone on the side that wins the round goes up on their own (levels stop at the
 * target). Next dealer: if the dealer's side holds, its next player after the dealer (the dealer
 * again if they played alone); otherwise the first defender after the dealer. The game is won when
 * the dealer's side holds while the dealer is at the target level. Swift `recordFindingFriends`.
 */
function recordFindingFriends(game: GameState, result: RoundResult): RoundSummary {
  const n = gamePlayers(game);
  while (game.levels.length < n) {
    // Only reachable with damaged saved data: restore a level for each seat.
    game.levels.push(game.settings.startRank);
  }
  result = structuredClone(result);
  const dealer = normalizeSeat(result.dealer, n);
  const declarers = new Set((result.declarers ?? []).map((seat) => normalizeSeat(seat, n)));
  declarers.add(dealer);
  const outcome = result.outcome;
  const before = game.levels.slice();
  const target = game.settings.targetRank;
  const holds = outcome.declarersHold;
  const side = (seat: number): number => (declarers.has(seat) === declarers.has(0) ? 0 : 1);

  let gained = 0;
  for (let seat = 0; seat < n; seat++) {
    if (declarers.has(seat) !== holds) continue;
    const newLevel = advanceRank(before[seat], outcome.levels, target);
    gained = Math.max(gained, newLevel - before[seat]);
    game.levels[seat] = newLevel;
  }
  const gameWinner = holds && before[dealer] >= target ? side(dealer) : null;
  const after = Array.from({ length: n - 1 }, (_, i) => normalizeSeat(dealer + i + 1, n));
  const next = holds
    ? (after.find((seat) => declarers.has(seat)) ?? dealer)
    : (after.find((seat) => !declarers.has(seat)) ?? nextSeat(dealer, n));

  game.nextDealer = next;
  game.roundsPlayed += 1;
  if (game.winner === null) game.winner = gameWinner;

  const summary: RoundSummary = {
    result,
    advancingTeam: gained > 0 ? (holds ? side(dealer) : 1 - side(dealer)) : null,
    levelsGained: gained,
    levelsBefore: before,
    levelsAfter: game.levels.slice(),
    nextDealer: next,
    gameWinner,
    explanation: "",
  };
  summary.explanation = explainFindingFriends(summary, target, n);
  game.history.push(structuredClone(summary));
  return summary;
}

/**
 * "Nobody", "East", "You and East", "East, you and Northwest": seats by name from seat 0, which is
 * "you" inside the list and "You" when it comes first.
 */
function seatList(seats: readonly number[], players: number): string {
  const list = seats.map((seat, index) =>
    seat === HUMAN_SEAT && index > 0 ? "you" : seatName(seat, HUMAN_SEAT, players),
  );
  switch (list.length) {
    case 0:
      return "Nobody";
    case 1:
      return list[0];
    default:
      return `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`;
  }
}

/**
 * The explanation of a Finding Friends round from seat 0's point of view (seat 0 is "you"). Swift
 * `GameState.explainFindingFriends`; for another viewer, explain the summary rotated to them
 * (`rotateSummary`).
 */
export function explainFindingFriends(summary: RoundSummary, target: Rank, players: number): string {
  const result = summary.result;
  const n = players;
  const threshold = takeoverThreshold(tableSize(n).decks);
  const declarers = result.declarers ?? [result.dealer];
  const points = result.defenderPoints;
  const kittyBonus = result.kittyPoints * result.kittyMultiplier;
  const scored =
    kittyBonus > 0
      ? `The defenders scored ${points} points (including ${kittyBonus} from the kitty)`
      : `The defenders scored ${points} points`;
  const sentences: string[] = [];
  if (declarers.length === 1) {
    sentences.push(`${seatList(declarers, n)} played alone: no friend joined.`);
  } else {
    sentences.push(`${seatList(declarers, n)} played together as the dealer's side.`);
  }
  const holds = result.outcome.declarersHold;
  if (holds) {
    sentences.push(`${scored}, short of ${threshold}, so the dealer's side keeps the deal.`);
  } else {
    sentences.push(`${scored}, reaching ${threshold}, so they take over the deal.`);
  }
  const fullSide = tableTeamSize(tableSize(n));
  const advancing = Array.from({ length: n }, (_, seat) => seat).filter((seat) => declarers.includes(seat) === holds);
  const dealerName = seatName(result.dealer, HUMAN_SEAT, n);
  if (summary.gameWinner !== null) {
    const ending = declarers.includes(0) ? "so you win the game!" : "so they win the game.";
    sentences.push(`${dealerName} held the deal at level ${rankLabel(target)}, ${ending}`);
    return sentences.join(" ");
  }
  const nominal = result.outcome.levels;
  if (nominal === 0) {
    sentences.push("Nobody goes up a level this time.");
  } else {
    const who = holds ? (declarers.length === 1 ? dealerName : "The dealer's side") : "The defenders";
    const plural = who === "The defenders" || who === seatName(HUMAN_SEAT, HUMAN_SEAT, n);
    const verb = plural ? "go" : "goes";
    const bonus = holds && declarers.length < fullSide ? " (1 of them for playing short-handed)" : "";
    const capped = advancing.some((seat) => summary.levelsAfter[seat] - summary.levelsBefore[seat] < nominal);
    const capNote = capped ? `, but levels stop at ${rankLabel(target)}` : "";
    sentences.push(`${who} ${verb} up ${levelPhrase(nominal)}${bonus}${capNote}.`);
  }
  if (summary.levelsBefore.length > 0 && summary.levelsAfter.length > 0 && summary.levelsAfter[0] !== summary.levelsBefore[0]) {
    sentences.push(`You are now at level ${rankLabel(summary.levelsAfter[0])}.`);
  }
  const next = summary.nextDealer;
  const nextLevel = next >= 0 && next < summary.levelsAfter.length ? summary.levelsAfter[next] : target;
  const dealerVerb = next === HUMAN_SEAT ? "deal" : "deals";
  sentences.push(`${seatName(next, HUMAN_SEAT, n)} ${dealerVerb} next at level ${rankLabel(nextLevel)}.`);
  return sentences.join(" ");
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
  if (gameFindsFriends(game)) {
    const seen = rotateSummary(summary, viewer, game.settings.targetRank, players);
    return explainFindingFriends(seen, game.settings.targetRank, players);
  }
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

// MARK: Rotation (Swift `RoundSummary.rotated(by:target:players:)`)

function rotateTeams<T>(values: readonly T[], viewer: number): T[] {
  if (values.length !== 2) return values.slice();
  const out = values.slice();
  out[(0 + viewer) % 2] = values[0];
  out[(1 + viewer) % 2] = values[1];
  return out;
}

/**
 * The same summary from `viewer`'s point of view at a table of `players`: seats and teams rotated,
 * explanation rewritten so the viewer's team is "Your team" (with Finding Friends, so the viewer is
 * "You": levels per seat rotate too, and team numbers swap when the viewer was on the other side
 * from seat 0). Swift `RoundSummary.rotated(by:target:players:)`. Always a copy.
 */
export function rotateSummary(summary: RoundSummary, viewer: number, target: Rank, players = 4): RoundSummary {
  const n = tableSize(players).players;
  const v = normalizeSeat(viewer, n);
  if (v === 0) return structuredClone(summary);
  const team = resultTeamRotation(summary.result, v, n);
  const result = rotateResult(summary.result, v, n);
  const next = normalizeSeat(summary.nextDealer - v, n);
  const gameWinner = summary.gameWinner === null ? null : team(summary.gameWinner);
  const advancingTeam = summary.advancingTeam === null ? null : team(summary.advancingTeam);

  if (tableFindsFriends(tableSize(n))) {
    const rotateSeats = (values: readonly Rank[]): Rank[] =>
      values.length === n ? Array.from({ length: n }, (_, i) => values[(i + v) % n]) : values.slice();
    const rotated: RoundSummary = {
      result,
      advancingTeam,
      levelsGained: summary.levelsGained,
      levelsBefore: rotateSeats(summary.levelsBefore),
      levelsAfter: rotateSeats(summary.levelsAfter),
      nextDealer: next,
      gameWinner,
      explanation: "",
    };
    rotated.explanation = explainFindingFriends(rotated, target, n);
    return rotated;
  }

  const after = rotateTeams(summary.levelsAfter, v);
  const benefiting = result.outcome.declarersHold ? result.declarerTeam : 1 - result.declarerTeam;
  const explanation = explainRound({
    result,
    team: benefiting,
    nominal: result.outcome.levels,
    gained: summary.levelsGained,
    newLevel: after[benefiting],
    gameWinner,
    target,
    nextDealer: next,
    nextLevel: after[next % 2],
    players: n,
  });
  return {
    result,
    advancingTeam,
    levelsGained: summary.levelsGained,
    levelsBefore: rotateTeams(summary.levelsBefore, v),
    levelsAfter: after,
    nextDealer: next,
    gameWinner,
    explanation,
  };
}
