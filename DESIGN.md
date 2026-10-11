# Shengji · Tractor: design spec

An iOS app that **teaches** Shengji (升级, "Level Up", also called **Tractor** / 拖拉机 tuōlājī)
and lets you **practise against bots**. The teaching side is built on learning-science
principles (see §Learning design). This document is the contract every part of the code follows.

## Repository layout

```
ShengjiCore/                      Swift package: all game logic + learning logic (no UI). Tested on Linux & macOS.
  Sources/ShengjiCore/Engine/     Card, Trump, Combination (done) · Rules, Scoring, Round, Game
  Sources/ShengjiCore/Bots/       Bot AI (also powers hints)
  Sources/ShengjiCore/Learning/   SpacedRepetition, Progress, Drills, Curriculum
  Tests/ShengjiCoreTests/
Shengji/                          iOS app (SwiftUI). Compiled only by Xcode.
  Shared/                         Theme, CardView, CardRow, TrumpBadge, RichText (done)
  Game/                           Play-vs-bots table
  Learn/                          Lessons, practice/review, rules reference, progress
  App/                            App entry, tabs, persistence stores
  Assets.xcassets
Shengji.xcodeproj                 Hand-written; app target uses a file-system-synchronized group for Shengji/
                                  and depends on the local package ShengjiCore.
.github/workflows/ci.yml          Linux `swift test` + macOS iOS build (+ simulator screenshots)
```

Conventions
- Swift 5 language mode (tools 5.9), iOS 17+, SwiftUI + Observation (`@Observable`). No third-party dependencies.
- Core is pure value types (`struct`/`enum`), `Codable`, `Sendable`; deterministic given a seeded RNG (`SeededGenerator`).
- Public API in the stub files is the contract. Don't change a public signature without updating every caller.
- Never use `fatalError` in shipped code paths (stubs aside). Never force-unwrap anything derived from user input.
- Learner-facing strings: short, plain English, second person ("You must follow suit…"). Chinese terms appear with pinyin.

## Rules implemented (the variant we teach)

Four players, fixed partnerships sitting opposite. Seat 0 = you (South), 1 = East, 2 = North (your partner),
3 = West. Play order 0→1→2→3 (counter-clockwise). Team = seat % 2. Two decks with jokers (108 cards).

**Levels.** Each team has a level, starting at 2, climbing 2,3,…,10,J,Q,K,A. The trump rank of a round is
the *dealer's team's* level. Gains are capped at the target (default A): you must win a round as declarers
while at A to win the game.

**Trumps (主牌).** All jokers, all cards of the trump rank, and all cards of the trump suit. Order, high→low:
big joker > small joker > trump-rank card in trump suit > trump-rank cards in other suits (equal to each other)
> A, K, Q… of the trump suit (skipping the rank). In a **no-trump** round (joker-pair declaration, or
kitty flip of a joker) only jokers and rank cards are trump; rank cards are all equal. Plain suits run A high
down to 2, skipping the trump rank. Strength values: see `Trump.strength` (consecutive = adjacent for tractors).

**Points.** 5 = 5 points, 10 and K = 10 points. 200 in total. Only the defenders' captured points matter.

**Dealing & declaring (亮主).** Cards are dealt one at a time (first to `dealer ?? seat 0`), 25 each; 8 form the
kitty (底牌). While cards arrive, anyone may reveal trump-rank cards to set the trump suit:
strength 1 = one rank card of a suit, 2 = a pair of rank cards of one suit, 3 = pair of small jokers (no trump),
4 = pair of big jokers (no trump). A declaration must be strictly stronger than the current one. A player who
holds the current declaration may only reinforce it (same suit, single → pair). The window stays open briefly after
the last card. First round only: the winning declarer becomes dealer (庄家). If nobody declares: in the first round
seat 0 deals; the kitty is flipped card by card and the first trump-rank card fixes the suit (a joker → no trump);
if none appears, the suit of the highest-ranked kitty card (first one if tied) is trump. `trumpFromKitty` records it.

