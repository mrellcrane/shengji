# Online protocol (v1)

The contract between the iOS app and the online server (`server/`, Cloudflare Worker `shengji-online`,
`https://shengji-online.ellcrane.workers.dev`). JSON over HTTPS, plus one WebSocket per open game.
All bodies are JSON (`content-type: application/json`). Errors are
`{"error": "<code>", "message": "<learner-facing sentence>"}` with an HTTP status (all codes: see Errors and limits).

## Conventions

- **Cards** are integers 0...107 (`Card.id` = face index + copy × 54; face index = suit × 13 + (rank − 2), small
  joker 52, big joker 53; suits: spades 0, hearts 1, clubs 2, diamonds 3; ranks 2...14 with A = 14).
- **Seats in views are viewer-relative**: the viewer is always seat 0, seat 1 their right (next to play),
  2 their partner, 3 their left; team 0 is the viewer's team. Actions never name seats.
- **SeatView** JSON is exactly the Codable form of Swift `SeatView` (`ShengjiCore/Sources/ShengjiCore/Engine/SeatView.swift`):
  optionals may be omitted or `null`; `Trump` is `{"rank": 2, "suit": 1}`; `Declaration` is
  `{"player", "cards", "suit"?, "strength"}`; `Play` `{"player", "cards"}`; `TrickRecord` `{"plays", "winner", "points"}`;
  `RoundResult` and `RoundSummary` mirror their Swift fields (with `outcome` = `{"declarersHold", "levels", "summary"}`).
  The server must never put a hidden card in a view (other hands, the undealt deck, a kitty the viewer may not see).
  The server writes absent optionals as `null` (Swift decodes both). `hand` is in deal order (not sorted).
  `lastRoundSummary.explanation` is written from the viewer's side ("Your team", "East and West", "Partner deals
  next"), exactly as Swift's `RoundSummary.rotated(by:target:)`. While bidding, `phase` is `"bidding"`, `turn` is
  `null` and `bidding.turn` says who bids; `bidding.available` is non-empty only on the viewer's own turn.
