import Foundation
import ShengjiCore

// The online server's wire models (docs/online-protocol.md). SwiftUI-free and Codable both ways, so the
// demo server can answer with the same JSON the real one sends. Decoding is forgiving where the protocol
// allows it: optionals may be omitted or null, and an unknown phase or status never fails a whole list.

/// `User` = `{"id": "u_...", "displayName": "Mei"}`.
struct OnlineUser: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var displayName: String

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

/// `Club` = `{"id": "c_...", "name": "Friday Tractor", "inviteCode": "ABCD-EFGH", "members": [User]}`.
struct OnlineClub: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var inviteCode: String
    var members: [OnlineUser]

    init(id: String, name: String, inviteCode: String, members: [OnlineUser]) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.members = members
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        inviteCode = try c.decodeIfPresent(String.self, forKey: .inviteCode) ?? ""
        members = try c.decodeIfPresent([OnlineUser].self, forKey: .members) ?? []
    }

    /// "Join my Shengji club with code ABCD-EFGH"
    var shareText: String { "Join my Shengji club with code \(inviteCode)" }
}

/// One line of the games list (`GameSummary`). Seats and teams are viewer-relative: index 0 is you.
struct OnlineGameSummary: Codable, Hashable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable {
        case active, finished
    }

    var id: String
    var clubId: String
    /// ISO 8601 strings as sent; see `createdDate` / `updatedDate`.
    var createdAt: String
    var updatedAt: String
    var status: Status
    /// Index 0 = you, 1 = your right, 2 = your partner, 3 = your left.
    var players: [SeatView.Player]
    /// [your team, the other team].
    var teamLevels: [Rank]
    var targetRank: Rank
    var roundNumber: Int
    /// nil when the server sent a phase this version doesn't know.
    var phase: SeatView.Phase?
    /// Viewer-relative seat that must act (bid, bury or play).
    var turn: Int?
    var yourTurn: Bool
    /// Viewer-relative winning team once the game is over.
    var winnerTeam: Int?
    /// e.g. "West played K♠ K♠".
    var lastEvent: String?
    /// You started this game, so you can end it (true when a server doesn't say: it then decides).
    var startedByYou: Bool

    init(id: String, clubId: String, createdAt: String, updatedAt: String, status: Status,
         players: [SeatView.Player], teamLevels: [Rank], targetRank: Rank, roundNumber: Int,
         phase: SeatView.Phase?, turn: Int?, yourTurn: Bool, winnerTeam: Int?, lastEvent: String?,
         startedByYou: Bool = true) {
        self.id = id
        self.clubId = clubId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.players = players
        self.teamLevels = teamLevels
        self.targetRank = targetRank
        self.roundNumber = roundNumber
        self.phase = phase
        self.turn = turn
        self.yourTurn = yourTurn
        self.winnerTeam = winnerTeam
        self.lastEvent = lastEvent
        self.startedByYou = startedByYou
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        clubId = try c.decodeIfPresent(String.self, forKey: .clubId) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        let rawStatus = try c.decodeIfPresent(String.self, forKey: .status)
        status = rawStatus.flatMap(Status.init(rawValue:)) ?? .active
        players = try c.decodeIfPresent([SeatView.Player].self, forKey: .players) ?? []
        teamLevels = try c.decodeIfPresent([Rank].self, forKey: .teamLevels) ?? []
        targetRank = try c.decodeIfPresent(Rank.self, forKey: .targetRank) ?? .ace
        roundNumber = try c.decodeIfPresent(Int.self, forKey: .roundNumber) ?? 1
        let rawPhase = try c.decodeIfPresent(String.self, forKey: .phase)
        phase = rawPhase.flatMap(SeatView.Phase.init(rawValue:))
        turn = try c.decodeIfPresent(Int.self, forKey: .turn)
        yourTurn = try c.decodeIfPresent(Bool.self, forKey: .yourTurn) ?? false
        winnerTeam = try c.decodeIfPresent(Int.self, forKey: .winnerTeam)
        lastEvent = try c.decodeIfPresent(String.self, forKey: .lastEvent)
        startedByYou = try c.decodeIfPresent(Bool.self, forKey: .startedByYou) ?? true
    }

    var isFinished: Bool { status == .finished }

    /// Your turn in a game that is still going.
    var isYourTurn: Bool { yourTurn && !isFinished }

    var createdDate: Date? { OnlineDates.parse(createdAt) }
    var updatedDate: Date? { OnlineDates.parse(updatedAt) }

    func player(_ seat: Int) -> SeatView.Player? {
        players.indices.contains(seat) ? players[seat] : nil
    }

    func level(of team: Int) -> Rank? {
        teamLevels.indices.contains(team) ? teamLevels[team] : nil
    }
}

