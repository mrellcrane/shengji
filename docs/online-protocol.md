# Online protocol (v1)

The contract between the iOS app and the online server (`server/`, Cloudflare Worker `shengji-online`,
`https://shengji-online.ellcrane.workers.dev`). JSON over HTTPS, plus one WebSocket per open game.
All bodies are JSON (`content-type: application/json`). Errors are
`{"error": "<code>", "message": "<learner-facing sentence>"}` with an HTTP status.

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
- **Auth**: every endpoint except `/v1/auth/*` and `/health` needs `Authorization: Bearer <session token>`.

## Auth

`POST /v1/auth/apple` `{"identityToken": "<JWT from Sign in with Apple>", "displayName": "Mei"?}`
→ `200 {"token": "<opaque session token>", "user": User}`.
The server verifies the JWT against Apple's JWKS (`https://appleid.apple.com/auth/keys`): RS256 signature, `iss` =
`https://appleid.apple.com`, `aud` = `com.mrellcrane.shengji`, not expired. Identity key `apple:<sub>`. A new user is
created on first sign-in (display name from the request, else "Player 1234"). Sessions last 180 days.

`POST /v1/auth/dev` `{"secret": "...", "name": "Test A"}` → same response. Enabled only when the Worker has a
`DEV_AUTH_SECRET` secret (the deploy workflow sets a random one per deploy for its own smoke tests).

`User` = `{"id": "u_...", "displayName": "Mei"}`.

## Me and devices

- `GET /v1/me` → `{"user": User, "clubs": [Club]}`
- `PATCH /v1/me` `{"displayName": "Mei"}` (1 to 24 characters) → `{"user": User}`
- `POST /v1/devices` `{"platform": "ios", "token": "<hex APNs token>", "environment": "sandbox" | "production"}` → `204`
- `DELETE /v1/devices/<token>` → `204`

Push may be disabled on the server (no APNs key yet); devices are still stored.

## Clubs (your group of friends)

`Club` = `{"id": "c_...", "name": "Friday Tractor", "inviteCode": "ABCD-EFGH", "members": [User]}`.

- `POST /v1/clubs` `{"name": "..."}` → `{"club": Club}` (creator joins)
- `POST /v1/clubs/join` `{"inviteCode": "ABCD-EFGH"}` → `{"club": Club}` (case- and dash-insensitive)
- `GET /v1/clubs/<id>` → `{"club": Club, "games": [GameSummary]}` (members only)
- `POST /v1/clubs/<id>/leave` → `204`

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
 "lastEvent": "West played K♠ K♠"}
```

- `POST /v1/games` `{"clubId": "...", "seats": [Seat x4], "targetRank": 5 | 10 | 14}` where
  `Seat` = `{"userId": "u_..."}` or `{"bot": "standard" | "beginner"}`, in absolute seat order (teams 0+2 and 1+3).
  The creator must hold a seat; every human must be a club member. → `{"game": GameSummary}` (from the creator's view).
  The first round deals immediately; bidding starts at the creator's seat.
- `GET /v1/games` → `{"games": [GameSummary]}` (the caller's active games first, then up to 20 finished)
- `GET /v1/games/<id>` → `{"game": GameSummary, "view": SeatView, "version": n}`
- `POST /v1/games/<id>/actions` `{"version": n, "action": Action}` →
  `200 {"game": GameSummary, "view": SeatView, "version": n, "outcome": Outcome?}`,
  `409 {"error": "stale", "game", "view", "version"}` when `version` is old (refresh and retry),
  `400 {"error": "illegal", "message": "<the engine's explanation, e.g. You must follow suit...>"}`,
  `403 {"error": "not_your_turn"}`.
  `Action` = `{"type": "bid", "declaration": Declaration}` | `{"type": "pass"}` | `{"type": "bury", "cards": [ids]}` |
  `{"type": "play", "cards": [ids]}`.
  `Outcome` = `{"type": "throwFailed", "forced": [ids], "blocker": seat}` (viewer-relative) when a throw failed.
  After every human action the server runs bot turns until a human must act. When a round ends the server records
  it and immediately deals the next round (the finished round's summary is in `view.lastRoundSummary`).
- `GET /v1/games/<id>/live?token=<session token>` → WebSocket. The server sends
  `{"type": "update", "game": GameSummary, "view": SeatView, "version": n}` after every change (and once on connect).
- `POST /v1/games/<id>/nudge` → `204` (reminds the player whose turn it is; at most once per 10 minutes per game).
- `DELETE /v1/games/<id>` → `204` (creator only; ends the game for everyone).

## Push notifications (when enabled)

Alert pushes, collapsed per game (`apns-collapse-id` = game id), badge = number of games where it is your turn:
- your turn: title "Your turn", body e.g. "Mei led K♠ K♠ in Friday Tractor."
- round over: "Round 3: your team took over the deal."
- game over, nudges.
Payload includes `{"gameId": "g_..."}` so tapping opens the game.

## Health

`GET /health` → `{"ok": true, "version": "<git sha>", "push": true | false}`
