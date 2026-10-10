import Foundation

/// What happens to the levels after a round.
public struct LevelOutcome: Hashable, Codable, Sendable {
    /// True if the declarers (dealer's team) kept the deal (defenders < 80).
    public var declarersHold: Bool
    /// Levels gained by the side that benefits (declarers if they hold, else defenders). May be 0.
    public var levels: Int
    /// e.g. "Defenders scored 85 (80 or more): they take over the deal but don't go up a level."
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
    public static func outcome(defenderPoints: Int) -> LevelOutcome {
        let points = max(0, defenderPoints)
        if points < takeoverThreshold {
            let levels: Int
            let scored: String
            if points == 0 {
                levels = 3
                scored = "Defenders scored 0"
            } else if points < stepSize {
                levels = 2
                scored = "Defenders scored \(points) (under \(stepSize))"
            } else {
                levels = 1
                scored = "Defenders scored \(points) (under \(takeoverThreshold))"
            }
            return LevelOutcome(
                declarersHold: true, levels: levels,
                summary: "\(scored): the declarers keep the deal and go up \(levelPhrase(levels)).")
        }
        let levels = (points - takeoverThreshold) / stepSize
        let line = takeoverThreshold + levels * stepSize
        let effect = levels == 0
            ? "they take over the deal but don't go up a level."
            : "they take over the deal and go up \(levelPhrase(levels))."
        return LevelOutcome(declarersHold: false, levels: levels,
                            summary: "Defenders scored \(points) (\(line) or more): \(effect)")
    }

    /// Kitty multiplier when the defenders win the last trick: 2 × the number of cards in the
    /// largest component of the last trick's lead (single ×2, pair ×4, 2-pair tractor ×8, 3-pair ×12).
    public static func kittyMultiplier(lastLead: [Card], trump: Trump) -> Int {
        let largest = Combos.decompose(lastLead, trump: trump).map(\.shape.cardCount).max() ?? 1
        return 2 * largest
    }

    /// "1 level", "2 levels".
    static func levelPhrase(_ levels: Int) -> String {
        levels == 1 ? "1 level" : "\(levels) levels"
    }
}