**Kitty (扣底).** The dealer takes the 8 kitty cards and buries any 8 cards face down. Burying point cards is legal
but risky (see scoring).

**Combinations.** Single · pair (two identical cards; 2♠2♣ is not a pair) · tractor (two or more pairs of adjacent
strength in one suit group: 7799 is a tractor when 8 is the trump rank; A♥A♥-2♠2♠ and 2♠2♠-2♥2♥ are trump tractors
when ♥ is trump and 2 is the rank; small-joker pair + big-joker pair is a tractor).

**Leading.** The leader plays any one combination, or a **throw** (甩牌): several combinations of one suit at once.
A throw succeeds only if no other player can beat any of its components with the same shape in that suit
(higher single / higher pair / higher tractor of that length). If it fails, the leader must play only the
lowest-ranked beatable component (smallest shape first, then lowest strength) and takes the rest back; no extra
point penalty. Bots only throw when the unseen cards make it guaranteed.

**Following (跟牌).** Play the same number of cards. If you hold enough cards of the led group you must play only
that group, and match structure: algorithm `Rules.followRequirement`:
walk the lead's components largest first over your led-group cards: a tractor(k) requires a k-tractor if you have a
run ≥ k (remove it), otherwise as many pairs as you have up to k (remove them); a pair requires a pair if you have one
(remove it); singles require nothing. The play must contain the required tractors (disjoint) and at least the
required total pairs. If you hold fewer led-group cards than needed, play them all and fill with anything.

