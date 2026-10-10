import Foundation

// API CONTRACT (stub). Filled in by the learning work.

/// How well an item was recalled. Graded automatically from correctness and response time.
public enum Grade: Int, Codable, Sendable, CaseIterable {
    case again = 0, hard, good, easy
}

/// Spaced-repetition state of one item (a skill or a fact).
public struct ItemSchedule: Codable, Hashable, Sendable {
    public var itemID: String
    public var due: Date
    /// Current interval in days (0 while in learning steps).
    public var intervalDays: Double
    public var ease: Double
    /// Successful reviews in a row.
    public var reps: Int
    public var lapses: Int
    /// Index into the (re)learning steps while the item is still being learned; nil once graduated.
    public var learningStep: Int?
    public var lastReviewed: Date?

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
}

/// SM-2 style scheduler with short learning steps (expanding retrieval):
/// new → 1 min → 10 min → 1 day → 1 day × ease → ...; a lapse drops back to a 10-minute relearning step
/// and reduces ease; "easy" graduates straight to 4 days.
public struct Scheduler: Hashable, Sendable {
    public var learningSteps: [TimeInterval]
    public var relearningSteps: [TimeInterval]
    public var graduatingIntervalDays: Double
    public var easyIntervalDays: Double
    public var startingEase: Double
    public var minimumEase: Double
    public var maximumIntervalDays: Double

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
    public func newSchedule(itemID: String, now: Date) -> ItemSchedule { fatalError("TODO") }

    public func review(_ s: ItemSchedule, grade: Grade, now: Date) -> ItemSchedule { fatalError("TODO") }

    /// Automatic grading: wrong → .again; right but slow (> 2× expected) → .hard;
    /// right within expected → .good; right in under half the expected time → .easy.
    public static func grade(correct: Bool, seconds: Double, expectedSeconds: Double) -> Grade { fatalError("TODO") }
}
