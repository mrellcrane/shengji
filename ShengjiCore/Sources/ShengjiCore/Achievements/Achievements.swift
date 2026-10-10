import Foundation

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

    public init(achievement: AchievementDefinition, tier: AchievementTier) {
        self.achievement = achievement
        self.tier = tier
    }
}

/// Progress towards every achievement. Persisted by the app as JSON (lenient decoding: missing keys default).
///
/// Counts never go down: moves and games won add up, and synced values (levels, lessons, streak, mastery,
/// answers) only ever raise a count. Every method that can raise a count returns the tiers newly reached,
/// in `Achievements.all` order, lowest tier first within an achievement.
public struct AchievementProgress: Codable, Hashable, Sendable {
    /// Count per achievement id.
    public private(set) var counts: [String: Int]
    /// When each tier was first reached: key "<achievementID>#<tier rawValue>".
    public private(set) var earnedAt: [String: Date]

    public init() {
        counts = [:]
        earnedAt = [:]
    }

    /// Adds table moves (each event counts once). Returns tiers newly reached (ordered).
    public mutating func record(_ events: [MoveEvent], now: Date) -> [TierUp] {
        guard !events.isEmpty else { return [] }
        var added: [String: Int] = [:]
        for event in events {
            guard let definition = Achievements.definition(for: event.kind) else { continue }
            added[definition.id, default: 0] += 1
        }
        return apply(now: now) { id, current in
            guard let extra = added[id] else { return current }
            return Self.adding(current, extra)
        }
    }

    /// Updates game milestones after a round: the human team's current level and whether a game was just won.
    public mutating func recordGameProgress(teamLevel: Rank, wonGame: Bool, now: Date) -> [TierUp] {
        let climbed = max(0, teamLevel.rawValue - Rank.two.rawValue)
        return apply(now: now) { id, current in
            switch id {
            case Achievements.levelReachedID: return max(current, climbed)
            case Achievements.gamesWonID: return wonGame ? Self.adding(current, 1) : current
            default: return current
            }
        }
    }

    /// Syncs journey counts from learning progress (lessons, longest streak, mastered skills, answers).
    /// Counts never go down. Returns tiers newly reached.
    /// Games won are also raised to `progress.gamesWon`, so wins from before achievements existed count.
    public mutating func syncLearning(_ progress: LearnerProgress, now: Date) -> [TierUp] {
        let lessons = progress.completedLessons.count
        let streak = Achievements.longestStreak(progress.studyDays)
        var mastered = 0
        for id in progress.unlockedItemIDs where progress.mastery(of: id) >= Achievements.masteryThreshold {
            mastered += 1
        }
        var answers = 0
        for stat in progress.stats.values { answers = Self.adding(answers, max(0, stat.attempts)) }
        let wins = max(0, progress.gamesWon)
        return apply(now: now) { id, current in
            switch id {
            case Achievements.lessonsCompletedID: return max(current, lessons)
            case Achievements.studyStreakID: return max(current, streak)
            case Achievements.skillsMasteredID: return max(current, mastered)
            case Achievements.questionsAnsweredID: return max(current, answers)
            case Achievements.gamesWonID: return max(current, wins)
            default: return current
            }
        }
    }

    public func count(for definition: AchievementDefinition) -> Int { max(0, counts[definition.id] ?? 0) }

    public func tier(for definition: AchievementDefinition) -> AchievementTier {
        Self.tier(count: count(for: definition), thresholds: definition.thresholds)
    }

    /// Next threshold to aim for (nil once gold).
    public func nextThreshold(for definition: AchievementDefinition) -> Int? {
        let count = count(for: definition)
        let reached = tier(for: definition).rawValue
        guard reached < AchievementTier.gold.rawValue, definition.thresholds.indices.contains(reached) else { return nil }
        let next = definition.thresholds[reached]
        return next > count ? next : nil
    }

