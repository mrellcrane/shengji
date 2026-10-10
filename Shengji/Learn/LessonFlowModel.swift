import Foundation
import Observation
import ShengjiCore

/// The flow through one lesson: its pages (with "your turn" predictions that must be answered
/// before moving on), then the end-of-lesson quiz, then pass or fail.
/// Passing completes the lesson in the store, which unlocks the next one and schedules its items.
/// SwiftUI-free so it can be checked off-device.
@MainActor
@Observable
final class LessonFlowModel {
    enum Stage: Equatable {
        case pages
        case quiz
        case passed
        case failed
    }

    private(set) var lesson: Lesson
    private(set) var pageIndex: Int
    private(set) var stage: Stage = .pages
    /// Choices made on "your turn" pages, by page index.
    private(set) var predictions: [Int: Int] = [:]
    /// The end-of-lesson quiz, once started.
    private(set) var quiz: PracticeModel?
    /// Quiz attempts on this lesson; each retry asks fresh questions.
    private(set) var quizAttempts = 0

    private let quizSeed: UInt64?

    /// - Parameters:
    ///   - startPage: page to open on (clamped to the lesson).
    ///   - demoAnswer: demo only; if the start page is a predict page, shows this choice as already picked.
    ///   - quizSeed: fixes the quiz questions (demo scenes); random when nil.
    init(lesson: Lesson, startPage: Int = 0, demoAnswer: Int? = nil, quizSeed: UInt64? = nil) {
        self.lesson = lesson
        let start = min(max(0, startPage), max(0, lesson.pages.count - 1))
        self.pageIndex = start
        self.quizSeed = quizSeed
        if let demoAnswer, lesson.pages.indices.contains(start),
           case let .predict(question) = lesson.pages[start],
           question.choices.indices.contains(demoAnswer) {
            predictions[start] = demoAnswer
        }
    }

    // MARK: Pages

    var pages: [LessonPage] { lesson.pages }

    var page: LessonPage? {
        lesson.pages.indices.contains(pageIndex) ? lesson.pages[pageIndex] : nil
    }

    var isFirstPage: Bool { pageIndex == 0 }
    var isLastPage: Bool { pageIndex >= lesson.pages.count - 1 }

    var isPredictPage: Bool {
        if case .predict? = page { return true }
        return false
    }

    /// The choice made on the current page, if it's a predict page that has been answered.
    var currentPrediction: Int? { predictions[pageIndex] }

    /// Predict pages must be answered before moving on (commit to a guess first).
    var canContinue: Bool { !isPredictPage || currentPrediction != nil }

    var continueTitle: String { isLastPage ? "Check what you learned" : "Continue" }

    /// "3 of 7"
    var pagePosition: String { "\(min(pageIndex + 1, max(pages.count, 1))) of \(max(pages.count, 1))" }

    /// Overall progress through the lesson, 0...1. The quiz counts as one last step.
    var progress: Double {
        let steps = Double(pages.count + 1)
        switch stage {
        case .pages:
            let done = Double(pageIndex + 1)
            return done / steps
        case .quiz:
            let quizDone: Double = quiz?.progressFraction ?? 0
            let done = Double(pages.count) + quizDone
            return done / steps
        case .passed, .failed:
            return 1
        }
    }

    var nextLesson: Lesson? {
        let number = lesson.number + 1
        return Curriculum.lessons.first { $0.number == number }
    }

    /// Learner-facing names of the items missed in the last quiz attempt.
    var missedTitles: [String] { quiz?.missedTitles ?? [] }

    // MARK: Actions

    func goBack() {
        guard stage == .pages, pageIndex > 0 else { return }
        pageIndex -= 1
    }

    /// Next page, or the quiz after the last page.
    func goForward(using recorder: LearningRecorder) {
        guard stage == .pages, canContinue else { return }
        if isLastPage {
            startQuiz(using: recorder)
        } else {
            pageIndex += 1
        }
    }

    /// The learner's guess on a predict page. The first answer counts; it can't be changed.
    func recordPrediction(_ choice: Int) {
        guard stage == .pages, isPredictPage, predictions[pageIndex] == nil else { return }
        predictions[pageIndex] = choice
    }

    func startQuiz(using recorder: LearningRecorder) {
        quizAttempts += 1
        let seed = quizSeed.map { $0 &+ UInt64(quizAttempts) } ?? UInt64.random(in: UInt64.min...UInt64.max)
        let model = PracticeModel(kind: .lessonQuiz(lessonID: lesson.id), seed: seed)
        quiz = model
        stage = .quiz
        model.start(using: recorder)
        finishQuizIfDone(using: recorder)
    }

    func answerQuiz(choice: Int, seconds: Double, using recorder: LearningRecorder) {
        guard stage == .quiz else { return }
        quiz?.answer(choice: choice, seconds: seconds, using: recorder)
    }

    func continueQuiz(using recorder: LearningRecorder) {
        guard stage == .quiz, let quiz else { return }
        quiz.advance(using: recorder)
        finishQuizIfDone(using: recorder)
    }

    /// Back to the first page to read the lesson again (predictions can be made afresh).
    func reviewLesson() {
        predictions = [:]
        pageIndex = 0
        stage = .pages
    }

    /// A new attempt with fresh questions.
    func retryQuiz(using recorder: LearningRecorder) {
        startQuiz(using: recorder)
    }

    /// Switches to the next lesson, from its first page. Returns false if this was the last lesson.
    @discardableResult
    func openNextLesson() -> Bool {
        guard let next = nextLesson else { return false }
        lesson = next
        predictions = [:]
        pageIndex = 0
        quiz = nil
        quizAttempts = 0
        stage = .pages
        return true
    }

    private func finishQuizIfDone(using recorder: LearningRecorder) {
        guard stage == .quiz, let quiz, quiz.phase == .finished else { return }
        if quiz.passed {
            recorder.completeLesson(lesson)
            stage = .passed
        } else {
            stage = .failed
        }
    }
}