**Winning a trick.** A play can only compete if it is entirely the led group or entirely trump, and has the same
structure as the lead (for a throw: the same multiset of shapes). Compare the key component (the lead's largest
component's counterpart; for singles just the card): trump beats non-trump, otherwise higher strength wins; ties go to
the earlier play. The winner leads next.

**Scoring a round.** Defenders' points = captured points + kitty bonus. If the defenders win the last trick, the
kitty's points count × `2 × (cards in the largest component of the last trick's lead)` (single ×2, pair ×4,
tractor ×8…). Then `Scoring.outcome`:

| Defenders | Result |
|---|---|
| 0 | declarers +3 levels |
| 5–35 | declarers +2 |
| 40–75 | declarers +1 |
| 80–115 | defenders take over the deal (+0) |
| 120–155 | take over +1 |
| 160–195 | take over +2 |
| 200+ | take over +3 (+1 more per extra 40) |

Next dealer: declarers hold → the dealer's partner; defenders take over → the player after the dealer.
Game won when the declaring team holds while at the target rank.

### Bigger tables (6 or 8 players)

Offline and online games can also seat 6 players with 3 decks or 8 with 4 (`TableSize`; the lessons and drills
teach the classic game only). Everything above holds, with these changes:

- **Seats and teams.** Teams alternate round the table (team = seat % 2), so you have two or three partners. Play
  still goes 0 → 1 → … counter-clockwise; seat names are compass points from South (6: South, Southeast,
  Northeast, North, Northwest, Southwest; 8: the eight points). Next dealer when the declarers hold: two seats on
  (the dealer's next partner); when the defenders take over: the next seat, as before.
- **Cards.** 54 × decks cards (162 or 216), 26 each, kitty 6 (6 players) or 8 (8 players). `Card.id` goes up to 215.
- **Sets.** A face can appear 3 or 4 times: three identical cards are a triple (`ComboShape.set(3)`), four are four of
  a kind (`.set(4)`), and runs of them are tractors (`.setTractor(width:length:)`). Decomposition takes the widest
  sets first (777 888 99 = tractor of triples + pair).
- **Following.** The same walk over the lead's components, largest first: a set of width w asks for the widest set
  you hold up to w (a triple led: your triple, else a pair); a tractor asks for the same tractor if you hold one,
  otherwise, for each of its steps, the widest set you hold up to its width (a tractor of pairs: as many pairs as you
  have, four identical cards counting as two pairs). The play must contain every owed set disjointly.
- **Winning and throws.** Only the lead's exact shapes compete (a triple beats only a lower triple, or a trump triple);
  a throw component is beaten by a higher one of the same shape held by any other player.
- **Declaring.** More cards beat fewer: strength(count, kind) = 1 for one rank card, else 3·count − 4 + kind (rank 0,
  small jokers 1, big jokers 2), so 2 rank = 2, small-joker pair 3, big-joker pair 4, three rank cards 5, three small
  jokers 6, … four big jokers 10. A holder may strengthen their own declaration with more of the same card.
  Online bidding ends when everyone else has passed since the last declaration (or all pass).
- **Scoring.** 100 points per deck; take over at 40 per deck, a level per 20 per deck (3 decks: 0 → +3, 5–55 → +2,
  60–115 → +1, 120–175 take over, then +1 per 60). The kitty multiplier is unchanged (a triple lead ×6).

The general rules live in `Engine/RulesSets.swift` and only run when a lead, hand or play holds three or more copies
of a face; with two decks the classic code paths run unchanged (a test checks that both agree there). Bots use the
same strategy with partners and opponents for any table, plus sets as sure winners.

## Engine API notes

- `Round` is a value-type state machine (`dealing → burying → playing → finished`). The UI keeps one `Round` and calls
  its mutating methods; illegal input throws `RoundError` whose `.explanation` is shown by the coach.
- When the 4th card of a trick lands, `Round.play` scores it immediately: `tricks.last` is the finished trick,
  `currentTrick` is empty and `leader` is the winner. UIs show `tricks.last` for a moment before the next lead.
- `Rules.winningIndex` works on partial tricks (bots use it to see who is winning right now).
- `Bot` never looks at other hands: every decision is made from a `SeatView` alone (viewer = seat 0), so the same
  bot plays offline and gives hints online. `BotKnowledge` = own hand, played cards, own buried kitty, and voids
  shown so far. View methods: `decide(view:)` (play, or bury for the dealer), `cardsToBury(view:)`,
  `declaration(view:available:)` (offline deal or online bidding; nil = pass) and `bid(view:)` (bidding hint texts).
  The `Round` methods (`decide(in:)`, `cardsToBury(in:)`, `declaration(in:)`) build `round.seatView(for: seat)`
  and call them.
- Hints = `Bot(seat: 0).decide(in:)` offline, `Bot(seat: 0).decide(view:)` online, with its `reason` and `concept`
  strings. Texts name the other players from the viewer's side (East on the right, West on the left).

## Bot strategy (standard level)

Declaring: count would-be trumps (suit cards + rank cards + jokers) as a fraction of cards received; declare when
strong enough (threshold falls as the deal progresses), never override partner, reinforce own single with a pair.
Burying: never bury trumps/aces/pairs if avoidable; prefer voiding short plain suits; avoid point cards.
Leading: (1) guaranteed throws of sure winners in a plain suit nobody has shown out of; (2) sure-winning tractors /
pairs / aces in plain suits; (3) declarers with long trumps draw trumps with top pairs or low singles; (4) lead a suit
partner is void in; (5) otherwise a low non-point card from a short plain suit (keep pairs intact); never lead point
cards unless they're sure winners. Following: partner winning *safely* (they're last, or their card is the highest
unseen and nobody after has shown out) → feed points; opponent winning → win cheaply if it's worth it (points on the
table, last to play, or a sure winner), ruff when void and points are at stake; otherwise dump the lowest non-point
cards without breaking pairs. Every decision carries a one-sentence reason and a concept tag.

## Learning design (why the app teaches the way it does)

| Principle | Where it shows up |
|---|---|
| **Retrieval practice** (testing effect) | Every lesson ends with a quiz; daily Review is all recall, never re-reading. |
| **Spaced repetition** | Items (skills + facts) are scheduled by `Scheduler` (1 min → 10 min → 1 day → ×ease). Review tab shows what's due. |
| **Interleaving** | Review mixes item types; lesson quizzes include 1–2 items from earlier lessons. |
| **Generation / prediction** | Lessons ask "your turn: who wins?" *before* explaining (`LessonPage.predict`). In play, optional "predict the winner" prompts. |
| **Immediate, elaborative feedback** | Every answer reveals the rule behind it (`Question.explanation`), right or wrong. |
| **Retest errors** | Missed items come back later in the same session (`PracticeSession.retryGap`) and are rescheduled sooner. |
| **Variable practice** | Skills are generators, so each review is a new situation (different trump, suit, rank). |
| **Worked examples → fading** | Lessons show worked examples first; at the table Coach level fades Guided → Coached → Solo. |
| **Dual coding** | Every rule is shown with real cards drawn on screen alongside words. |
| **Chunking / small steps** | Lessons are 2–4 minutes, one idea each; the next unlocks after a passing quiz (mastery gating, 80%). |
| **Desirable difficulty** | Question difficulty rises with successful reps (`LearnerProgress.difficulty`). |
| **Learning from real mistakes** | Illegal plays at the table make the related skill due now (`noteGameMistake`). |
| **Motivation & metacognition** | Streak, due counts, per-skill mastery bars so you can see what you know and don't. |

Curriculum (lesson → skills/facts it unlocks):
1. The big picture: teams, levels, goal, 80-point line. (facts: teams, goal, threshold)
2. Cards & points: 108 cards, 5/10/K. (pointValue, countPoints)
3. What's trump: rank, suit, jokers. (isTrump)
4. Trump order: jokers > rank-in-suit > other rank cards > suit A…  (trumpOrder)
5. Following suit & winning tricks with singles: follow, ruff, discard. (cardBeats)
6. Pairs (对子): what is/isn't a pair; following a pair. (isPair, legalFollow)
7. Tractors (拖拉机): consecutive pairs, skipping the rank, trump tractors. (isTractor)
8. Who wins the trick: full tricks with pairs/tractors/ruffs. (trickWinner)
9. Dealing, declaring & the kitty: declaring strength, burying. (facts)
10. Scoring & levelling up: the table, kitty multiplier. (levelOutcome, kittyBonus)
11. Throws (甩牌): when they succeed and fail. (facts)
12. Strategy basics: feed partner points, count cards, void a suit, don't lead points. (bestPlay)

## App UI

Tabs: **Learn** (lesson path with lock/complete states + a "Due for review" banner), **Review** (start daily
practice; shows due count, streak, next due time, skill mastery list), **Play** (new game / continue, coach level,
game settings), **Rules** (searchable quick reference + glossary 中文/pinyin).

Play table (portrait iPhone first, works on iPad): top bar (levels for Us/Them, trump badge, dealer, defenders' points,
menu); seats around a felt table (Partner top, West left, East right) showing card counts and each seat's
current play near the centre; a coach banner (explanations, hint reason, illegal-move explanation); action bar
(Hint, Play/Bury/Declare buttons); your hand at the bottom in up to two overlapping rows, sorted by
`Trump.sortKey`, tap to raise/select. In Guided coach level: trumps get the gold edge and cards that can't be legal
are dimmed. Dealing animates card by card with live declare buttons. After each trick: winner highlighted for ~1s
(tap to skip) with a one-line explanation. End of round: results sheet (points, kitty reveal & multiplier, level
change explained in words, next dealer). Bots act with short delays so you can follow.

## Demo / screenshot scenes

Launching with `-ScreenshotScene <name>` (read with `UserDefaults.standard.string(forKey: "ScreenshotScene")`)
opens straight into a deterministic scene so CI can capture simulator screenshots:
`learn` (lesson path), `lesson` (lesson 4, a cards page), `predict` (a lesson predict page, answered),
`review` (review tab), `quiz` (a practice question answered, showing feedback), `game` (table mid-trick, seed 7,
Guided coach level, a hint shown), `dealing` (mid-deal with declare buttons), `result` (round result sheet),
`rules` (rules reference), `coach` (the `game` table with the coach sheet open on a canned chat, no network),
`achievements` (the achievements screen with sample progress), `online` (Play online: sample clubs and games from
the in-memory demo server), `onlineGame` (an online table mid-play, a seeded round's seat view, demo server),
`game6` and `game8` (the `game` table with 6 players and 3 decks, and with 8 and 4).
Without the argument the app starts normally. Scene setup must never touch saved progress (or the network).

## Work ownership (for parallel development)

- Engine: `Engine/Rules.swift`, `Scoring.swift`, `Round.swift`, `Game.swift` + tests.
- Learning core: `Learning/SpacedRepetition.swift`, `Learning/Progress.swift` + tests.
- Curriculum content: `Learning/Curriculum.swift` + tests.
- Drills: `Learning/Drills.swift` + tests.
- Bots: `Bots/` + tests.
- Project: `Shengji.xcodeproj`, `Shengji/Assets.xcassets`, `.github/`, `README.md`.
- Game UI: `Shengji/Game/`.
- Learn UI + app shell: `Shengji/Learn/`, `Shengji/App/`.
- Shared UI (`Shengji/Shared/`): additive changes only.

## App integration contract

- `LearningStore` (`Shengji/App/LearningStore.swift`, done): `@MainActor @Observable`, persisted `LearnerProgress`.
  Shared through the environment: `.environment(store)` / `@Environment(LearningStore.self) private var learning`.
  Game UI uses `coachLevel`, `noteGameMistake(_:)`, `record(itemID:correct:seconds:updateSchedule:)` (in-game
  predictions use `updateSchedule: false`), `recordRoundPlayed()`, `recordGameFinished(won:)`.
- `DemoScene` and `AppTab` (`Shengji/App/DemoScene.swift`, done).
- Play tab root: `PlayHomeView(demoScene: DemoScene? = nil)` in `Shengji/Game/` (game UI owns it). For `.game`,
  `.dealing` and `.result` it opens the table directly in that state, without touching any saved game.
- App entry `ShengjiApp` (`@main`) and `RootView` in `Shengji/App/` (learn UI owns them): create
  `LearningStore(ephemeral: DemoScene.current != nil)`, inject it, TabView with Learn (`LessonPathView`),
  Review (`ReviewView`), Play (`PlayHomeView`), Rules (`RulesView`); initial tab `DemoScene.current?.tab ?? .learn`.
- Saved game: game UI persists the in-progress game as JSON in Application Support (`savedGame.json`).
- `AchievementStore` (`Shengji/Achievements/`): `@MainActor @Observable`, persisted `AchievementProgress` (JSON in
  UserDefaults, `achievements.v1`; ephemeral in demo scenes), injected next to `LearningStore` by `ShengjiApp`
  (`@Environment(AchievementStore.self)`). Journey counts follow `LearningStore.onProgressChange`; the table reports
  moves through `GameController.onMoves` / `onGameProgress` (`connectAchievements`) and shows the store's toasts
  (setting `play.moveCelebrations`, held during "who wins?" prompts and while a sheet covers the table). While you
  guess who won a round's last trick, the top bar keeps showing the levels from before the round.
- Online client (`Shengji/Online/`): `OnlineSession` (`@MainActor @Observable`, created by `ShengjiApp`, injected with
  `.environment(online)`; the demo server in screenshot scenes) holds the account, clubs and games and talks to the
  server through `OnlineAPI` (SwiftUI-free, URLSession transport; session token in the Keychain). `OnlineGameModel`
  runs one table from the server's `SeatView` (live updates over a WebSocket, polling while it is down) and
  `OnlineTableView` draws it. Push: `ShengjiAppDelegate` (`@UIApplicationDelegateAdaptor`) forwards the device token
  and notification taps to `OnlinePushCenter`; a tap opens the game (Play tab, online, table).
- Coach client (`Shengji/Coach/`): `CoachClient` (SSE over `URLSession.bytes`, device id in UserDefaults
  `coach.deviceID`), `CoachConversation` (SwiftUI-free; keeps requests within the proxy's limits) and `CoachSheet`.
  Entry points: the table's coach button and the hint banner's "Why?", "Ask the coach" on lesson pages, "Ask why"
  after a practice answer. Demo scenes use an offline conversation and never touch the network.

## Coach (Claude-powered tutor)

- Network: the app never holds an Anthropic key. It calls the Cloudflare Worker in `proxy/`
  (`POST https://shengji-coach.ellcrane.workers.dev/coach`), which pins `claude-haiku-5-5`, restricts the topic,
  rate-limits per device and IP, and streams SSE events: `{"type":"text","text":...}`,
  `{"type":"done","stopReason":...}`, `{"type":"error","code":...,"message":...}`. Request:
  `{"deviceId": "<random install id>", "turns": [{"role":"user","text":"...","context":"<table state>"}, {"role":"assistant","text":"..."}, ...]}`
  (alternating, starting and ending with user; user turns carry the table state they were asked with; limits in `proxy/src/protocol.ts`).