    /// 0...1 progress from the current tier's threshold to the next one (1 when gold).
    public func fractionToNextTier(for definition: AchievementDefinition) -> Double {
        guard let next = nextThreshold(for: definition) else { return 1 }
        let reached = tier(for: definition).rawValue
        let floor = reached > 0 && definition.thresholds.indices.contains(reached - 1) ? definition.thresholds[reached - 1] : 0
        let span = next - floor
        guard span > 0 else { return 1 }
        let fraction = Double(count(for: definition) - floor) / Double(span)
        return min(1, max(0, fraction))
    }

    /// Earned tiers across all achievements / total possible tiers, 0...1 (for an overall progress bar).
    public var overallFraction: Double {
        var earned = 0
        var possible = 0
        for definition in Achievements.all {
            possible += min(definition.thresholds.count, AchievementTier.gold.rawValue)
            earned += tier(for: definition).rawValue
        }
        guard possible > 0 else { return 0 }
        return min(1, Double(earned) / Double(possible))
    }

    /// When `tier` of `definition` was first reached (nil if not reached, or reached before dates were kept).
    public func earnedDate(for definition: AchievementDefinition, tier: AchievementTier) -> Date? {
        earnedAt[Self.earnedKey(definition.id, tier)]
    }

    // MARK: - Internals

    static func earnedKey(_ id: String, _ tier: AchievementTier) -> String { "\(id)#\(tier.rawValue)" }

    static func tier(count: Int, thresholds: [Int]) -> AchievementTier {
        var reached = 0
        for threshold in thresholds.prefix(AchievementTier.gold.rawValue) where count >= threshold {
            reached += 1
        }
        return AchievementTier(rawValue: reached) ?? .gold
    }

    /// Overflow-safe addition (counts are clamped at Int.max).
    static func adding(_ a: Int, _ b: Int) -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        return overflow ? Int.max : sum
    }

    /// Updates every achievement's count with `update(id, current)` (never lowering it) and returns the
    /// tiers newly reached, in `Achievements.all` order.
    private mutating func apply(now: Date, _ update: (String, Int) -> Int) -> [TierUp] {
        var ups: [TierUp] = []
        for definition in Achievements.all {
            let current = count(for: definition)
            let updated = max(current, update(definition.id, current))
            guard updated != current else { continue }
            let before = Self.tier(count: current, thresholds: definition.thresholds)
            counts[definition.id] = updated
            let after = Self.tier(count: updated, thresholds: definition.thresholds)
            guard after > before else { continue }
            for raw in (before.rawValue + 1)...after.rawValue {
                guard let tier = AchievementTier(rawValue: raw) else { continue }
                let key = Self.earnedKey(definition.id, tier)
                if earnedAt[key] == nil { earnedAt[key] = now }
                ups.append(TierUp(achievement: definition, tier: tier))
            }
        }
        return ups
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case counts, earnedAt
    }

    /// Lenient decoding: missing or malformed keys default to empty, negative counts become 0.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawCounts = (try? c.decodeIfPresent([String: LossyEntry<Int>].self, forKey: .counts)) ?? nil
        var counts: [String: Int] = [:]
        for (id, entry) in rawCounts ?? [:] {
            guard let value = entry.value, value > 0 else { continue }
            counts[id] = value
        }
        self.counts = counts
        let rawDates = (try? c.decodeIfPresent([String: LossyEntry<Date>].self, forKey: .earnedAt)) ?? nil
        var dates: [String: Date] = [:]
        for (key, entry) in rawDates ?? [:] {
            guard let date = entry.value else { continue }
            dates[key] = date
        }
        earnedAt = dates
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(counts, forKey: .counts)
        try c.encode(earnedAt, forKey: .earnedAt)
    }
}

/// Decodes a value if it can, or nil instead of failing the surrounding collection.
private struct LossyEntry<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

public enum Achievements {
    /// Every achievement: one per MoveKind (category .moves) plus the journey set (category .journey):
    /// levels (reach 5, 10, A as thresholds on levelReached), games won, lessons completed, study streak,
    /// skills mastered, questions answered.
    public static var all: [AchievementDefinition] { definitions }
    public static func definition(id: String) -> AchievementDefinition? { all.first { $0.id == id } }
    public static func definition(for move: MoveKind) -> AchievementDefinition? {
        all.first { $0.source == .move(move) }
    }

    /// An item counts as mastered at this mastery (see `LearnerProgress.mastery(of:)`).
    public static let masteryThreshold = 0.75

