import Foundation

/// How well an item was recalled. Graded automatically from correctness and response time.
public enum Grade: Int, Codable, Sendable, CaseIterable {
    case again = 0, hard, good, easy
}

/// Spaced-repetition state of one item (a skill or a fact).
public struct ItemSchedule: Codable, Hashable, Sendable {
    public var itemID: String
    public var due: Date
    /// Current interval in days (0 while in learning steps). While relearning after a lapse it holds the
    /// reduced interval the item will get back when it re-graduates.
    public var intervalDays: Double
    public var ease: Double
    /// Successful reviews in a row.
    public var reps: Int
    public var lapses: Int
    /// Index into the (re)learning steps while the item is still being learned; nil once graduated.
    public var learningStep: Int?
    public var lastReviewed: Date?
    /// True while the item is in the relearning steps after a lapse (it was graduated, then forgotten).
    /// Decides which step list applies and which interval the item graduates to.
    public var isRelearning: Bool = false

    public init(itemID: String, due: Date, intervalDays: Double, ease: Double, reps: Int, lapses: Int,
                learningStep: Int?, lastReviewed: Date?) {
        self.itemID = itemID
        self.due = due
        self.intervalDays = intervalDays
        self.ease = ease
        self.reps = reps
        self.lapses = lapses
        self.learningStep = learningStep
        self.lastReviewed = lastReviewed
    }

    private enum CodingKeys: String, CodingKey {
        case itemID, due, intervalDays, ease, reps, lapses, learningStep, lastReviewed, isRelearning
    }

    /// Lenient decoding: only `itemID` and `due` are required, so data saved by older versions
    /// (for example without `isRelearning`) still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try c.decode(String.self, forKey: .itemID)
        due = try c.decode(Date.self, forKey: .due)
        intervalDays = max(0, (try? c.decodeIfPresent(Double.self, forKey: .intervalDays)) ?? 0)
        ease = (try? c.decodeIfPresent(Double.self, forKey: .ease)) ?? Scheduler.defaultStartingEase
        reps = max(0, (try? c.decodeIfPresent(Int.self, forKey: .reps)) ?? 0)
        lapses = max(0, (try? c.decodeIfPresent(Int.self, forKey: .lapses)) ?? 0)
        learningStep = try? c.decodeIfPresent(Int.self, forKey: .learningStep)
        lastReviewed = try? c.decodeIfPresent(Date.self, forKey: .lastReviewed)
        isRelearning = (try? c.decodeIfPresent(Bool.self, forKey: .isRelearning)) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(itemID, forKey: .itemID)
        try c.encode(due, forKey: .due)
        try c.encode(intervalDays, forKey: .intervalDays)
        try c.encode(ease, forKey: .ease)
        try c.encode(reps, forKey: .reps)
        try c.encode(lapses, forKey: .lapses)
        try c.encodeIfPresent(learningStep, forKey: .learningStep)
        try c.encodeIfPresent(lastReviewed, forKey: .lastReviewed)
        try c.encode(isRelearning, forKey: .isRelearning)
    }
}

/// SM-2 style scheduler with short learning steps (expanding retrieval):
/// new → 1 min → 10 min → 1 day → 1 day × ease → ...; a lapse drops back to a 10-minute relearning step
/// and reduces ease; "easy" graduates straight to 4 days.
///
/// Transitions (deterministic, no random fuzz):
/// - Learning or relearning (`learningStep != nil`):
///   again → back to step 0; hard → repeat the current step; good → next step, graduating after the last one;
///   easy → graduate at once. A new item graduates to `graduatingIntervalDays` (good) or `easyIntervalDays` (easy).
///   An item relearning after a lapse graduates back to the interval it kept at the lapse (good),
///   or to the larger of `easyIntervalDays` and that interval × 1.3 (easy).
/// - Graduated: again → lapse (ease - 0.2, interval halved but at least 1 day, relearning steps);
///   hard → interval × 1.2, ease - 0.15; good → interval × ease; easy → interval × ease × 1.3, ease + 0.15.
///   Good and easy always add at least one day. Intervals never exceed `maximumIntervalDays`
///   and ease never drops below `minimumEase`.
/// - `reps` counts successful answers in a row (hard, good and easy); again resets it to 0.
public struct Scheduler: Hashable, Sendable {
    public var learningSteps: [TimeInterval]
    public var relearningSteps: [TimeInterval]
    public var graduatingIntervalDays: Double
    public var easyIntervalDays: Double
    public var startingEase: Double
    public var minimumEase: Double
    public var maximumIntervalDays: Double

    static let defaultStartingEase = 2.5
    static let secondsPerDay: TimeInterval = 86_400

