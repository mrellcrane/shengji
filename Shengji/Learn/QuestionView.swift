import SwiftUI
import ShengjiCore

/// One retrieval-practice question: the prompt, the trump context, the picture (cards, a trick,
/// a hand), and the choices. After a tap the input locks, the right choice turns green, a wrong
/// pick turns red, and the explanation appears (right or wrong: always the rule behind it).
///
/// The view measures response time from when the question appears to the tap and reports it
/// with the choice through `onAnswer`. Give it a fresh identity per question (`.id(...)`).
@MainActor
struct QuestionView: View {
    enum Mode: Equatable {
        /// Review, quiz and extra practice.
        case practice
        /// "Your turn" in a lesson: guess before the explanation.
        case predict
    }

    /// Scroll anchor of the feedback card, for `ScrollViewProxy.scrollTo`.
    static let feedbackID = "question-feedback"

    let question: Question
    let mode: Mode
    let onAnswer: (Int, Double) -> Void

    @State private var selected: Int?
    @State private var shownAt: Date?

    /// - Parameter preselected: show the question as already answered with this choice (no callback).
    init(_ question: Question, mode: Mode = .practice, preselected: Int? = nil,
         onAnswer: @escaping (Int, Double) -> Void) {
        self.question = question
        self.mode = mode
        self.onAnswer = onAnswer
        _selected = State(initialValue: preselected)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            QuestionVisualView(question: question, revealed: selected != nil, markTrumps: marksTrumps)
            ChoiceList(question: question, selected: selected, markTrumps: marksTrumps) { index in
                pick(index)
            }
            if let selected {
                AnswerFeedbackCard(correct: selected == question.correctChoice,
                                   title: verdict(correct: selected == question.correctChoice),
                                   explanation: question.explanation)
                    .id(Self.feedbackID)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if mode == .predict {
                Text("Make your best guess. It's fine to be wrong: guessing first helps the answer stick.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.25), value: selected)
        .onAppear {
            if shownAt == nil { shownAt = .now }
        }
        .sensoryFeedback(trigger: selected) { _, newValue in
            guard let newValue else { return nil }
            return newValue == question.correctChoice ? .success : .error
        }
    }

    @ViewBuilder private var header: some View {
        if mode == .predict {
            Label("Your turn: predict first", systemImage: "lightbulb.fill")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.themColor)
        }
        RichText(question.prompt)
            .font(.title3.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        if let trump = question.trump {
            TrumpBadge(trump: trump)
        }
    }

    /// Scaffolding that fades: trumps get the gold edge only on the easiest questions.
    /// When spotting trumps is the point of the question, the edge would give the answer away,
    /// so it waits for the answer.
    private var marksTrumps: Bool {
        guard question.difficulty <= 1, question.trump != nil else { return false }
        return selected != nil || !asksToSpotTrumps
    }

    /// "Is this a trump?" drills, and the "your turn" questions of the lesson that teaches spotting
    /// trumps (their item id is the lesson's id), e.g. "Which of these cards is a trump?".
    private var asksToSpotTrumps: Bool {
        if question.itemID == SkillID.isTrump.itemID { return true }
        return Curriculum.lesson(id: question.itemID)?.skills.contains(.isTrump) ?? false
    }

    private func verdict(correct: Bool) -> String {
        switch mode {
        case .practice: return correct ? "Correct" : "Not quite"
        case .predict: return correct ? "Good call! Here's why" : "Not this time. Here's why"
        }
    }

    private func pick(_ index: Int) {
        guard selected == nil else { return }
        let seconds = Date.now.timeIntervalSince(shownAt ?? .now)
        selected = index
        onAnswer(index, max(0.1, seconds))
    }
}

// MARK: - Visual

/// The picture above the choices, for every `QuestionVisual` case.
@MainActor
private struct QuestionVisualView: View {
    let question: Question
    /// The question has been answered (a trick's winner may be highlighted).
    let revealed: Bool
    let markTrumps: Bool

    var body: some View {
        switch question.visual {
        case .none:
            EmptyView()
        case let .cards(cards):
            LearnCardRows(cards: cards, trump: question.trump, markTrumps: markTrumps,
                          cardWidth: cards.count <= 4 ? 60 : 48, perRow: 6, spacing: cards.count <= 4 ? 8 : -10,
                          alignment: .center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        case let .trick(plays):
            TrickDiagram(plays: plays, trump: question.trump,
                         winner: revealed ? revealedWinner(in: plays) : nil,
                         markTrumps: markTrumps)
        case let .handAndLead(hand, lead, leader):
            HandAndLeadView(hand: hand, lead: lead, leader: leader, trump: question.trump, markTrumps: markTrumps)
        case let .situation(plays, hand):
            VStack(alignment: .leading, spacing: 14) {
                TrickDiagram(plays: plays, trump: question.trump, markTrumps: markTrumps,
                             nextToPlay: Seats.human)
                LearnHandView(cards: hand, trump: question.trump, markTrumps: markTrumps)
            }
        }
    }

    /// After answering a "who wins?" question, highlight the seat named by the right answer.
    private func revealedWinner(in plays: [Play]) -> Int? {
        guard question.choices.indices.contains(question.correctChoice) else { return nil }
        let answer = question.choices[question.correctChoice].label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return plays.first { play in
            let name = Seats.name(play.player).lowercased()
            return answer == name || answer.hasPrefix(name + " ") || answer.hasPrefix(name + ",")
        }?.player
    }
}

/// "Led by West" with the lead, then the learner's hand.
@MainActor
private struct HandAndLeadView: View {
    let hand: [Card]
    let lead: [Card]
    let leader: Int
    let trump: Trump?
    let markTrumps: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(leader == Seats.human ? "You led" : "Led by \(Seats.name(leader))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                CardRow(cards: lead, cardWidth: 48, spacing: -18, trump: trump, markTrumps: markTrumps)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.felt, Theme.feltDeep], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            LearnHandView(cards: hand, trump: trump, markTrumps: markTrumps)
        }
    }
}

// MARK: - Choices

/// How a choice looks once the question is answered.
private enum ChoiceState: Equatable {
    case idle
    /// The right answer (whether or not it was picked).
    case correct
    /// The learner's wrong pick.
    case wrongPick
    /// Any other choice after answering.
    case faded
}

/// Text choices as full-width buttons; card choices as tappable tiles in a grid.
@MainActor
private struct ChoiceList: View {
    let question: Question
    let selected: Int?
    let markTrumps: Bool
    let onPick: (Int) -> Void

    private var showsCards: Bool { question.choices.contains { !$0.cards.isEmpty } }

    /// Tiles side by side fit up to 5 overlapping cards on a 375-point-wide phone;
    /// longer plays (a 3-pair tractor, a throw) get full-width tiles so nothing spills over.
    private var tileMinimumWidth: CGFloat {
        let most = question.choices.map(\.cards.count).max() ?? 0
        return most > 5 ? 300 : 140
    }

    var body: some View {
        if showsCards {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: tileMinimumWidth), spacing: 10)], spacing: 10) {
                buttons
            }
        } else {
            VStack(spacing: 10) {
                buttons
            }
        }
    }

    private var buttons: some View {
        ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
            Button {
                onPick(index)
            } label: {
                ChoiceLabel(choice: choice, state: state(of: index), trump: question.trump, markTrumps: markTrumps)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(selected == nil)
            .accessibilityAddTraits(selected == index ? .isSelected : [])
        }
    }

    private func state(of index: Int) -> ChoiceState {
        guard let selected else { return .idle }
        if index == question.correctChoice { return .correct }
        if index == selected { return .wrongPick }
        return .faded
    }
}

