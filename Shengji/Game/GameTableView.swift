import SwiftUI
import ShengjiCore

/// Sheets the table can show from its menu.
enum GameTableSheet: String, Identifiable {
    case rules, lastTrick

    var id: String { rawValue }
}

/// The card table: top bar, the four seats with their plays, the coach banner, the action bar
/// and your hand. Presented full screen by `PlayHomeView`.
@MainActor
struct GameTableView: View {
    @Bindable var controller: GameController
    var onExit: () -> Void

    @Environment(LearningStore.self) private var learning
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheet: GameTableSheet? = nil

    var body: some View {
        ZStack {
            GameFeltBackground()
            VStack(spacing: 8) {
                GameTopBar(controller: controller, coachLevel: coachBinding,
                           onShowRules: { sheet = .rules },
                           onShowLastTrick: { sheet = .lastTrick },
                           onQuit: quit)
                GameTableArea(controller: controller)
                    .frame(maxHeight: .infinity)
                GameCoachArea(controller: controller)
                GameActionBar(controller: controller)
                GameHandView(controller: controller)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            resultOverlay
        }
        .sheet(item: $sheet) { item in
            sheetContent(item)
        }
        .onAppear(perform: appear)
        .onDisappear { controller.tearDown() }
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
            // The bots wait while you read the rules or review the last trick.
            if newSheet == nil {
                controller.start()
            } else {
                controller.pause()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: controller.isShowingResult)
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
        }
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
        } else {
            controller.connectLearning(learning)
            controller.coachLevel = learning.coachLevel
        }
        controller.start()
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if controller.stage == .predicting {
                GamePredictionPanel { seat in controller.answerPrediction(seat) }
                    .transition(AnyTransition.opacity)
            } else {
                GameCoachBannerView(message: controller.banner)
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
