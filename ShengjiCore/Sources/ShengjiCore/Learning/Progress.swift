import Foundation

// API CONTRACT (stub). Filled in by the learning work.

/// How much help the table gives during play. Scaffolding is meant to fade as skill grows.
public enum CoachLevel: String, Codable, CaseIterable, Sendable {
    /// Legal cards highlighted, trumps marked, every trick explained, hints on tap.
    case guided
    /// Mistakes explained and hints on tap; no highlighting.
    case coached
    /// No help.
    case solo

    public var title: String { fatalError("TODO") }
    public var blurb: String { fatalError("TODO") }
}

public struct SkillStats: Codable, Hashable, Sendable {
    public var attempts: Int
    public var correct: Int
    /// Most recent results, newest last, at most 10.
    public var recent: [Bool]

    public init(attempts: Int = 0, correct: Int = 0, recent: [Bool] = []) {
        self.attempts = attempts
        self.correct = correct
        self.recent = recent
    }

    public var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

/// Everything persisted about the learner. Plain value type; the app stores it as JSON.
public struct LearnerProgress: Codable, Hashable, Sendable {
    public var completedLessons: Set<String>
    public var schedules: [String: ItemSchedule]
    public var stats: [String: SkillStats]
    /// Days (yyyy-MM-dd, local time) with at least one review or lesson, for the streak.
    public var studyDays: [String]
    public var coachLevel: CoachLevel
    public var gamesPlayed: Int
    public var gamesWon: Int
    public var roundsPlayed: Int

    public init() { fatalError("TODO") }

    /// Lesson 1 is always open; lesson n opens once lesson n-1 is completed (mastery gating).
    public func isUnlocked(_ lesson: Lesson) -> Bool { fatalError("TODO") }

    /// Marks the lesson complete and schedules its items (due now, at learning step 0) if new.
    public mutating func completeLesson(_ lesson: Lesson, now: Date, scheduler: Scheduler = Scheduler()) { fatalError("TODO") }

    /// Item ids due at `now`, most overdue first.
    public func dueItemIDs(now: Date) -> [String] { fatalError("TODO") }

    /// Earliest future due date among scheduled items.
    public func nextDueDate(after now: Date) -> Date? { fatalError("TODO") }

    /// Records an answer: updates stats and study days, and — when `updateSchedule` is true and the
    /// item is scheduled — its spaced-repetition schedule (graded by `Scheduler.grade`).
    public mutating func record(itemID: String, correct: Bool, seconds: Double, now: Date,
                                updateSchedule: Bool = true, scheduler: Scheduler = Scheduler()) { fatalError("TODO") }

    /// Item ids the learner has unlocked (scheduled), in lesson order.
    public var unlockedItemIDs: [String] { fatalError("TODO") }

    /// A mistake made during real play (e.g. an illegal follow): makes that skill due now
    /// so it gets retrieval practice soon. No-op if the skill isn't scheduled yet.
    public mutating func noteGameMistake(_ skill: SkillID, now: Date) { fatalError("TODO") }

    /// 0...1 estimate of how well an item is known (interval length and recent accuracy).
    public func mastery(of itemID: String) -> Double { fatalError("TODO") }

    /// Question difficulty for an item, 1...3, rising with successful reps.
    public func difficulty(for itemID: String) -> Int { fatalError("TODO") }

    /// Consecutive study days ending today (or yesterday, if not studied yet today).
    public func streak(now: Date, calendar: Calendar = .current) -> Int { fatalError("TODO") }
}

/// A queue of retrieval-practice questions with immediate feedback. Missed items are re-asked
/// later in the same session (after `retryGap` other questions) until answered correctly.
/// Used for both daily review (interleaved due items) and end-of-lesson quizzes.
public struct PracticeSession: Sendable {
    public enum Kind: Hashable, Sendable {
        /// Due items across all lessons, interleaved.
        case review
        /// End-of-lesson check: the lesson's items plus a couple of earlier items (cumulative review).
        case lessonQuiz(lessonID: String)
        /// Extra practice on demand: random unlocked items (or just `skills` if non-empty).
        /// Answers here should NOT move schedules (reviewing before due would distort intervals).
        case freePractice(skills: [SkillID])
    }

    /// Whether answers in this session should update spaced-repetition schedules (only `.review`).
    public var updatesSchedule: Bool { fatalError("TODO") }

    public let kind: Kind
    /// Item ids still to ask, front first.
    public private(set) var queue: [String]
    public private(set) var current: Question?
    /// Items answered correctly on the first try / items asked for the first time.
    public private(set) var firstTryCorrect: Int
    public private(set) var firstTryTotal: Int
    public private(set) var answeredCount: Int
    public var retryGap: Int

    /// Review: up to `maxItems` due items, shuffled so consecutive questions differ in kind (interleaving).
    /// Lesson quiz: each lesson item once or twice (≈ 6–8 questions) plus up to 2 earlier items.
    /// Free practice: `maxItems` random picks from unlocked items (or the given skills).
    public init<G: RandomNumberGenerator>(kind: Kind, progress: LearnerProgress, now: Date, maxItems: Int = 15, rng: inout G) { fatalError("TODO") }

    /// Pops the next item and generates its question (difficulty from `progress`). Nil when done.
    public mutating func next<G: RandomNumberGenerator>(progress: LearnerProgress, rng: inout G) -> Question? { fatalError("TODO") }

    /// Records the answer to `current`. A wrong answer re-inserts the item `retryGap` places later.
    public mutating func answer(correct: Bool) { fatalError("TODO") }

    public var isFinished: Bool { fatalError("TODO") }
    /// First-try accuracy, 0...1.
    public var score: Double { fatalError("TODO") }
    /// Lesson quizzes pass at ≥ 80% first-try accuracy.
    public var passed: Bool { fatalError("TODO") }
}
