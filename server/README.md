# Shengji server

The online multiplayer server (DESIGN.md, Online multiplayer). So far it holds the **game engine**:
a TypeScript port of the Swift engine in `ShengjiCore/Sources/ShengjiCore/Engine`, proven identical
to it by test vectors that the Swift engine generates.

```
src/engine/   cards, trump, combos, rules, scoring, round, game  (ports of the Swift files)
              view.ts     per-seat views (privacy)
              shuffle.ts  crypto-quality shuffling for real games
              index.ts    re-exports everything
test/         node:test suites; test/vectors/ holds the generated Swift vectors
```

Node 22, TypeScript 5.9, ES modules, no build step for tests:

```
npm ci
npm run typecheck
npm test            # node --experimental-strip-types --test test/*.test.ts
```

## The engine

Plain data and functions, no classes: every state object (`Round`, `GameState`, views) is
JSON-serialisable and survives `JSON.parse(JSON.stringify(x))` exactly, so a Durable Object can
store it as is. Functions that change a round (`dealNext`, `declare`, `bid`, `bury`, `play`, ...)
mutate it in place like the Swift mutating methods and return an error value instead of throwing;
when they return an error they have not changed anything. `cloneRound` makes a copy.

- Cards are their Swift `Card.id`, 0...107 (face index + copy x 54; 52/53 are the small and big
  joker). Suits and ranks are the Swift raw values (suits 0 = spades, 1 = hearts, 2 = clubs,
  3 = diamonds; ranks 2...14). A suit group is `"trump"` or a suit. Shapes are
  `{type: "single" | "pair" | "tractor", pairs}`.
- Errors and outcomes are tagged unions mirroring the Swift enums (`{case: "illegalFollow",
  violation: {case: "mustFollowSuit", group: 1}}`), with the same learner-facing text from
  `roundErrorExplanation`, `followViolationExplanation`, `leadViolationExplanation`,
  `declarationDescription`, `scoreOutcome(...).summary` and `RoundSummary.explanation`.
- Swift names map directly: `Rules.validateFollow` is `validateFollow`, `Combos.decompose` is
  `decompose`, `Round.play(_:by:)` is `play(round, cards, player)`, and so on.
- Additions for online play: `seatName`, `declarationDescription` and `explainRound` take an
  optional `viewer` seat so each player reads "You" for themselves (seat 0 gives the Swift text);
  `bury` takes an optional seat and rejects anyone but the dealer; `newRound` rejects a deck that
  is not exactly the 108 cards; `parseDeclaration` checks the shape of a client message.

### Online bidding (no Swift counterpart)

`startBidding(round, firstBidder)` deals all 100 cards at once and opens turn-based declaring at
`firstBidder` (the dealer, or the game creator's seat in round 1; `startOnlineRound(game, deck,
creatorSeat)` does both steps). Then, in seat order:

- `biddingTurn(round)` is the seat to act; `availableBids(round, seat)` is what that seat may
  declare now (exactly the offline `availableDeclarations`: strictly stronger than the current
  declaration) and is empty for everyone else.
- `bid(round, seat, declaration | "pass")`. A declaration resets the pass count.
- Bidding ends when the three other players have passed since the last declaration, or when all
  four pass with no declaration at all (then the kitty flip sets trump, as offline). The round then
  moves to burying exactly as `finishDealing` does. In round 1 the winning declarer deals; if
  nobody declared, the first bidder deals.
- Because three passes in a row after a declaration end the bidding, the current declarer never
  gets another turn while holding the declaration, so the offline "reinforce your own single to a
  pair" move cannot arise online; declaring a pair straight away is the stronger bid. A player
  whose declaration was overridden may override back with anything stronger.
- While bidding is open, `declare` returns `wrongPhase` and `finishDealing` does nothing.

### Views and privacy

`viewFor(round, seat)` is what one seat may see: its own hand (sorted for display), every hand's
card count, the trump, dealer and declarers, declarations and bids (their cards were shown),
the bidding turn and that seat's available bids, every play of the current and past tricks, the
defenders' points, the result when finished, and the kitty card turned up when nobody declared.
It never contains another hand or the undealt cards; the kitty only for the dealer while holding
it or after burying it, and for everyone once the round is finished. The tests check this over
thousands of random states, including that a view does not change when the hidden cards are
shuffled among the hidden places.

## Parity vectors

`test/vectors/*.json` are written by the Swift `ShengjiVectors` executable from fixed seeds:

```
cd ShengjiCore && swift run ShengjiVectors ../server/test/vectors
```

Regenerate them whenever the Swift engine changes (CI fails with "Vectors in sync" otherwise),
then make `npm test` pass again. `test/vectors.test.ts` replays every vector and prints the first
differing paths of each mismatch. Field names match the TypeScript types.

- `combos.json`: suit, rank (including `advanced(by:cap:)`), face, group and shape tables; for
  every trump context (13 ranks x 5 suit choices) the trump membership, group, strength and sort
  key of every face, the trump order and the sorted deck; and 1200 card sets biased to tricky
  cases (pairs of off-suit rank cards, tractors across the skipped rank, jokers, no trump, mixed
  groups) with `decompose`, `shape`, pairs, tractors of each length, singles, `isThrow` and the
  kitty multiplier.
- `rules.json`: 1200 positions (trump, four hands, leader). Each has lead attempts with
  `validateLead` and its explanation, `isThrow`, `checkThrow` against the hands and against a
  card pool; for each follower the `followRequirement` and several plays (legal ones built from
  the rules, ruffs, and many illegal ones) with `validateFollow` (absent = legal, else the
  violation and its explanation) and `matchesStructure`; and tricks with `winningIndex` for every
  prefix, including probe tricks of pair-rich plays against tractor leads.
- `rounds.json`: 200 rounds driven through the `Round` API: deck order, dealer (or null), trump
  rank and an action list (dealing, declarations with every seat's `availableDeclarations`,
  state snapshots, `finishDealing`, bury attempts, every play attempt with its error and
  explanation, or its outcome (absent = played) and the finished trick's winner and points),
  then the `RoundResult`.
- `games.json`: the scoring table, and 30 games of `GameState` progression (levels, next dealer,
  winner, `RoundSummary` and its explanation) over many rounds, from played rounds or synthetic
  results that reach every outcome band.
