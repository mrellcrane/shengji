import SwiftUI
import ShengjiCore

/// A practice session: daily review, extra practice, or (through `LessonQuizView`) a lesson quiz.
/// Shows progress, one question at a time with feedback, and a summary at the end.
@MainActor
struct PracticeView: View {
    @Environment(LearningStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var model: PracticeModel

    /// - Parameters:
    ///   - seed: fixes the questions (demo scenes); random when nil.
    ///   - answerFirstQuestionWrongly: demo only; shows the feedback for a wrong first answer.
    init(kind: PracticeSession.Kind, seed: UInt64? = nil, answerFirstQuestionWrongly: Bool = false) {
        let model = PracticeModel(kind: kind,
                                  seed: seed ?? UInt64.random(in: UInt64.min...UInt64.max),
                                  answerFirstQuestionWrongly: answerFirstQuestionWrongly)
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            LearnFlowTopBar(title: model.kind.screenTitle, progress: model.progressFraction, detail: progressDetail) {
                dismiss()
            }
            content
        }
        .onAppear {
            model.start(using: store)
        }
    }

    private var progressDetail: String? {
        switch model.phase {
        case .notStarted, .finished: return nil
        case .asking, .answered: return "\(model.answeredCount) done · \(model.remainingCount) left"
        }
    }

    private var note: String? {
        switch model.kind {
        case .review: return nil
        case .lessonQuiz: return nil
        case .freePractice: return "Extra practice doesn't change your review schedule."
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .notStarted:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .asking, .answered:
            PracticeRunner(model: model, note: note) { choice, seconds in
                model.answer(choice: choice, seconds: seconds, using: store)
            } onContinue: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    model.advance(using: store)
                }
            }
        case .finished:
            PracticeSummaryView(model: model) {
                dismiss()
            }
        }
    }
}

/// The question on screen, its feedback, and the Continue bar. Shared by practice and lesson quizzes.
@MainActor
struct PracticeRunner: View {
    let model: PracticeModel
    var note: String? = nil
    let onAnswer: (Int, Double) -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let note {
                        Label(note, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let question = model.question {
                        QuestionView(question, mode: .practice, preselected: model.selectedChoice, onAnswer: onAnswer)
                            .id(model.questionNumber)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            // A fresh scroll view per question, so the next question starts at the top
            // instead of where the previous one was scrolled to (its feedback).
            .id(model.questionNumber)
            .onChange(of: model.selectedChoice, initial: true) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(QuestionView.feedbackID, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.phase == .answered {
                continueBar
            }
        }
    }

    private var continueBar: some View {
        LearnBottomBar {
            if model.missedQuestionComesBack {
                Label("We'll come back to this one.", systemImage: "arrow.uturn.backward.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            LearnPrimaryButton(title: model.remainingCount == 0 ? "Finish" : "Continue", action: onContinue)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// End of a practice session: first-try score, what to revisit, and when the next review is due.
@MainActor
private struct PracticeSummaryView: View {
    let model: PracticeModel
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: model.firstTryTotal == 0 ? "tray" : "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(model.firstTryTotal == 0 ? Color.secondary : Theme.correct)
                    .padding(.top, 12)
                Text(headline)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if model.firstTryTotal > 0 {
                    scoreCard
                }
                if !model.missedTitles.isEmpty {
                    missedCard
                }
                nextReviewCard
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            LearnBottomBar {
                LearnPrimaryButton(title: "Done", action: onDone)
            }
        }
    }

    private var headline: String {
        guard model.firstTryTotal > 0 else { return "Nothing to practise right now" }
        switch model.score {
        case 0.9...: return "Excellent work!"
        case 0.7..<0.9: return "Nice work!"
        default: return "Good effort. Mistakes help it stick."
        }
    }

    private var scoreCard: some View {
        HStack(spacing: 16) {
            MasteryRing(value: model.score, size: 56, lineWidth: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.firstTryCorrect) of \(model.firstTryTotal)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("right on the first try")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .learnCard()
    }

    private var missedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Worth another look", systemImage: "arrow.uturn.backward.circle")
                .font(.headline)
            LearnBulletList(items: model.missedTitles)
                .font(.subheadline)
            Text(model.updatesSchedule
                 ? "These come back sooner in your reviews."
                 : "You can practise them again any time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .learnCard()
    }

    private var nextReviewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Next review", systemImage: "calendar")
                .font(.headline)
            Text(nextReviewText)
                .font(.subheadline)
            if isExtraPractice {
                Text("Extra practice doesn't change your review schedule.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .learnCard()
    }

    private var isExtraPractice: Bool {
        if case .freePractice = model.kind { return true }
        return false
    }

    private var nextReviewText: String {
        if model.stillDueCount > 0 {
            let count = model.stillDueCount
            return (count == 1 ? "1 review is" : "\(count) reviews are") + " still due. Start another round from the Review tab."
        }
        guard let date = model.nextDueDate else { return "Nothing scheduled yet. Pass a lesson to add to your reviews." }
        return "Your next review is due \(TimePhrase.until(date))."
    }
}
