import Foundation

// API CONTRACT (stub). Filled in by the engine work.

/// What happens to the levels after a round.
public struct LevelOutcome: Hashable, Codable, Sendable {
    /// True if the declarers (dealer's team) kept the deal (defenders < 80).
    public var declarersHold: Bool
    /// Levels gained by the side that benefits (declarers if they hold, else defenders). May be 0.
    public var levels: Int
    /// e.g. "Defenders scored 85 (≥ 80): they take over the deal."
    public var summary: String

    public init(declarersHold: Bool, levels: Int, summary: String) {
        self.declarersHold = declarersHold
        self.levels = levels
        self.summary = summary
    }
}

public enum Scoring {
    public static let totalPoints = 200
    public static let takeoverThreshold = 80
    public static let stepSize = 40

    /// Standard table (two decks):
    ///   0 → declarers +3 · 5–35 → declarers +2 · 40–75 → declarers +1
    ///   80–115 → defenders take over (+0) · 120–155 → take over +1 · 160–195 → +2 · 200+ → +3, each further 40 → +1
    public static func outcome(defenderPoints: Int) -> LevelOutcome { fatalError("TODO") }

    /// Kitty multiplier when the defenders win the last trick: 2 × the number of cards in the
    /// largest component of the last trick's lead (single ×2, pair ×4, 2-pair tractor ×8, 3-pair ×12).
    public static func kittyMultiplier(lastLead: [Card], trump: Trump) -> Int { fatalError("TODO") }
}
