# Shengji server

The online multiplayer server (DESIGN.md, Online multiplayer): the Cloudflare Worker
`shengji-online` (free plan) that implements docs/online-protocol.md for the iOS app. It runs on a
TypeScript port of the Swift engine in `ShengjiCore/Sources/ShengjiCore/Engine`, proven identical
to it by test vectors that the Swift engine generates (including the per-seat views the app decodes).

```
src/worker.ts   Worker entry: wires the bindings into the router; exports the Durable Objects
src/api/        router.ts (HTTP routes, auth, rate limits), validate.ts (input checks), result.ts
src/auth/       apple.ts (Sign in with Apple JWT verification, JWKS cache), crypto.ts (tokens, ids, codes)
src/hub/        service.ts (users, identities, sessions, devices, clubs, games index over SQL), host.ts (RPC surface, push delivery)
src/room/       service.ts (one game's state and action log over SQL), host.ts (publishes changes)
src/game/       online.ts (the online game: turns, bots between humans, rounds, notifications),
                summary.ts (GameSummary, lastEvent lines), bots.ts (placeholder bots)
src/push/       apns.ts (ES256 provider token, APNs requests)
src/durable/    hub.ts, room.ts (thin Durable Object adapters: RPC, WebSockets), sql.ts
src/storage/    sql.ts (the one storage interface: synchronous SQLite)
src/engine/     cards, trump, combos, rules, scoring, round, game  (ports of the Swift files)
                seatview.ts the wire view (Swift SeatView, viewer-relative), view.ts absolute views
                shuffle.ts  crypto-quality shuffling for real games
scripts/        smoke.ts (end-to-end test of a running server), e2e.ts (runs it on wrangler dev),
                viewcheck.ts (view checks shared with the tests)
test/           node:test suites; test/vectors/ holds the generated Swift vectors
```

Node 22.13 or later (node:sqlite runs the storage tests), TypeScript 5.9, ES modules, no build step for tests:

```
npm ci
npm run typecheck   # wrangler types, then the Node and the Worker configurations
npm test            # node --experimental-strip-types --test test/*.test.ts
npm run e2e         # the whole API in wrangler dev (workerd), see Testing
```

## How it works

Two kinds of Durable Objects, both SQLite-backed (`new_sqlite_classes`):

- **Hub**, a single instance named `hub`: users, linked sign-in identities (`provider` + `subject`:
  `apple` now, `google` later, `dev` for smoke tests), sessions (only the SHA-256 of each random
  32-byte token is stored; 180 days), devices, clubs and memberships, and the games index: one row
  per game with a public snapshot (players, levels, phase, whose turn, last event), so game lists
  never wake the GameRooms.
- **GameRoom**, one per game (named by the game id): the authoritative `GameState` and `Round`
  with a version that grows with every change, seat assignments (a user id or a bot level per
  absolute seat), an action log of every move (bots too) and every deck dealt, and the live
  WebSockets (hibernation API, so idle sockets cost nothing).

The logic lives in plain modules over a tiny `Sql` interface (`exec`, `transaction`), so the tests
run the real SQL on node:sqlite; the Durable Object classes only forward RPC calls. Every request:
rate limit by IP, then the session (one Hub call), then a rate limit by user, then the Hub or the
game's room. After an accepted move the room runs bot turns until a person must act (a finished
round is recorded and the next one dealt at once), saves state and log in one transaction, sends
each connected socket its own seat's update, updates the Hub's index (awaited, so lists are
current), and returns the pushes, which the Worker sends with `ctx.waitUntil` so the reply never
waits for APNs.

**Privacy.** Every view is built by `toSeatView` from what that seat may see (DESIGN.md); game
summaries and their `lastEvent` lines come from public facts only. test/privacy.test.ts checks
every state a client can receive in many random games, for all four seats and every message
(replies, WebSocket updates, summaries), and that shuffling a seat's hidden cards never changes
what it receives.

