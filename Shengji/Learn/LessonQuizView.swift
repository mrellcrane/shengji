import SwiftUI
import ShengjiCore

/// "Check what you learned": the end-of-lesson quiz (a `PracticeSession` of kind `.lessonQuiz`).
@MainActor
struct LessonQuizView: View {
    @Environment(LearningStore.self) private var store
    let flow: LessonFlowModel

    var body: some View {
        if let quiz = flow.quiz {
            PracticeRunner(model: quiz,
                           note: "Answer from memory. Get 80% right on the first try to unlock the next lesson.") { choice, seconds in
                flow.answerQuiz(choice: choice, seconds: seconds, using: store)
            } onContinue: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    flow.continueQuiz(using: store)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Quiz passed: a small celebration, what comes next, and the spacing schedule.
@MainActor
struct LessonPassedView: View {
    let flow: LessonFlowModel
    let onDone: () -> Void

    @State private var celebrates = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                CelebrationBadge(isOn: celebrates)
                Text("Lesson passed!")
                    .font(.largeTitle.weight(.bold))
                if let quiz = flow.quiz, quiz.firstTryTotal > 0 {
                    Text("You got \(quiz.firstTrySummary).")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                newSkillsCard
                spacingCard
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            LearnBottomBar {
                if let next = flow.nextLesson {
                    LearnPrimaryButton(title: "Next lesson: \(next.title)", systemImage: "arrow.right") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            _ = flow.openNextLesson()
                        }
                    }
                    LearnSecondaryButton(title: "Done", action: onDone)
                } else {
                    LearnPrimaryButton(title: "Done", action: onDone)
                }
            }
        }
        .onAppear {
            celebrates = true
        }
        .sensoryFeedback(.success, trigger: celebrates)
    }

    @ViewBuilder private var newSkillsCard: some View {
        let titles = ItemNames.titles(for: flow.lesson.itemIDs)
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("New in your reviews", systemImage: "sparkles")
                    .font(.headline)
                LearnBulletList(items: titles, symbol: "checkmark", symbolColor: Theme.correct, symbolSize: 12)
                    .font(.subheadline)
            }
            .learnCard()
        }
    }

    private var spacingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Coming back to you", systemImage: "calendar")
                .font(.headline)
            Text("These skills are ready for review in about a minute. Then they come back in 10 minutes, then tomorrow, with longer gaps each time you get them right. Spacing them out like this is what makes them stick.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .learnCard()
    }
}

/// Quiz not passed yet: encouragement, what was missed, and two ways forward.
@MainActor
struct LessonFailedView: View {
    @Environment(LearningStore.self) private var store
    let flow: LessonFlowModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.themColor)
                    .padding(.top, 12)
                Text("Almost there")
                    .font(.largeTitle.weight(.bold))
                Text(summary)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if !flow.missedTitles.isEmpty {
                    missedCard
                }
                Text("Getting things wrong and then fixing them is part of learning. Have another look, then try again with fresh questions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            LearnBottomBar {
                LearnPrimaryButton(title: "Retry quiz", systemImage: "arrow.clockwise") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        flow.retryQuiz(using: store)
                    }
                }
                LearnSecondaryButton(title: "Review lesson", systemImage: "book") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        flow.reviewLesson()
                    }
                }
            }
        }
    }

    private var summary: String {
        guard let quiz = flow.quiz else { return "You need 80% to unlock the next lesson." }
        return "You got \(quiz.firstTrySummary). You need 80% to unlock the next lesson."
    }

    private var missedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("What to look at again", systemImage: "magnifyingglass")
                .font(.headline)
            LearnBulletList(items: flow.missedTitles)
                .font(.subheadline)
        }
        .learnCard()
    }
}

/// A seal with card suits bursting out around it.
@MainActor
private struct CelebrationBadge: View {
    let isOn: Bool

    private static let suits = ["♠", "♥", "♣", "♦"]

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                suitSymbol(index)
            }
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76))
                .foregroundStyle(Theme.correct)
                .scaleEffect(isOn ? 1 : 0.3)
        }
        .frame(height: 180)
        .animation(.spring(response: 0.55, dampingFraction: 0.6), value: isOn)
        .accessibilityHidden(true)
    }

    private func suitSymbol(_ index: Int) -> some View {
        let symbol = Self.suits[index % Self.suits.count]
        let color: Color = index % 2 == 0 ? Color.primary : Theme.cardRed
        return Text(symbol)
            .font(.title)
            .foregroundStyle(color)
            .offset(y: isOn ? -74 : 0)
            .rotationEffect(.degrees(Double(index) * 45))
            .opacity(isOn ? 1 : 0)
    }
}
