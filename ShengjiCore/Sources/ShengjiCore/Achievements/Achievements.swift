import Foundation

// API CONTRACT (stub). Filled in by the achievements-core work.

public enum AchievementTier: Int, Codable, Comparable, CaseIterable, Sendable {
    case none = 0, bronze, silver, gold

    public static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .none: return "Not yet"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }
}

/// Where an achievement's count comes from.
public enum AchievementSource: Hashable, Sendable {
    /// Number of times the move was made at the table.
    case move(MoveKind)
    /// Highest level your team has reached in any game (count = levels climbed from 2, e.g. reaching 5 = 3).
    case levelReached
    case gamesWon
    case lessonsCompleted
    /// Longest study streak in days.
    case studyStreak
    /// Number of unlocked items with mastery ≥ 0.75.
    case skillsMastered
    /// Total retrieval-practice answers recorded.
    case questionsAnswered
}

public enum AchievementCategory: String, Codable, CaseIterable, Sendable {
    /// Moves you pull off at the table.
    case moves
    /// Your learning and game journey.
    case journey

    public var title: String { self == .moves ? "Moves" : "Journey" }
}

public struct AchievementDefinition: Identifiable, Hashable, Sendable {
    /// "move.ruff", "journey.gamesWon", ...
    public var id: String
    public var title: String
    public var category: AchievementCategory
    public var source: AchievementSource
    /// Counts needed for bronze, silver, gold (ascending), e.g. [1, 5, 25].
    public var thresholds: [Int]
    /// How to earn it (shown on locked badges as a goal).
    public var goal: String
    /// What it teaches (1 to 2 sentences, second person).
    public var lesson: String
    /// Example cards to draw on the badge detail (may be empty).
    public var exampleCards: [Card]
    /// Trump context for the example cards, if they need one.
    public var exampleTrump: Trump?
    /// SF Symbol name.
    public var symbol: String

    public init(id: String, title: String, category: AchievementCategory, source: AchievementSource, thresholds: [Int],
                goal: String, lesson: String, exampleCards: [Card], exampleTrump: Trump?, symbol: String) {
        self.id = id
        self.title = title
        self.category = category
        self.source = source
        self.thresholds = thresholds
        self.goal = goal
        self.lesson = lesson
        self.exampleCards = exampleCards
        self.exampleTrump = exampleTrump
        self.symbol = symbol
    }
}

/// A tier just reached, for celebration toasts.
public struct TierUp: Hashable, Sendable {
    public var achievement: AchievementDefinition
    public var tier: AchievementTier
}

/// Progress towards every achievement. Persisted by the app as JSON (lenient decoding: missing keys default).
public struct AchievementProgress: Codable, Hashable, Sendable {
    /// Count per achievement id.
    public private(set) var counts: [String: Int]
    /// When each tier was first reached: key "<achievementID>#<tier rawValue>".
    public private(set) var earnedAt: [String: Date]

    public init() { fatalError("TODO") }

    /// Adds table moves. Returns tiers newly reached (ordered).
    public mutating func record(_ events: [MoveEvent], now: Date) -> [TierUp] { fatalError("TODO") }

    /// Updates game milestones after a round: the human team's current level and whether a game was just won.
    public mutating func recordGameProgress(teamLevel: Rank, wonGame: Bool, now: Date) -> [TierUp] { fatalError("TODO") }

    /// Syncs journey counts from learning progress (lessons, longest streak, mastered skills, answers).
    /// Counts never go down. Returns tiers newly reached.
    public mutating func syncLearning(_ progress: LearnerProgress, now: Date) -> [TierUp] { fatalError("TODO") }

    public func count(for definition: AchievementDefinition) -> Int { fatalError("TODO") }
    public func tier(for definition: AchievementDefinition) -> AchievementTier { fatalError("TODO") }
    /// Next threshold to aim for (nil once gold).
    public func nextThreshold(for definition: AchievementDefinition) -> Int? { fatalError("TODO") }
    /// 0...1 progress from the current tier's threshold to the next one (1 when gold).
    public func fractionToNextTier(for definition: AchievementDefinition) -> Double { fatalError("TODO") }
    /// Earned tiers across all achievements / total possible tiers, 0...1 (for an overall progress bar).
    public var overallFraction: Double { fatalError("TODO") }
}

public enum Achievements {
    /// Every achievement: one per MoveKind (category .moves) plus the journey set (category .journey):
    /// levels (reach 5, 10, A as thresholds on levelReached), games won, lessons completed, study streak,
    /// skills mastered, questions answered.
    public static var all: [AchievementDefinition] { fatalError("TODO") }
    public static func definition(id: String) -> AchievementDefinition? { all.first { $0.id == id } }
    public static func definition(for move: MoveKind) -> AchievementDefinition? {
        all.first { $0.source == .move(move) }
    }
}