**Bots** (`src/game/bots.ts`) are a deterministic placeholder behind one narrow function,
`chooseBotAction(round, seat, level)`, that reads only the bot's own hand and public facts:
bid only a pair of trump-rank cards in the longest suit; bury the lowest non-trumps; lead an ace or
a low card; follow with a legal play found among candidates checked by the engine (cheapest, or the
cheapest winner when points are at stake). A port of the Swift bots replaces it later.

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
  is not exactly the 108 cards; `parseDeclaration` checks the shape of a client message (a
  missing `suit` means no trump suit, which is how the Swift app's `Codable` sends a joker pair),
  and `declare` and `bid` run it too, so a malformed declaration is refused with
  `invalidDeclaration` instead of throwing.
- Value semantics as in Swift: `recordRound` keeps its own copy of the result in the history, and
  views share no objects with the round.

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

`toSeatView(game, round, seat, players)` (seatview.ts) is the wire view: a port of Swift
`Round.seatView(for:players:game:)`, rotated so the viewer is seat 0, plus the online bidding state
(`bidding`: turn, history, and the viewer's own options on their turn). views.json proves the
JSON is identical to the Swift `SeatView` Codable for all four seats.

`viewFor(round, seat)` (view.ts) is the older absolute-seat view of one round: its own hand (sorted
for display), every hand's card count, the trump, dealer and declarers, declarations and bids,
the bidding turn and that seat's available bids, every play, the defenders' points, the result
when finished, and the kitty flip card. Both never contain another hand or the undealt cards; the
kitty only for the dealer while holding it or after burying it, and for everyone once the round is
finished. The tests check this over thousands of random states, including that a view does not
change when the hidden cards are shuffled among the hidden places.

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
- `views.json`: about 100 points of up to 40 rounds in 20 games (just after the deal closes, after
  burying, mid-play often mid-trick, finished, and finished and recorded, sometimes winning the
  game), each with its inputs (players, the `GameState` with its last history entry, the `Round`)
  and the four views exactly as Swift's `JSONEncoder` writes `SeatView`. The test compares parsed
  objects, treating an absent optional as null.
- `edges.json`: targeted cases for branches the random files reach rarely. The declaration text
  for every strength (0...5), suit and card variant (including no cards). 200 kitty flips through
  `finishDealing` (a trump-rank card or a joker first, the only one coming late, the highest card
  with ties), with and without a known dealer. 200 throws checked against the hands and a pool,
  about half of them with two or more beatable components that tie on size and strength (equal
  trump-rank cards, so display order picks the forced one), some with leader seats outside 0...3
  and short hand lists. 200 follows to leads of two or three tractors, with plays that hold only
  some of the required tractors (which length `mustPlayTractor` names). 200 tricks where a
  plain-suit lead, often a throw, is ruffed and over-ruffed.

## Testing

`npm test` runs, in Node, without workerd:

- the engine suites and the parity vectors (above), including views.json;
- auth.test.ts: Sign in with Apple tokens signed with a locally generated RSA key against a fake
  JWKS (issuer, audience, expiry, clock skew, tampering, `alg` games, key rotation, the JWKS cache),
  session tokens, constant-time comparison, ids and invite codes;
- hub.test.ts: identities and sessions (180 days, at most 20), devices, clubs (codes in any case,
  members only, the last one out closes the club), game creation checks, the games index;
- api.test.ts and games.test.ts: the whole HTTP API on the in-process "cloud" (test/cloud.ts: the
  real router, Hub and GameRooms over node:sqlite, with RPC-style cloning): sign-in, rate limits,
  body limits, validation, a whole round with bots, a game played to the end with pushes, stale
  versions, illegal moves with the engine's explanation, failed throws, nudges, renames, deletion;
- privacy.test.ts (see above), bots.test.ts (150 all-bot rounds: every move legal, deterministic),
  seatview.test.ts (bidding views, summaries, event lines), push.test.ts (ES256 provider tokens
  signed with a generated P-256 key and verified, the 50-minute cache, APNs requests and replies with
  fetch mocked, device clean-up, and that a hanging APNs never delays a reply).

`npm run e2e` starts `wrangler dev` (workerd with real SQLite Durable Objects, rate limiters and
WebSockets) on a free port with fresh storage and a random `DEV_AUTH_SECRET`, then runs
scripts/smoke.ts against it: two dev users make a club and join it, start a game with two bots, open
the live WebSocket for both, and play a whole round, each choosing moves from their own view only;
it checks the error paths (401, 403 not_your_turn, 409 stale, 400 illegal, 426, nudges), the game
and club lists, that both sockets get every update in order up to the final version, that no view
(HTTP or WebSocket) shows a card of another hand or a hidden kitty, then deletes the game (sockets
close with 4004) and leaves the club. It prints a JSON report. The same script runs against a
deployed Worker:

```
node --experimental-strip-types scripts/smoke.ts https://shengji-online.<subdomain>.workers.dev <DEV_AUTH_SECRET>
```

## Operations

**Deploying.** `.github/workflows/deploy-server.yml` runs on pushes to `server/**` (branches `main`
and `claude/epic-einstein-25elio`) or by hand: typecheck and tests, then `wrangler deploy --var
VERSION:<git sha>` (so `/health` names the commit), then one `wrangler secret bulk` with a fresh
random `DEV_AUTH_SECRET` (and the APNs secrets when the repository has them), then the smoke test
against the deployed URL (retried while the new version settles). The URL and the smoke test's
checks go to the job summary. Without `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` the deploy
job is skipped with a notice. By hand: `npx wrangler deploy` in `server/`.

**Secrets.** Worker secrets, never in the repository:

| Secret | Purpose |
|---|---|
| `DEV_AUTH_SECRET` | enables `POST /v1/auth/dev`; replaced on every deploy and known only to that deploy's smoke test. `npx wrangler secret delete DEV_AUTH_SECRET` switches dev sign-in off until the next deploy. |
| `APNS_KEY_P8`, `APNS_KEY_ID`, `APPLE_TEAM_ID` | push notifications. Create an APNs key (Apple Developer, Keys, "Apple Push Notifications service"), add the .p8 file's contents and its key id as the repository secrets `APNS_KEY_P8` and `APNS_KEY_ID` (`APPLE_TEAM_ID` is already there for TestFlight), and rerun the workflow. `/health` then says `"push": true`. |

Without the APNs secrets push is off and everything else works; devices are still registered, so
pushes start as soon as the key is added. The app must send `environment: "sandbox"` from debug
builds and `"production"` from TestFlight and App Store builds; a token sent to the wrong
environment is reported as `BadDeviceToken` and forgotten (the app registers it again on launch).

**Running locally.** `npx wrangler dev --var DEV_AUTH_SECRET:something` (or put secrets in
`server/.dev.vars`, which is gitignored). State persists in `server/.wrangler/` between runs;
delete that folder for a clean start. `npm run e2e` uses its own temporary storage.

**Watching.** `npx wrangler tail shengji-online` streams live logs (Workers observability is on, so
the dashboard keeps them too). The server logs failed pushes, unexpected errors and Apple key
fetch failures with `console.error`. `GET /health` returns `{"ok", "version", "push"}`.

**Data.** Everything lives in the Durable Objects' SQLite storage: the Hub (tables `users`,
`identities`, `sessions`, `devices`, `clubs`, `memberships`, `games`, `game_players`,
`deleted_games`) and one GameRoom per game (`state`: the game as JSON with its version; `log`: every
action, bot move and dealt deck, for settling disputes; never sent to players). Deleting a game
drops its room's storage. Schema changes are additive `CREATE TABLE IF NOT EXISTS` statements run
when an object starts; a new Durable Object class needs a new `[[migrations]]` tag in wrangler.toml.

**Limits and costs.** Built for the Workers free plan: SQLite Durable Objects, WebSocket hibernation
(idle sockets cost nothing), and little work per request (a move plus at most about one round of
bot turns). Rate limits (wrangler.toml): 120 requests a minute per user, 300 per IP, 20 sign-ins
per IP and 20 invite-code tries per user. Product limits (src/hub/service.ts): 20 clubs per user,
50 members per club, 30 active games per player, 10 devices per user, 20 sessions per user.

**Known gaps.** Sessions cannot be revoked one by one yet (they expire after 180 days); there is no
account deletion endpoint yet (needed before an App Store release); APNs has only been exercised
with a mocked fetch until a key exists (APNs requires HTTP/2 from Workers' fetch; failed pushes are
logged with APNs' reason); the bots are a simple placeholder until the Swift bots are ported.