    public init(learningSteps: [TimeInterval] = [60, 600], relearningSteps: [TimeInterval] = [600],
                graduatingIntervalDays: Double = 1, easyIntervalDays: Double = 4, startingEase: Double = 2.5,
                minimumEase: Double = 1.3, maximumIntervalDays: Double = 180) {
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.graduatingIntervalDays = graduatingIntervalDays
        self.easyIntervalDays = easyIntervalDays
        self.startingEase = startingEase
        self.minimumEase = minimumEase
        self.maximumIntervalDays = maximumIntervalDays
    }

    /// A brand-new item, due immediately, at learning step 0.
    public func newSchedule(itemID: String, now: Date) -> ItemSchedule {
        ItemSchedule(itemID: itemID, due: now, intervalDays: 0, ease: startingEase, reps: 0, lapses: 0,
                     learningStep: 0, lastReviewed: nil)
    }

    public func review(_ s: ItemSchedule, grade: Grade, now: Date) -> ItemSchedule {
        var r = s
        r.lastReviewed = now
        if let step = s.learningStep {
            reviewLearning(&r, step: step, grade: grade, now: now)
        } else {
            reviewGraduated(&r, grade: grade, now: now)
        }
        return r
    }

    /// Automatic grading: wrong → .again; right but slow (> 2× expected) → .hard;
    /// right within expected → .good; right in under half the expected time → .easy.
    /// A right answer with an unusable time (negative, not finite, or no positive expectation) counts as .good.
    public static func grade(correct: Bool, seconds: Double, expectedSeconds: Double) -> Grade {
        guard correct else { return .again }
        guard seconds.isFinite, seconds >= 0, expectedSeconds.isFinite, expectedSeconds > 0 else { return .good }
        if seconds > 2 * expectedSeconds { return .hard }
        if seconds < 0.5 * expectedSeconds { return .easy }
        return .good
    }

    // MARK: - Transitions

    private func reviewLearning(_ r: inout ItemSchedule, step: Int, grade: Grade, now: Date) {
        let steps = r.isRelearning ? relearningSteps : learningSteps
        // Clamp a stored step that no longer fits the configured steps (settings changed, old data).
        let current = steps.isEmpty ? 0 : min(max(step, 0), steps.count - 1)
        // The interval a relearning item kept at its lapse (always at least one day).
        let keptInterval = max(1, r.intervalDays)

        switch grade {
        case .again:
            r.reps = 0
            r.learningStep = 0
            r.due = now.addingTimeInterval(Self.delay(steps, at: 0))
        case .hard:
            r.reps += 1
            r.learningStep = current
            r.due = now.addingTimeInterval(Self.delay(steps, at: current))
        case .good:
            r.reps += 1
            let next = current + 1
            if next < steps.count {
                r.learningStep = next
                r.due = now.addingTimeInterval(steps[next])
            } else {
                graduate(&r, intervalDays: r.isRelearning ? keptInterval : graduatingIntervalDays, now: now)
            }
        case .easy:
            r.reps += 1
            let days = r.isRelearning ? max(easyIntervalDays, keptInterval * 1.3) : easyIntervalDays
            graduate(&r, intervalDays: days, now: now)
        }
    }

    private func reviewGraduated(_ r: inout ItemSchedule, grade: Grade, now: Date) {
        let interval = max(0, r.intervalDays)
        let ease = r.ease

        switch grade {
        case .again:
            r.reps = 0
            r.lapses += 1
            r.ease = max(minimumEase, ease - 0.2)
            r.intervalDays = capped(max(1, interval * 0.5))
            if let firstStep = relearningSteps.first {
                r.isRelearning = true
                r.learningStep = 0
                r.due = now.addingTimeInterval(max(0, firstStep))
            } else {
                // No relearning steps configured: go straight back to the reduced interval.
                r.isRelearning = false
                r.learningStep = nil
                r.due = now.addingTimeInterval(r.intervalDays * Self.secondsPerDay)
            }
        case .hard:
            r.reps += 1
            r.ease = max(minimumEase, ease - 0.15)
            setInterval(&r, days: max(1, interval * 1.2), now: now)
        case .good:
            r.reps += 1
            setInterval(&r, days: max(interval * ease, interval + 1), now: now)
        case .easy:
            r.reps += 1
            setInterval(&r, days: max(interval * ease * 1.3, interval + 1), now: now)
            r.ease = ease + 0.15
        }
    }

    private func graduate(_ r: inout ItemSchedule, intervalDays: Double, now: Date) {
        r.learningStep = nil
        r.isRelearning = false
        setInterval(&r, days: intervalDays, now: now)
    }

    private func setInterval(_ r: inout ItemSchedule, days: Double, now: Date) {
        r.intervalDays = capped(days)
        r.due = now.addingTimeInterval(r.intervalDays * Self.secondsPerDay)
    }

    private func capped(_ days: Double) -> Double {
        min(maximumIntervalDays, max(0, days))
    }

    private static func delay(_ steps: [TimeInterval], at index: Int) -> TimeInterval {
        guard !steps.isEmpty else { return 0 }
        return max(0, steps[min(max(index, 0), steps.count - 1)])
    }
}