- Table state given to the coach: only what the learner can see (phase, trump, levels, dealer/declarers, own hand,
  current and previous trick, points, cards played so far by suit, shown voids, the current hint, last illegal attempt).
- Hint ladder (Guided/Coached): step 1 `BotDecision.nudge` (what to notice), step 2 `principle`, step 3 highlight
  `cards` + `reason`; every step offers "Why?" which asks the coach with full context.
- Suggested questions: tap-to-ask chips chosen from the phase and situation (your turn to lead/follow, after an
  illegal attempt, dealing, burying, after a trick, after a round, inside a lesson), plus follow-ups under each answer
  ("Why?", "Show an example", "Just tell me"). Typing is optional.

## Online multiplayer (planned; decisions made with the user)

Small private groups (6 to 10 friends), tables of 4, 6 or 8 (bots fill empty seats), asynchronous turn-based play with push notifications, live updates when
several players are in the app. Offline learning, practice and bot games stay as they are.

- Server: a separate Cloudflare Worker in `server/` (free plan). TypeScript port of the engine (decision: no
  container). Each game is a Durable Object (authoritative state, ordered actions, WebSocket live updates);
  a single Hub Durable Object (SQLite) holds users, linked sign-in identities, sessions, devices, clubs and the
  games index.
- Rules parity: the Swift engine generates JSON test vectors (`ShengjiVectors` executable target, output in
  `server/test/vectors/`); the TypeScript engine must reproduce every one exactly (validity, violations and their
  explanation text, trick winners, throws, scoring, game progression). The bots have the same check: the server's
  TypeScript port of the bots (`server/src/bots`, both levels, choices without the texts) must choose exactly the
  cards the Swift bots choose at every decision of the generated rounds (`bots.json`), bidding included.
  CI regenerates the vectors and fails if they drift from the Swift engine or bots.
