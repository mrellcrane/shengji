import Foundation
import Observation
import ShengjiCore

/// One celebration at the table: a move you just made, or a badge tier you just reached.
struct AchievementToast: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case move(MoveKind)
        case tierUp(AchievementTier)
    }

    let id: UUID
    let kind: Kind
    /// SF Symbol name.
    let symbol: String
    /// "Ruff", or "Ruff · Bronze" for a tier.
    let title: String
    /// "You trumped East's spade lead and won 15 points."
    let detail: String

    init(id: UUID = UUID(), kind: Kind, symbol: String, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    /// A move: its symbol and name, and the detector's line (without repeating the name at the start).
    static func move(_ event: MoveEvent) -> AchievementToast {
        let title = event.kind.title
        return AchievementToast(kind: .move(event.kind), symbol: event.kind.symbol, title: title,
                                detail: detailText(event.detail, title: title))
    }

    /// A tier reached: "Ruff · Bronze" and what comes next.
    static func tierUp(_ tierUp: TierUp) -> AchievementToast {
        let definition = tierUp.achievement
        let next = nextTier(after: tierUp.tier, thresholds: definition.thresholds)
        let detail: String
        if let next {
            detail = "New \(tierUp.tier.title.lowercased()) badge! \(next.tier.title) comes at \(next.count)."
        } else {
            detail = "Gold! That's the top tier. Brilliant."
        }
        return AchievementToast(kind: .tierUp(tierUp.tier), symbol: definition.symbol,
                                title: "\(definition.title) · \(tierUp.tier.title)", detail: detail)
    }

    /// The detail line without a leading "Ruff! " (the title already says it).
    static func detailText(_ detail: String, title: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return trimmed }
        for separator in ["! ", ". ", ": ", " · "] {
            let prefix = title + separator
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? trimmed : rest
            }
        }
        return trimmed
    }

    /// The tier after `tier` and the count it needs, if there is one.
    static func nextTier(after tier: AchievementTier, thresholds: [Int]) -> (tier: AchievementTier, count: Int)? {
        guard let next = AchievementTier(rawValue: tier.rawValue + 1) else { return nil }
        let index = next.rawValue - 1
        guard thresholds.indices.contains(index) else { return nil }
        return (next, thresholds[index])
    }

    var accessibilityText: String { "\(title). \(detail)" }
}

/// A badge tier you have earned, and when.
struct EarnedBadge: Identifiable, Equatable, Sendable {
    let definition: AchievementDefinition
    let tier: AchievementTier
    let date: Date

    var id: String { "\(definition.id)#\(tier.rawValue)" }
}

/// Your progress towards every achievement, persisted as JSON in UserDefaults ("achievements.v1";
/// in memory only for demo scenes), plus the queue of celebration toasts for the table.
/// Shared through the environment like `LearningStore`:
/// `@Environment(AchievementStore.self) private var achievements`.
@MainActor
@Observable
final class AchievementStore {
    private(set) var progress: AchievementProgress
    /// Waiting celebrations, oldest first. The table shows the first one.
    private(set) var toasts: [AchievementToast] = []

    /// Demo/screenshot scenes use an ephemeral store so they never touch saved progress.
    let isEphemeral: Bool