    static let levelReachedID = "journey.levelReached"
    static let gamesWonID = "journey.gamesWon"
    static let lessonsCompletedID = "journey.lessonsCompleted"
    static let studyStreakID = "journey.studyStreak"
    static let skillsMasteredID = "journey.skillsMastered"
    static let questionsAnsweredID = "journey.questionsAnswered"

    /// Longest run of consecutive days in `studyDays` ("yyyy-MM-dd" keys; malformed keys are ignored).
    public static func longestStreak(_ studyDays: [String]) -> Int {
        let days: [Int] = Set(studyDays.compactMap { LearnerProgress.dayNumber(fromKey: $0) }).sorted()
        var best = 0
        var run = 0
        var previous: Int?
        for day in days {
            if let previous, day == previous + 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    private static let definitions: [AchievementDefinition] = moveDefinitions + journeyDefinitions

    // MARK: Moves

    /// Rarer moves get lower thresholds.
    private static func thresholds(for kind: MoveKind) -> [Int] {
        switch kind {
        case .shutout, .kittyRaid, .cleanThrow, .overrideDeclaration: return [1, 3, 10]
        default: return [1, 5, 25]
        }
    }

    private static let heartsTwo = Trump(rank: .two, suit: .hearts)

    private static func goal(for kind: MoveKind) -> String {
        switch kind {
        case .ruff: return "Win a trick by trumping a suit you're out of."
        case .overruff: return "Beat an opponent's trump with a higher trump in the same trick."
        case .feedPartner: return "Add 5 or more points to a trick your partner wins."
        case .tractor: return "Lead a tractor, or win a trick with one."
        case .cleanThrow: return "Lead several cards of one suit at once that nobody can beat."
        case .topCard: return "Lead a card or combination in a plain suit that nobody beats."
        case .bigJoker: return "Win a trick with the big joker."
        case .kittyRaid: return "As a defender, win the last trick of a round."
        case .declareTrump: return "Make the declaration that sets trump for the round."
        case .overrideDeclaration: return "Beat an opponent's declaration with a stronger one."
        case .holdDeal: return "As declarers, keep the defenders under 80 points."
        case .shutout: return "As declarers, hold the defenders to 0 points."
        case .takeOver: return "As defenders, score 80 or more to take over the deal."
        case .bigTrick: return "Win a trick worth 30 or more points for your team."
        }
    }

    /// Cards that illustrate each move (with hearts trump and rank 2 where trump matters).
    private static func example(for kind: MoveKind) -> (cards: [Card], trump: Trump?) {
        switch kind {
        case .ruff:
            // East leads K♠; you are out of spades and take it with the 3♥.
            return ([Card(.king, .spades), Card(.three, .hearts)], heartsTwo)
        case .overruff:
            // A club lead, an opponent trumps with 4♥, you trump higher with 9♥.
            return ([Card(.ace, .clubs), Card(.four, .hearts), Card(.nine, .hearts)], heartsTwo)
        case .feedPartner:
            // Partner's A♠ is winning; you give them the K♠.
            return ([Card(.ace, .spades), Card(.king, .spades)], heartsTwo)
        case .tractor:
            return ([Card(.seven, .spades), Card(.seven, .spades, copy: 1),
                     Card(.eight, .spades), Card(.eight, .spades, copy: 1)], heartsTwo)
        case .cleanThrow:
            // An ace and a pair of kings: with the other ace out of play, nothing beats any part.
            return ([Card(.ace, .spades), Card(.king, .spades), Card(.king, .spades, copy: 1)], heartsTwo)
        case .topCard:
            return ([Card(.ace, .diamonds)], heartsTwo)
        case .bigJoker:
            return ([Card.bigJoker(), Card.smallJoker(), Card(.two, .hearts)], heartsTwo)
        case .kittyRaid:
            // Kitty points the defenders can win on the last trick.
            return ([Card(.king, .clubs), Card(.ten, .diamonds), Card(.five, .spades)], heartsTwo)
        case .declareTrump:
            return ([Card(.two, .hearts)], heartsTwo)
        case .overrideDeclaration:
            // A pair of 2♠ beats a single 2♥.
            return ([Card(.two, .spades), Card(.two, .spades, copy: 1)], Trump(rank: .two, suit: .spades))
        case .holdDeal:
            // Top trumps to draw the defenders' trumps out.
            return ([Card.bigJoker(), Card.smallJoker(), Card(.two, .hearts)], heartsTwo)
        case .shutout:
            return ([Card(.five, .clubs), Card(.ten, .diamonds), Card(.king, .spades)], nil)
        case .takeOver:
            return ([Card(.ten, .spades), Card(.king, .clubs), Card(.five, .diamonds)], nil)
        case .bigTrick:
            return ([Card(.ace, .spades), Card(.king, .spades), Card(.ten, .spades), Card(.ten, .spades, copy: 1)], heartsTwo)
        }
    }

    private static let moveDefinitions: [AchievementDefinition] = MoveKind.allCases.map { kind in
        let sample = example(for: kind)
        return AchievementDefinition(
            id: "move." + kind.rawValue, title: kind.title, category: .moves, source: .move(kind),
            thresholds: thresholds(for: kind), goal: goal(for: kind), lesson: kind.howTo,
            exampleCards: sample.cards, exampleTrump: sample.trump, symbol: kind.symbol)
    }

    // MARK: Journey

    private static let journeyDefinitions: [AchievementDefinition] = [
        AchievementDefinition(
            id: levelReachedID, title: "Level climber", category: .journey, source: .levelReached,
            thresholds: [3, 8, 12],
            goal: "Reach level 5, then 10, then A with your team.",
            lesson: "Your team climbs a level each time you hold the deal or take it over with points to spare. Every level climbed brings you closer to A.",
            exampleCards: [Card(.five, .hearts), Card(.ten, .hearts), Card(.ace, .hearts)], exampleTrump: nil,
            symbol: "arrow.up.circle.fill"),
        AchievementDefinition(
            id: gamesWonID, title: "Game winner", category: .journey, source: .gamesWon,
            thresholds: [1, 3, 10],
            goal: "Win a whole game: hold the deal at level A.",
            lesson: "Reaching A is not enough: you win the game by holding the deal as declarers while at A.",
            exampleCards: [Card(.ace, .spades), Card(.ace, .hearts), Card(.ace, .clubs), Card(.ace, .diamonds)],
            exampleTrump: nil, symbol: "trophy.fill"),
        AchievementDefinition(
            id: lessonsCompletedID, title: "Scholar", category: .journey, source: .lessonsCompleted,
            thresholds: [3, 8, 12],
            goal: "Complete 3, then 8, then all 12 lessons.",
            lesson: "Each lesson is one idea, checked by a short quiz. Passing it unlocks the next one and adds its skills to your reviews.",
            exampleCards: [], exampleTrump: nil, symbol: "graduationcap.fill"),
        AchievementDefinition(
            id: studyStreakID, title: "Study streak", category: .journey, source: .studyStreak,
            thresholds: [3, 7, 30],
            goal: "Study on 3, 7, then 30 days in a row.",
            lesson: "A few minutes every day beats one long session. Spaced practice is how rules move into long-term memory.",
            exampleCards: [], exampleTrump: nil, symbol: "flame.fill"),
        AchievementDefinition(
            id: skillsMasteredID, title: "Skill master", category: .journey, source: .skillsMastered,
            thresholds: [3, 8, 15],
            goal: "Master 3, then 8, then 15 skills and facts in review.",
            lesson: "An item is mastered when you answer it well over growing gaps of time. Keep doing your reviews when they are due.",
            exampleCards: [], exampleTrump: nil, symbol: "checkmark.seal.fill"),
        AchievementDefinition(
            id: questionsAnsweredID, title: "Questions answered", category: .journey, source: .questionsAnswered,
            thresholds: [50, 250, 1000],
            goal: "Answer 50, then 250, then 1,000 practice questions.",
            lesson: "Answering questions from memory teaches more than reading the rules again. Every answer, right or wrong, strengthens what you know.",
            exampleCards: [], exampleTrump: nil, symbol: "questionmark.circle.fill"),
    ]
}