- Card wire format: `Card.id` (face index + copy × 54: 0...107 with 2 decks, up to 215 with 4). Seats 0...3 as
  offline (0...5 or 0...7 at a table of 6 or 8); each player sees the table rotated so they are "You".
- Declaring online is turn-based: all 25 cards are dealt at once, then from the first bidder (the dealer, or the
  game creator's seat in round 1) each player in turn declares (same strength rules as offline) or passes.
  Bidding ends when the three other players have passed since the last declaration, or when all four pass with no
  declaration (then the kitty flip rule sets trump). Round 1: the winning declarer deals.
- Privacy: a player's view never contains other hands, the undealt deck, or the kitty (unless they are the dealer
  holding or having buried it, or the round is finished).
- Accounts are provider-agnostic: internal user ids with linked identities. Sign in with Apple now (identity token
  verified against Apple's JWKS, audience = bundle id); Google sign-in later for an Android app.
- Push is pluggable: APNs now (token auth with an APNs .p8 key: `APNS_KEY_P8`, `APNS_KEY_ID`, team
  `APPLE_TEAM_ID`; sandbox for debug builds, production for TestFlight/App Store), FCM later.
- Client: the online table renders a per-seat view from the server. Bots, hints, the coach context and move
  detection work from the same "seat view" model offline and online.
