import SwiftUI
import ShengjiCore

/// A lesson: short pages with Back / Continue and a progress bar, "your turn" predictions that
/// must be answered before moving on, then the end-of-lesson quiz and its result.
@MainActor
struct LessonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var flow: LessonFlowModel

    /// - Parameters:
    ///   - startPage: page to open on.
    ///   - demoAnswer: demo only; shows this choice as already picked if the start page is a predict page.
    init(_ lesson: Lesson, startPage: Int = 0, demoAnswer: Int? = nil) {
        _flow = State(initialValue: LessonFlowModel(lesson: lesson, startPage: startPage, demoAnswer: demoAnswer))
    }

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(spacing: 0) {
            LearnFlowTopBar(title: flow.lesson.title, subtitle: "Lesson \(flow.lesson.number)",
                            progress: flow.progress, detail: topDetail) {
                dismiss()
            }
            stageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topDetail: String? {
        switch flow.stage {
        case .pages:
            return flow.pagePosition
        case .quiz:
            guard let quiz = flow.quiz, quiz.phase != .finished else { return nil }
            return "Quiz · \(quiz.remainingCount) left"
        case .passed, .failed:
            return nil
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch flow.stage {
        case .pages:
            LessonPagesStage(flow: flow)
        case .quiz:
            LessonQuizView(flow: flow)
        case .passed:
            LessonPassedView(flow: flow) {
                dismiss()
            }
        case .failed:
            LessonFailedView(flow: flow)
        }
    }
}

/// The lesson's pages with Back / Continue at the bottom.
@MainActor
private struct LessonPagesStage: View {
    @Environment(LearningStore.self) private var store
    let flow: LessonFlowModel

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                if let page = flow.page {
                    LessonPageView(page: page, flow: flow)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }
            .id("\(flow.lesson.id)#\(flow.pageIndex)")
            .onChange(of: flow.currentPrediction, initial: true) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(QuestionView.feedbackID, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            navigationBar
        }
    }

    private var navigationBar: some View {
        LearnBottomBar {
            if !flow.canContinue {
                Text("Answer to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { flow.goBack() }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(flow.isFirstPage)
                LearnPrimaryButton(title: flow.continueTitle, systemImage: flow.isLastPage ? "checkmark.seal" : "chevron.right") {
                    withAnimation(.easeInOut(duration: 0.2)) { flow.goForward(using: store) }
                }
                .disabled(!flow.canContinue)
            }
        }
    }
}

/// Draws one `LessonPage`.
@MainActor
private struct LessonPageView: View {
    let page: LessonPage
    let flow: LessonFlowModel

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        switch page {
        case let .text(title, text):
            TextLessonPage(title: title, text: text)
        case let .cards(title, text, cards, trump):
            CardsLessonPage(title: title, text: text, cards: cards, trump: trump)
        case let .trick(title, text, plays, trump, winner):
            TrickLessonPage(title: title, text: text, plays: plays, trump: trump, winner: winner)
        case let .predict(question):
            QuestionView(question, mode: .predict, preselected: flow.currentPrediction) { choice, _ in
                flow.recordPrediction(choice)
            }
        case let .recap(points):
            RecapLessonPage(points: points)
        }
    }
}

@MainActor
private struct TextLessonPage: View {
    let title: String
    let text: String

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.bold))
            RichText(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A worked example with real cards (words and pictures together).
@MainActor
private struct CardsLessonPage: View {
    let title: String
    let text: String
    let cards: [Card]
    let trump: Trump?

    private var cardWidth: CGFloat {
        switch cards.count {
        case ...3: return 64
        case 4...5: return 56
        default: return 46
        }
    }

    private var spacing: CGFloat { cards.count <= 5 ? 8 : -12 }

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
            RichText(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let trump {
                TrumpBadge(trump: trump)
            }
            LearnCardRows(cards: cards, trump: trump, markTrumps: trump != nil,
                          cardWidth: cardWidth, perRow: 7, spacing: spacing, alignment: .center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 8)
                .background(
                    LinearGradient(colors: [Theme.felt, Theme.feltDeep], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A worked trick: who played what, and who won.
@MainActor
private struct TrickLessonPage: View {
    let title: String
    let text: String
    let plays: [Play]
    let trump: Trump
    let winner: Int

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
            TrumpBadge(trump: trump)
            TrickDiagram(plays: plays, trump: trump, winner: winner, markTrumps: true, cardWidth: 40)
            RichText(text)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Key takeaways at the end of a lesson.
@MainActor
private struct RecapLessonPage: View {
    let points: [String]

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        VStack(alignment: .leading, spacing: 16) {
            Text("Key points")
                .font(.title2.weight(.bold))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.correct)
                        RichText(point)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .learnCard()
            Label("Next: a short quiz. Answer from memory; recalling is what makes it stick.",
                  systemImage: "brain.head.profile")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
