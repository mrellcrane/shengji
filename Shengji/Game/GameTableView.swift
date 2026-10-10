import SwiftUI
import ShengjiCore

/// Sheets the table can show from its menu, the coach button and the hint banner.
enum GameTableSheet: String, Identifiable {
    case rules, lastTrick, coach

    var id: String { rawValue }
}

/// The card table: top bar, the four seats with their plays, the coach banner, the action bar
/// and your hand. Presented full screen by `PlayHomeView`.
@MainActor
struct GameTableView: View {
    @Bindable var controller: GameController
    var onExit: () -> Void

    @Environment(LearningStore.self) private var learning
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: GameTableSheet? = nil
    /// The chat with the coach, kept for the whole visit to the table.
    @State private var coach: CoachConversation
    /// Measured, so celebration toasts sit just under the top bar.
    @State private var topBarHeight: CGFloat = 76
    /// The `coach` demo scene opens its sheet once, not again each time the table reappears.
    @State private var demoCoachOpened = false
    /// The `coach` demo scene opens the sheet on this canned chat.
    private let demoCoach: CoachConversation?

    init(controller: GameController, demoCoach: CoachConversation? = nil, onExit: @escaping () -> Void) {
        _controller = Bindable(wrappedValue: controller)
        self.onExit = onExit
        self.demoCoach = demoCoach
        _coach = State(initialValue: demoCoach ?? CoachConversation.live())
    }

    var body: some View {
        ZStack {
            GameFeltBackground()
            VStack(spacing: 8) {
                GameTopBar(controller: controller, coachLevel: coachBinding,
                           onShowRules: { sheet = .rules },
                           onShowLastTrick: { sheet = .lastTrick },
                           onAskCoach: { openCoach(explainingHint: false) },
                           onQuit: quit)
                    .background(topBarReader)
                GameTableArea(controller: controller)
                    .frame(maxHeight: .infinity)
                GameCoachArea(controller: controller) {
                    openCoach(explainingHint: true)
                }
                GameActionBar(controller: controller)
                GameHandView(controller: controller)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            resultOverlay
            toastLayer
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .onAppear(perform: appear)
        .onDisappear {
            controller.tearDown()
            achievements.clearToasts()
        }
        .task {
            await openDemoCoachIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if sheet == nil { controller.start() }
            } else {
                controller.saveNow()
                controller.pause()
            }
        }
        .onChange(of: learning.coachLevel) { _, level in
            if !controller.isDemo { controller.coachLevel = level }
        }
        .onChange(of: sheet) { _, newSheet in
            // The bots wait while you read the rules, review the last trick or talk to the coach.
            if newSheet == nil {
                controller.start()
            } else {
                controller.pause()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controller.isShowingResult)
    }

    /// Celebrations just under the top bar: above the table and the result panel (whose zIndex is 1),
    /// never over your hand. They wait while you guess who won the trick (they would give the answer
    /// away) and while a sheet covers the table (so none time out unseen).
    private var toastLayer: some View {
        VStack(spacing: 0) {
            AchievementToastLayer(store: achievements, canShow: controller.stage != .predicting && sheet == nil)
                .padding(.top, topBarHeight + 4)
                .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .zIndex(2)
    }

    private var topBarReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { topBarHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in
                    topBarHeight = height
                }
        }
    }

    @ViewBuilder private var resultOverlay: some View {
        if controller.isShowingResult, let summary = controller.roundSummary {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {}
                RoundResultView(summary: summary,
                                roundNumber: controller.game.roundsPlayed,
                                isDemo: controller.isDemo,
                                onNextRound: { controller.startNextRound() },
                                onNewGame: { controller.startNewGame() },
                                onViewTable: { controller.isShowingResult = false },
                                onLeave: quit)
            }
            .transition(reduceMotion ? AnyTransition.opacity
                                     : AnyTransition.move(edge: .bottom).combined(with: AnyTransition.opacity))
            .zIndex(1)
        }
    }

    @ViewBuilder private func sheetContent(_ item: GameTableSheet) -> some View {
        switch item {
        case .rules:
            RulesQuickSheet()
        case .lastTrick:
            LastTrickView(trick: controller.round.tricks.last,
                          trickNumber: controller.round.tricks.count,
                          trump: controller.round.trump,
                          explanation: lastTrickExplanation)
        case .coach:
            CoachSheet(conversation: coach)
        }
    }

    /// Opens the coach on the table as it is now (fresh chips and context each time). From the hint
    /// banner's "Why?", it asks why that hint applies straight away.
    private func openCoach(explainingHint: Bool) {
        guard controller.canAskCoach else { return }
        // Hold the bots now, not only once the sheet's onChange runs: a bot acting in between would
        // leave the coach looking at a table that has already moved on.
        controller.pause()
        if demoCoach == nil {
            controller.prepareCoach(coach)
            if explainingHint, let question = controller.explainHintQuestion {
                let lastAsked = coach.messages.last(where: { $0.role == .user })?.sentText
                if lastAsked != question.prompt {
                    coach.ask(question)
                }
            }
        }
        sheet = .coach
    }

    /// The `coach` demo scene: the sheet opens over the table once, after the full-screen table has
    /// finished presenting (UIKit drops a sheet presented while another presentation is in flight).
    private func openDemoCoachIfNeeded() async {
        guard demoCoach != nil, !demoCoachOpened, sheet == nil else { return }
        demoCoachOpened = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled, sheet == nil else { return }
        controller.pause()
        sheet = .coach
    }

    private var lastTrickExplanation: String? {
        guard let trick = controller.round.tricks.last else { return nil }
        return GameCoachText.trickExplanation(trick, trump: controller.round.trump, coach: .guided, detailed: true,
                                              winnerIsDefender: controller.round.isDefender(trick.winner),
                                              isLastTrick: false)?.text
    }

    private var coachBinding: Binding<CoachLevel> {
        Binding(get: { controller.coachLevel },
                set: { level in
                    controller.coachLevel = level
                    if !controller.isDemo { learning.coachLevel = level }
                })
    }

    private func appear() {
        if controller.isDemo {
            controller.disconnectLearning()
            controller.disconnectAchievements()
        } else {
            controller.connectLearning(learning)
            controller.connectAchievements(achievements)
            controller.coachLevel = learning.coachLevel
        }
        if sheet == nil { controller.start() }
    }

    private func quit() {
        controller.saveAndQuit()
        onExit()
    }
}

/// Felt-green table background.
@MainActor
struct GameFeltBackground: View {
    var body: some View {
        RadialGradient(colors: [Theme.felt, Theme.feltDeep], center: .center, startRadius: 40, endRadius: 520)
            .ignoresSafeArea()
    }
}

/// The coach banner, or the "who wins?" prompt, plus declare buttons while dealing.
@MainActor
struct GameCoachArea: View {
    let controller: GameController
    /// "Why?" under a hint: ask the coach why that hint applies.
    var onWhy: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if controller.stage == .predicting {
                GamePredictionPanel { seat in controller.answerPrediction(seat) }
                    .transition(AnyTransition.opacity)
            } else {
                GameCoachBannerView(message: controller.banner,
                                    onWhy: controller.isShowingHint && controller.canAskCoach ? onWhy : nil)
            }
            if !controller.availableDeclarations.isEmpty {
                GameDeclareRow(declarations: controller.availableDeclarations,
                               current: controller.round.declaration) { declaration in
                    controller.declare(declaration)
                }
                .transition(AnyTransition.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controller.stage)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controller.banner)
    }
}