/// A seat in `POST /v1/games`: `{"userId": "u_..."}` or `{"bot": "standard" | "beginner"}`.
enum OnlineSeatSpec: Codable, Hashable, Sendable {
    case user(id: String)
    case bot(OnlineBotLevel)

    private enum CodingKeys: String, CodingKey {
        case userId, bot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .userId) {
            self = .user(id: id)
        } else {
            self = .bot(try c.decode(OnlineBotLevel.self, forKey: .bot))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .user(id): try c.encode(id, forKey: .userId)
        case let .bot(level): try c.encode(level, forKey: .bot)
        }
    }
}

enum OnlineBotLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case standard, beginner

    var title: String {
        switch self {
        case .standard: return "Bot"
        case .beginner: return "Beginner bot"
        }
    }

    var bot: BotLevel {
        switch self {
        case .standard: return .standard
        case .beginner: return .beginner
        }
    }
}

/// What you do at the table. Actions never name seats (the server knows who you are).
enum OnlineAction: Codable, Hashable, Sendable {
    case bid(Declaration)
    case pass
    case bury([Card])
    case play([Card])

    private enum CodingKeys: String, CodingKey {
        case type, declaration, cards
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "bid": self = .bid(try c.decode(Declaration.self, forKey: .declaration))
        case "pass": self = .pass
        case "bury": self = .bury(try c.decode([Card].self, forKey: .cards))
        case "play": self = .play(try c.decode([Card].self, forKey: .cards))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown action \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bid(declaration):
            try c.encode("bid", forKey: .type)
            try c.encode(declaration, forKey: .declaration)
        case .pass:
            try c.encode("pass", forKey: .type)
        case let .bury(cards):
            try c.encode("bury", forKey: .type)
            try c.encode(cards, forKey: .cards)
        case let .play(cards):
            try c.encode("play", forKey: .type)
            try c.encode(cards, forKey: .cards)
        }
    }

    /// The cards this action puts down (for the coach's "last illegal attempt").
    var cards: [Card] {
        switch self {
        case let .bid(declaration): return declaration.cards
        case .pass: return []
        case let .bury(cards), let .play(cards): return cards
        }
    }
}

/// Something notable about an accepted action: `{"type": "throwFailed", "forced": [ids], "blocker": seat}`.
struct OnlineOutcome: Codable, Hashable, Sendable {
    var type: String
    var forced: [Card]?
    /// Viewer-relative seat that could beat part of the throw.
    var blocker: Int?

    init(type: String, forced: [Card]? = nil, blocker: Int? = nil) {
        self.type = type
        self.forced = forced
        self.blocker = blocker
    }

    static func throwFailed(forced: [Card], blocker: Int) -> OnlineOutcome {
        OnlineOutcome(type: "throwFailed", forced: forced, blocker: blocker)
    }

    var isThrowFailed: Bool { type == "throwFailed" }
}

/// A game as one seat sees it at one version: `{"game": GameSummary, "view": SeatView, "version": n}`.
struct OnlineGameState: Codable, Hashable, Sendable {
    var game: OnlineGameSummary
    var view: SeatView
    var version: Int

    init(game: OnlineGameSummary, view: SeatView, version: Int) {
        self.game = game
        self.view = view
        self.version = version
    }
}

/// `{"error": "<code>", "message": "<learner-facing sentence>"}` (a stale action also carries the state).
struct OnlineErrorBody: Codable, Hashable, Sendable {
    var error: String
    var message: String?

    init(error: String, message: String? = nil) {
        self.error = error
        self.message = message
    }
}

// MARK: - Request and response bodies

struct OnlineAppleSignInBody: Codable, Hashable, Sendable {
    var identityToken: String
    var displayName: String?
}

struct OnlineDevSignInBody: Codable, Hashable, Sendable {
    var secret: String
    var name: String
}

struct OnlineAuthResponse: Codable, Hashable, Sendable {
    var token: String
    var user: OnlineUser
}

struct OnlineMeResponse: Codable, Hashable, Sendable {
    var user: OnlineUser
    var clubs: [OnlineClub]

    init(user: OnlineUser, clubs: [OnlineClub]) {
        self.user = user
        self.clubs = clubs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decode(OnlineUser.self, forKey: .user)
        clubs = try c.decodeIfPresent([OnlineClub].self, forKey: .clubs) ?? []
    }
}

struct OnlineDisplayNameBody: Codable, Hashable, Sendable {
    var displayName: String
}

struct OnlineUserResponse: Codable, Hashable, Sendable {
    var user: OnlineUser
}

struct OnlineDeviceBody: Codable, Hashable, Sendable {
    var platform: String
    var token: String
    var environment: String
}

struct OnlineClubNameBody: Codable, Hashable, Sendable {
    var name: String
}