/// The look of one choice: text, or cards with a caption.
@MainActor
private struct ChoiceLabel: View {
    let choice: Choice
    let state: ChoiceState
    let trump: Trump?
    let markTrumps: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    var body: some View {
        content
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(border, lineWidth: state == .idle || state == .faded ? 1 : 2)
            }
            .opacity(state == .faded ? 0.55 : 1)
            .contentShape(shape)
    }

    @ViewBuilder private var content: some View {
        if choice.cards.isEmpty {
            HStack(spacing: 10) {
                RichText(choice.label)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                stateIcon
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 8) {
                CardRow(cards: choice.cards, cardWidth: 40, spacing: -16, trump: trump, markTrumps: markTrumps)
                HStack(spacing: 4) {
                    stateIcon
                    RichText(choice.label)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 104)
        }
    }

    @ViewBuilder private var stateIcon: some View {
        switch state {
        case .correct:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.correct)
        case .wrongPick:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Theme.wrong)
        case .idle, .faded:
            EmptyView()
        }
    }

    private var fill: Color {
        switch state {
        case .idle, .faded: return Color.secondary.opacity(0.08)
        case .correct: return Theme.correct.opacity(0.15)
        case .wrongPick: return Theme.wrong.opacity(0.15)
        }
    }

    private var border: Color {
        switch state {
        case .idle: return Color.secondary.opacity(0.25)
        case .faded: return Color.secondary.opacity(0.12)
        case .correct: return Theme.correct
        case .wrongPick: return Theme.wrong
        }
    }
}