- **Versions**: each game has a `version` that grows with every change (each move, including every bot move,
  each new deal, and a player's new display name). Two messages with the same `version` hold the same game, so
  keeping only newer versions is safe. Send the `version` of the newest view you have; the server answers
  `409 stale` otherwise.
- **Auth**: every endpoint except `/v1/auth/*` and `/health` needs `Authorization: Bearer <session token>`.

## Auth

`POST /v1/auth/apple` `{"identityToken": "<JWT from Sign in with Apple>", "displayName": "Mei"?}`
→ `200 {"token": "<opaque session token>", "user": User}`.
The server verifies the JWT against Apple's JWKS (`https://appleid.apple.com/auth/keys`): RS256 signature, `iss` =
`https://appleid.apple.com`, `aud` = `com.mrellcrane.shengji`, not expired. Identity key `apple:<sub>`. A new user is
created on first sign-in (display name from the request, else "Player 1234"). Sessions last 180 days.
A `displayName` longer than 24 characters is shortened, and one that breaks the other name rules (see
`PATCH /v1/me`) is ignored. For an existing user it only replaces a default "Player 1234" name (a name chosen
with `PATCH /v1/me` is kept). A token that fails the checks is `401 invalid_token`; if Apple's keys cannot be
fetched, `503 unavailable` (try again).

`POST /v1/auth/dev` `{"secret": "...", "name": "Test A"}` → same response. Enabled only when the Worker has a
`DEV_AUTH_SECRET` secret (the deploy workflow sets a random one per deploy for its own smoke tests).
Otherwise it answers `404` (whatever the method or body). The same name always signs in as the same (dev) user.

`User` = `{"id": "u_...", "displayName": "Mei"}`.

## Me and devices

- `GET /v1/me` → `{"user": User, "clubs": [Club]}`
- `PATCH /v1/me` `{"displayName": "Mei"}` (1 to 24 characters) → `{"user": User}`
  (spaces are trimmed and runs of spaces collapsed; control and invisible formatting characters are refused;
  emoji are fine). The new name also shows in the player's active games. A name needs at least one visible
  character, and text that is not valid Unicode (a lone UTF-16 surrogate, which JSON would carry as `"\ud800"`
  and `JSONDecoder` rejects) is refused; the same rules apply to club names and dev sign-in names.
- `POST /v1/devices` `{"platform": "ios", "token": "<hex APNs token>", "environment": "sandbox" | "production"}` → `204`
  (a token registered again moves to the caller; at most 10 devices per user, the oldest are dropped)
- `DELETE /v1/devices/<token>` → `204` (also when it was not registered)

Push may be disabled on the server (no APNs key yet); devices are still stored. The app reads `push` from
`GET /health` and, while it is `false`, neither promises nor offers notifications or nudges (a nudge would reach nobody).

## Clubs (your group of friends)

`Club` = `{"id": "c_...", "name": "Friday Tractor", "inviteCode": "ABCD-EFGH", "members": [User]}`.

- `POST /v1/clubs` `{"name": "..."}` → `{"club": Club}` (creator joins; names are 1 to 40 characters)
- `POST /v1/clubs/join` `{"inviteCode": "ABCD-EFGH"}` → `{"club": Club}` (case- and dash-insensitive; spaces are
  ignored too; joining a club you are in is fine; an unknown code is `404`)
- `GET /v1/clubs/<id>` → `{"club": Club, "games": [GameSummary]}` (members only; `404` for anyone else).
  `games` holds the club's games, at most 50 (your-turn first, then active, then finished; newest first). For a
  game you are not seated in, the summary is seen from absolute seat 0, nobody is "You", and `yourTurn` is `false`.
- `POST /v1/clubs/<id>/leave` → `204` (when the last member leaves, the club is deleted; its games go on)

Members are listed in the order they joined. A user can be in 20 clubs; a club holds 50 members.
Invite codes use the letters and digits `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no I, L, O, 0 or 1).

## Games

`GameSummary` =
```
{"id": "g_...", "clubId": "c_...", "createdAt": iso, "updatedAt": iso, "status": "active" | "finished",
 "players": [{"name": "Mei", "isBot": false, "userID": "u_..."} x4],   // viewer-relative, index 0 = you
 "teamLevels": [rank, rank], "targetRank": 14, "roundNumber": 3,
 "phase": "bidding" | "burying" | "playing" | "finished",
 "turn": seat | null,            // viewer-relative seat that must act (bid, bury or play)
 "yourTurn": true,
 "winnerTeam": 0 | 1 | null,     // viewer-relative
 "lastEvent": "West played K♠ K♠",
 "startedByYou": false}          // you started this game (only you can end it)
```

`lastEvent` is one line about the latest move, naming players by display name and the viewer as "You":
"Mei started the game", "Lin declared ♥ (pair of 2♥)", "You passed", "Sam buried the kitty", "Mei led K♠ K♠",
"Tiger Bot played 3♣", "You tried a throw that failed and led 9♠", "Round 3: your team took over the deal",
"Round 4: Mei and Lin kept the deal and went up 2 levels to 7", "Round 9: your team won the game".
When a round ends during a batch of bot moves, its line is kept over the bids that follow it.
Bots are named by absolute seat: "Panda Bot", "Tiger Bot", "Crane Bot", "Dragon Bot" (`userID` null).

- `POST /v1/games` `{"clubId": "...", "seats": [Seat x4], "targetRank": 5 | 10 | 14}` where
  `Seat` = `{"userId": "u_..."}` or `{"bot": "standard" | "beginner"}`, in absolute seat order (teams 0+2 and 1+3).
  The creator must hold a seat; every human must be a club member. → `{"game": GameSummary}` (from the creator's view).
  The first round deals immediately; bidding starts at the creator's seat.
  `targetRank` defaults to 14. Each person sits once. At most 30 active games per player: if anyone at the
  table already has 30, the answer is `409 too_many_games` (its `message` names who).
- `GET /v1/games` → `{"games": [GameSummary]}` (the caller's active games first, then up to 20 finished)
  (games where it is your turn come first; newest first within each group).
- `GET /v1/games/<id>` → `{"game": GameSummary, "view": SeatView, "version": n}`
  (seated players only: others get `403 not_seated`; a deleted game is `404`).
- `POST /v1/games/<id>/actions` `{"version": n, "action": Action}` →
  `200 {"game": GameSummary, "view": SeatView, "version": n, "outcome": Outcome?}`,
  `409 {"error": "stale", "game", "view", "version"}` when `version` is old (refresh and retry),
  `400 {"error": "illegal", "message": "<the engine's explanation, e.g. You must follow suit...>"}`,
  `403 {"error": "not_your_turn"}`.
  `Action` = `{"type": "bid", "declaration": Declaration}` | `{"type": "pass"}` | `{"type": "bury", "cards": [ids]}` |
  `{"type": "play", "cards": [ids]}`.
  `Outcome` = `{"type": "throwFailed", "forced": [ids], "blocker": seat}` (viewer-relative) when a throw failed.
  After every human action the server runs bot turns until a human must act. Bots play exactly like the app's bots of
  their level, each deciding from its own seat's view (bids from `view.bidding.available`). When a round ends the
  server records it and immediately deals the next round (the finished round's summary is in `view.lastRoundSummary`).
  Details: send a bid's declaration back as it appears in `view.bidding.available` (its `player` is 0, you; it may be
  left out; `suit` is left out or `null` for a joker pair). Cards are matched by id. The checks run in this order:
  `403 not_seated`, `409 stale`, `403 not_your_turn` (also when the game is over: "The game is over."), then the
  engine (`400 illegal`, with "You can't do that at this point in the round." for an action of the wrong phase).
  A malformed body is `400 bad_request`. Refused actions change nothing. `outcome` is only in the mover's own reply;
  others see the forced cards in the trick. When a team wins, the game's `status` and `phase` become `"finished"`,
  the last round stays on the table (its `result` and kitty visible to all), `view.gameWinnerTeam` and
  `game.winnerTeam` are set, and nobody can act any more.
- `GET /v1/games/<id>/live?token=<session token>` → WebSocket. The server sends
  `{"type": "update", "game": GameSummary, "view": SeatView, "version": n}` after every change (and once on connect).
  The session token may instead be sent as `Authorization: Bearer <token>`. Before upgrading, a bad session is `401`,
  someone not seated `403`, a deleted game `404`, and a plain (non-WebSocket) request `426`. The client never needs to
  send anything; a text message `ping` is answered with `pong` (keep-alive). When the game is deleted the server
  closes the socket with code `4004`. Each person keeps at most 4 live sockets per game: opening a fifth closes
  their oldest with code `4001` (usually one a phone left behind when its network dropped). A close from the
  client is answered at once (with its code, or `1000` when it sent none). After any other close, reconnect if you
  still need updates (the first message is the current state).
- `POST /v1/games/<id>/nudge` → `204` (reminds the player whose turn it is; at most once per 10 minutes per game).
  Too soon is `429 too_soon` with `retry-after` set to the seconds until the next nudge is allowed; when it is your
  own turn or the game is over, `400 cannot_nudge`.
- `DELETE /v1/games/<id>` → `204` (creator only, `startedByYou`; ends the game for everyone).
  Others get `403 forbidden`. The game disappears from every list, and open WebSockets close with `4004`.

## Push notifications (when enabled)

Alert pushes, collapsed per game (`apns-collapse-id` = game id), badge = number of games where it is your turn:
- your turn: title "Your turn", body e.g. "Mei led K♠ K♠ in Friday Tractor."
- round over: "Round 3: your team took over the deal."
- game over, nudges.
Payload includes `{"gameId": "g_..."}` so tapping opens the game.

Exactly: `{"aps": {"alert": {"title", "body"}, "badge": n, "sound": "default", "thread-id": "<game id>"},
"gameId": "<game id>"}`. Nobody is told about their own move, and each person gets at most one push per move:
- your turn: title "Your turn", body "<lastEvent as you see it> in <club>." (after a round ended:
  "Round 3: your team took over the deal. It's your turn in Friday Tractor.");
- round over (to the other people): title "<club>", body "Round 3: your team took over the deal.";
- game over: title "Game over", body "Your team won the game in Friday Tractor!" or
  "Mei and Lin won the game in Friday Tractor.";
- nudge: title "Your turn", body "Lin is waiting for you in Friday Tractor."
Devices that APNs reports as gone (410, `BadDeviceToken`, `Unregistered`, `DeviceTokenNotForTopic`) are forgotten.

## Health

`GET /health` → `{"ok": true, "version": "<git sha>", "push": true | false}`

## Errors and limits

| Status | `error` | When |
|---|---|---|
| 400 | `bad_request` | a field is missing, of the wrong type, or out of range |
| 400 | `bad_json` | the body is not JSON |
| 400 | `illegal` | the engine refused the move (`message` explains the rule) |
| 400 | `cannot_nudge` | nudging yourself, or a finished game |
| 401 | `unauthorized` | no session, an unknown or expired one (sign in again), or a wrong dev secret |
| 401 | `invalid_token` | the Sign in with Apple token did not verify |
| 403 | `not_your_turn` | someone else must act, or the game is over |
| 403 | `not_seated` | you are not playing in that game |
| 403 | `forbidden` | deleting a game you did not start |
| 404 | `not_found` | no such path, game, club (or not a member), or invite code |
| 405 | `method_not_allowed` | wrong HTTP method |
| 409 | `stale` | your `version` is not the latest (the body has the current game, view and version) |
| 409 | `club_full`, `too_many_clubs`, `too_many_games` | a limit below was reached |
| 413 | `too_large` | the body is over 16 KB |
| 426 | `upgrade_required` | the live address without a WebSocket upgrade |
| 429 | `rate_limited` | too many requests (`retry-after: 60`) |
| 429 | `too_soon` | a nudge within 10 minutes of the last one (`retry-after`: seconds until the next is allowed) |
| 500 | `internal` | a server bug (try again) |
| 503 | `unavailable` | Apple's sign-in keys could not be fetched (try again) |

Rate limits: 120 requests a minute per user, 300 a minute per IP address, and 20 sign-ins (per IP) or invite-code
tries (per user) a minute. Names: display names 1 to 24 characters, club names 1 to 40.