struct OnlineJoinClubBody: Codable, Hashable, Sendable {
    var inviteCode: String
}

struct OnlineClubResponse: Codable, Hashable, Sendable {
    var club: OnlineClub
}

struct OnlineClubDetailResponse: Codable, Hashable, Sendable {
    var club: OnlineClub
    var games: [OnlineGameSummary]

    init(club: OnlineClub, games: [OnlineGameSummary]) {
        self.club = club
        self.games = games
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        club = try c.decode(OnlineClub.self, forKey: .club)
        games = try c.decodeIfPresent([OnlineGameSummary].self, forKey: .games) ?? []
    }
}

struct OnlineGamesResponse: Codable, Hashable, Sendable {
    var games: [OnlineGameSummary]
}

struct OnlineNewGameBody: Codable, Hashable, Sendable {
    var clubId: String
    /// Absolute seat order, 4, 6 or 8 seats: teams alternate (seats 0 + 2 and 1 + 3 at a table of four).
    var seats: [OnlineSeatSpec]
    var targetRank: Rank
}

struct OnlineGameResponse: Codable, Hashable, Sendable {
    var game: OnlineGameSummary
}

struct OnlineActionBody: Codable, Hashable, Sendable {
    var version: Int
    var action: OnlineAction
}

/// `200 {"game", "view", "version", "outcome"?}` after an action.
struct OnlineActionResponse: Codable, Hashable, Sendable {
    var game: OnlineGameSummary
    var view: SeatView
    var version: Int
    var outcome: OnlineOutcome?

    var state: OnlineGameState { OnlineGameState(game: game, view: view, version: version) }
}

/// A WebSocket message: `{"type": "update", "game", "view", "version"}`. Other types are ignored.
struct OnlineLiveMessage: Codable, Hashable, Sendable {
    var type: String
    var game: OnlineGameSummary?
    var view: SeatView?
    var version: Int?

    var state: OnlineGameState? {
        guard type == "update", let game, let view, let version else { return nil }
        return OnlineGameState(game: game, view: view, version: version)
    }
}

/// `GET /health` → `{"ok": true, "version": "<git sha>", "push": true | false}`.
struct OnlineHealth: Codable, Hashable, Sendable {
    var ok: Bool
    var version: String?
    var push: Bool?
}

// MARK: - Helpers

/// Server timestamps are ISO 8601, with or without fractional seconds.
enum OnlineDates {
    static func parse(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// Invite codes are case- and dash-insensitive: "abcd efgh", "ABCDEFGH" and "abcd-efgh" are the same code.
enum OnlineInviteCode {
    /// Letters and digits only, upper-cased. A whole pasted invite ("Join my Shengji club with code
    /// ABCD-EFGH", copied from Messages) gives just its code.
    static func compact(_ text: String) -> String {
        let all = letters(text)
        guard all.count > 8, let code = text.range(of: shared, options: .regularExpression) else { return all }
        return letters(String(text[code]))
    }

    /// A code as `OnlineClub.shareText` writes it, on its own: four letters or digits, a dash, four more.
    private static let shared = "(?<![A-Za-z0-9])[A-Za-z0-9]{4}-[A-Za-z0-9]{4}(?![A-Za-z0-9])"

    private static func letters(_ text: String) -> String {
        String(text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    /// "ABCD-EFGH" for eight characters, otherwise the compact form.
    static func normalized(_ text: String) -> String {
        let code = compact(text)
        guard code.count == 8 else { return code }
        return String(code.prefix(4)) + "-" + String(code.suffix(4))
    }

    /// Long enough to send (codes are eight letters and digits).
    static func isPlausible(_ text: String) -> Bool {
        (6...16).contains(compact(text).count)
    }
}

/// Display names are 1 to 24 characters after trimming, counted the way the server counts them.
enum OnlineDisplayName {
    static let maxLength = 24
    static let clubNameMaxLength = 40

    /// Spaces trimmed and runs of spaces collapsed (as the server does), then at most 24 characters.
    static func cleaned(_ text: String) -> String {
        limited(text, to: maxLength)
    }

    /// `text` tidied like `cleaned`, cut to at most `max` Unicode scalars: the server counts code points,
    /// so an emoji such as a family can count as several. A character is never cut in half.
    static func limited(_ text: String, to max: Int) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result = ""
        var count = 0
        for character in collapsed {
            count += character.unicodeScalars.count
            if count > max { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    static func isValid(_ text: String) -> Bool {
        !cleaned(text).isEmpty
    }

    /// The server names a new user "Player 1234" when it had no name to use.
    static func looksGenerated(_ name: String) -> Bool {
        let parts = name.split(separator: " ")
        guard parts.count == 2, parts[0] == "Player" else { return false }
        return parts[1].allSatisfy(\.isNumber)
    }
}