    /// The "Move celebrations" setting on the Play tab (on unless turned off).
    static let celebrationsKey = "play.moveCelebrations"
    static let storageKey = "achievements.v1"
    /// Older celebrations are dropped beyond this many (a burst at the end of a round stays short).
    static let maxQueuedToasts = 6

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, ephemeral: Bool = false) {
        self.defaults = defaults
        self.isEphemeral = ephemeral
        if !ephemeral,
           let data = defaults.data(forKey: AchievementStore.storageKey),
           let saved = try? JSONDecoder().decode(AchievementProgress.self, from: data) {
            progress = saved
        } else {
            progress = AchievementProgress()
        }
    }

    // MARK: Reading

    var currentToast: AchievementToast? { toasts.first }

    /// Whether moves are celebrated at the table (the Play tab's "Move celebrations" setting).
    var celebrationsEnabled: Bool {
        defaults.object(forKey: AchievementStore.celebrationsKey) as? Bool ?? true
    }

    func definitions(in category: AchievementCategory) -> [AchievementDefinition] {
        Achievements.all.filter { $0.category == category }
    }

    /// Earned tiers across one category, 0...1.
    func fraction(in category: AchievementCategory) -> Double {
        let counts = tierCounts(in: category)
        return counts.possible > 0 ? Double(counts.earned) / Double(counts.possible) : 0
    }

    /// Tiers earned (and possible) across one category, e.g. (7, 30).
    func tierCounts(in category: AchievementCategory) -> (earned: Int, possible: Int) {
        let definitions = definitions(in: category)
        let possible = definitions.reduce(0) { $0 + $1.thresholds.count }
        let earned = definitions.reduce(0) { $0 + min(progress.tier(for: $1).rawValue, $1.thresholds.count) }
        return (earned, possible)
    }

    /// Tiers earned, newest first (optionally only one category).
    func recentlyEarned(limit: Int, category: AchievementCategory? = nil) -> [EarnedBadge] {
        var badges: [EarnedBadge] = []
        for (key, date) in progress.earnedAt {
            guard let split = key.lastIndex(of: "#"),
                  let raw = Int(key[key.index(after: split)...]),
                  let tier = AchievementTier(rawValue: raw), tier != .none,
                  let definition = Achievements.definition(id: String(key[..<split])) else { continue }
            if let category, definition.category != category { continue }
            badges.append(EarnedBadge(definition: definition, tier: tier, date: date))
        }
        badges.sort { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        return Array(badges.prefix(max(0, limit)))
    }

    /// When a tier of an achievement was first reached.
    func earnedDate(_ definition: AchievementDefinition, tier: AchievementTier) -> Date? {
        progress.earnedAt["\(definition.id)#\(tier.rawValue)"]
    }

    // MARK: Writing

    /// Journey counts from learning progress (lessons, streak, mastered skills, answers). Quiet: the
    /// lesson and review screens celebrate on their own, so no toasts here.
    func syncLearning(_ learner: LearnerProgress, now: Date = .now) {
        var updated = progress
        let reached = updated.syncLearning(learner, now: now)
        guard updated != progress || !reached.isEmpty else { return }
        progress = updated
        save()
    }

    /// Moves made at the table: each one, then any tier it reached, is celebrated.
    func record(_ events: [MoveEvent], now: Date = .now) {
        guard !events.isEmpty else { return }
        let reached = progress.record(events, now: now)
        save()
        enqueue(events.map(AchievementToast.move) + reached.map(AchievementToast.tierUp))
    }

    /// Game milestones after each round: your team's level, and whether you just won the game.
    func recordGameProgress(teamLevel: Rank, wonGame: Bool, now: Date = .now) {
        let reached = progress.recordGameProgress(teamLevel: teamLevel, wonGame: wonGame, now: now)
        save()
        enqueue(reached.map(AchievementToast.tierUp))
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    func clearToasts() {
        if !toasts.isEmpty { toasts = [] }
    }

    /// Used by demo scenes to show sample progress (never saved when ephemeral).
    func replaceProgress(_ newProgress: AchievementProgress) {
        progress = newProgress
        save()
    }

    func resetAll() {
        progress = AchievementProgress()
        toasts = []
        save()
    }

    private func enqueue(_ new: [AchievementToast]) {
        guard !new.isEmpty, celebrationsEnabled else { return }
        var queue = toasts + new
        // Keep the one on screen; drop the oldest waiting ones.
        while queue.count > AchievementStore.maxQueuedToasts {
            queue.remove(at: 1)
        }
        toasts = queue
    }

    private func save() {
        guard !isEphemeral, let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: AchievementStore.storageKey)
    }
}
