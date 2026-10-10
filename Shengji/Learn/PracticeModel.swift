import Foundation
import Observation
import ShengjiCore

/// What the practice and lesson flows need from the learner's store.
/// `LearningStore` conforms; a mock can stand in for tests.
@MainActor
protocol LearningRecorder: AnyObject {
    var progress: LearnerProgress { get }
    func record(itemID: String, correct: Bool, seconds: Double, updateSchedule: Bool)
    func completeLesson(_ lesson: Lesson)
}

extension LearningStore: LearningRecorder {}

/// Runs one `PracticeSession` (daily review, lesson quiz or extra practice) for a screen:
/// asks a question, takes the answer, records it in the store, shows feedback, moves on,
/// and finally summarises the session. SwiftUI-free so it can be checked off-device.
@MainActor
@Observable
final class PracticeModel {
    enum Phase: Equatable {
        /// `start(using:)` hasn't run yet.
        case notStarted
        /// A question is on screen, waiting for an answer.
        case asking
        /// The answer is in; feedback is showing until the learner continues.
        case answered
        /// No questions left.
        case finished
    }

    let kind: PracticeSession.Kind
    private(set) var phase: Phase = .notStarted
    private(set) var session: PracticeSession?
    /// The question on screen (nil before starting and once finished).
    private(set) var question: Question?
    /// Increases with every new question, so views can reset per question even if ids repeat.
    private(set) var questionNumber = 0
    /// The choice picked for `question` (nil while asking).
    private(set) var selectedChoice: Int?
    /// Items answered wrongly at least once this session, in the order they were missed.
    private(set) var missedItemIDs: [String] = []
    /// When the next review falls due, captured when the session finishes.
    private(set) var nextDueDate: Date?
    /// Items still due right after the session (e.g. more than one session's worth), captured when it finishes.
    private(set) var stillDueCount = 0

    @ObservationIgnored private var rng: SeededGenerator
    private let answersFirstQuestionWrongly: Bool

    /// - Parameters:
    ///   - seed: seeds question generation; fixed in demo scenes so they are deterministic.
    ///   - answerFirstQuestionWrongly: demo only; picks a wrong answer to the first question so its feedback shows.
    init(kind: PracticeSession.Kind, seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
         answerFirstQuestionWrongly: Bool = false) {
        self.kind = kind
        self.rng = SeededGenerator(seed: seed)
        self.answersFirstQuestionWrongly = answerFirstQuestionWrongly
    }

    // MARK: Reading

    /// Whether the answer to the question on screen was right (nil until it's answered).
    var isCorrect: Bool? {
        guard let question, let selectedChoice else { return nil }
        return selectedChoice == question.correctChoice
    }

    var answeredCount: Int { session?.answeredCount ?? 0 }

    /// Questions still to come, counting the one on screen if it hasn't been answered.
    var remainingCount: Int {
        (session?.queue.count ?? 0) + (phase == .asking ? 1 : 0)
    }

    /// 0...1 for a progress bar.
    var progressFraction: Double {
        if phase == .finished { return 1 }
        let total = answeredCount + remainingCount
        return total == 0 ? 0 : Double(answeredCount) / Double(total)
    }

    /// The missed question on screen is queued to come back later in this session.
    var missedQuestionComesBack: Bool {
        guard phase == .answered, isCorrect == false, let itemID = question?.itemID else { return false }
        return session?.queue.contains(itemID) ?? false
    }

    var firstTryCorrect: Int { session?.firstTryCorrect ?? 0 }
    var firstTryTotal: Int { session?.firstTryTotal ?? 0 }

    /// First-try accuracy, 0...1.
    var score: Double { firstTryTotal == 0 ? 0 : (session?.score ?? 0) }

    /// Lesson quizzes pass at 80% first-try accuracy. A quiz with no questions counts as passed.
    var passed: Bool {
        guard let session else { return false }
        return session.firstTryTotal == 0 || session.passed
    }

    /// Whether these answers move the spaced-repetition schedule (only daily review does).
    var updatesSchedule: Bool { session?.updatesSchedule ?? false }

    /// Learner-facing names of the missed items.
    var missedTitles: [String] { ItemNames.titles(for: missedItemIDs) }

    /// "7 of 9 right on the first try".
    var firstTrySummary: String {
        "\(firstTryCorrect) of \(firstTryTotal) right on the first try"
    }

    /// Percentage for display, e.g. 78.
    var scorePercent: Int { Int((score * 100).rounded()) }

    // MARK: Actions

    /// Builds the session from the learner's current progress and shows the first question.
    func start(using recorder: LearningRecorder, now: Date = .now) {
        guard phase == .notStarted else { return }
        var generator = rng
        session = PracticeSession(kind: kind, progress: recorder.progress, now: now, rng: &generator)
        rng = generator
        showNextQuestion(using: recorder, now: now)
        if answersFirstQuestionWrongly, let question,
           let wrong = question.choices.indices.first(where: { $0 != question.correctChoice }) {
            answer(choice: wrong, seconds: 7, using: recorder)
        }
    }

    /// Records the learner's answer to the question on screen and switches to feedback.
    /// `seconds` is the time from the question appearing to the tap.
    func answer(choice: Int, seconds: Double, using recorder: LearningRecorder) {
        guard phase == .asking, let question, question.choices.indices.contains(choice),
              var updated = session else { return }
        let correct = choice == question.correctChoice
        updated.answer(correct: correct)
        session = updated
        selectedChoice = choice
        phase = .answered
        if !correct && !missedItemIDs.contains(question.itemID) {
            missedItemIDs.append(question.itemID)
        }
        recorder.record(itemID: question.itemID, correct: correct, seconds: max(0.1, seconds),
                        updateSchedule: updated.updatesSchedule)
    }

    /// Moves on from the answered question to the next one, or finishes the session.
    /// Ignored while a question is still waiting for its answer (e.g. a second tap on Continue),
    /// so a question can never be skipped or restarted without being answered.
    func advance(using recorder: LearningRecorder, now: Date = .now) {
        guard phase == .answered else { return }
        showNextQuestion(using: recorder, now: now)
    }

    private func showNextQuestion(using recorder: LearningRecorder, now: Date) {
        guard var updated = session else { return }
        var generator = rng
        let next = updated.next(progress: recorder.progress, rng: &generator)
        rng = generator
        session = updated
        selectedChoice = nil
        if let next {
            question = next
            questionNumber += 1
            phase = .asking
        } else {
            question = nil
            nextDueDate = recorder.progress.nextDueDate(after: now)
            stillDueCount = recorder.progress.dueItemIDs(now: now).count
            phase = .finished
        }
    }
}

extension PracticeSession.Kind {
    /// Screen title for a session of this kind.
    var screenTitle: String {
        switch self {
        case .review: return "Review"
        case .lessonQuiz: return "Quiz"
        case let .freePractice(skills):
            if skills.count == 1, let skill = skills.first { return skill.title }
            return "Extra practice"
        }
    }
}
