import Foundation
import ShengjiCore

// SwiftUI-free value types used by the Play tab. Type-checked on Linux together with GameController.

/// Where the table is in its flow. Finer grained than `RoundPhase`: it also covers the declaring
/// window after the deal, the pause after each trick and the "who wins?" prompt.
enum GameStage: String, Codable, Sendable {
    /// Cards are still arriving one at a time.
    case dealing
    /// Every card is dealt; you may still declare (tap Continue to close the window).
    case declareWindow
    /// You declared at the end of the deal; each bot gets one more chance to override.
    case botsRespond
    /// The dealer has the kitty and buries 8 cards.
    case burying
    case playing
    /// A trick just finished; it stays on the table for a moment (tap to skip).
    case trickPause
    /// A trick just finished and you are asked who won it before it is revealed.
    case predicting
    /// The round is scored and the result is available.
    case roundOver
}

/// One message in the coach banner.
struct GameCoachMessage: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case info, hint, warning, success
    }

    let id: UUID
    var text: String
    /// Short tag for the idea behind the message, e.g. "Follow suit" or "Ruff".
    var concept: String?
    var kind: Kind

    init(_ text: String, concept: String? = nil, kind: Kind = .info, id: UUID = UUID()) {
        self.id = id
        self.text = text
        self.concept = concept
        self.kind = kind
    }
}

/// How fast the bots act.
enum GameBotSpeed: String, CaseIterable, Codable, Identifiable, Sendable {
    case relaxed, normal, fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    /// Multiplies every bot delay.
    var delayScale: Double {
        switch self {
        case .relaxed: return 1.6
        case .normal: return 1.0
        case .fast: return 0.5
        }
    }
}

/// How long a game lasts: the level a team must win at.
enum GameLengthOption: String, CaseIterable, Identifiable, Sendable {
    case toFive = "5"
    case toTen = "10"
    case toAce = "A"

    var id: String { rawValue }

    var targetRank: Rank {
        switch self {
        case .toFive: return .five
        case .toTen: return .ten
        case .toAce: return .ace
        }
    }

    var title: String {
        switch self {
        case .toFive: return "Level 5"
        case .toTen: return "Level 10"
        case .toAce: return "Ace"
        }
    }

    var detail: String {
        switch self {
        case .toFive: return "A short game: first team to win at level 5."
        case .toTen: return "A medium game: first team to win at level 10."
        case .toAce: return "The full game: climb all the way to Ace."
        }
    }
}

/// "Who wins this trick?" asked after the 4th card lands and before the winner is shown.
struct GamePredictionPrompt: Equatable, Sendable {
    /// 1-based trick number within the round.
    var trickNumber: Int
    var winner: Int
    var askedAt: Date
}

/// The cards to draw in the middle of the table.
struct TableTrickDisplay: Equatable, Sendable {
    var plays: [Play]
    /// Set once the trick is finished and revealed.
    var winner: Int?
    var isFinished: Bool
    /// Points in the cards shown.
    var points: Int

    static let empty = TableTrickDisplay(plays: [], winner: nil, isFinished: false, points: 0)

    func cards(for seat: Int) -> [Card]? {
        plays.first { $0.player == seat }?.cards
    }

    var leader: Int? { plays.first?.player }
}

enum GameSeatRole: String, Sendable {
    case dealer, declarer, defender

    var title: String {
        switch self {
        case .dealer: return "Dealer"
        case .declarer: return "Declarer"
        case .defender: return "Defender"
        }
    }
}

/// Everything a seat label shows.
struct GameSeatInfo: Equatable, Sendable {
    var seat: Int
    var name: String
    var team: Int
    var cardCount: Int
    var role: GameSeatRole?
    /// It is this seat's turn to act (play, or bury as dealer).
    var isTurn: Bool
    /// A bot in this seat is about to act.
    var isThinking: Bool
    /// This seat won the trick on display.
    var isTrickWinner: Bool
    /// Guided only: this seat is winning the trick in progress.
    var isLeading: Bool

    var accessibilityText: String {
        var parts = [name, "\(cardCount) cards"]
        if let role { parts.append(role.title) }
        if isTurn { parts.append(seat == Seats.human ? "your turn" : "to play") }
        if isTrickWinner { parts.append("won the trick") }
        return parts.joined(separator: ", ")
    }
}

/// The main button in the action bar.
enum GamePrimaryAction: Equatable, Sendable {
    case none
    /// Close the declaring window.
    case continueDeal
    case bury(count: Int, enabled: Bool)
    case play(enabled: Bool)
    /// Skip the pause after a trick.
    case nextTrick
    /// Reopen the round result.
    case showResult
}
