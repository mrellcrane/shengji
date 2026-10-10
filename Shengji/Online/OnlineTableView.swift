import SwiftUI
import ShengjiCore

/// An online game's table, full screen: the top bar, the four seats with the trick, the coach banner
/// (with declare buttons while bidding), the action bar and your hand. Draws `OnlineGameModel`.
@MainActor
struct OnlineTableView: View {
    let model: OnlineGameModel
    let onClose: () -> Void

    @Environment(OnlineSession.self) private var session
    @Environment(LearningStore.self) private var learning
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.scenePhase) private var scenePhase

    /// The chat with the coach for this visit to the table (offline in demo scenes).
    @State private var coach = CoachConversation.live()
    @State private var topBarHeight: CGFloat = 96
    @State private var confirmingEnd = false

    var body: some View {
        ZStack {
            GameFeltBackground()
            VStack(spacing: 8) {
                OnlineTopBar(model: model, coachLevel: coachBinding, onClose: onClose,
                             onCoach: { openCoach(explainingHint: false) },
                             onEndGame: { confirmingEnd = true })
                    .background(topBarReader)
                OnlineTableArea(model: model)
                    .frame(maxHeight: .infinity)
                OnlineCoachArea(model: model) { openCoach(explainingHint: true) }
                OnlineActionBar(model: model)
                OnlineHandView(model: model)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            OnlineTableOverlay(model: model, onClose: onClose)
            toastLayer
        }
        .sheet(item: sheetBinding) { item in
            sheetContent(item)
        }
        .confirmationDialog("End this game for everyone?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End game", role: .destructive, action: endGame)
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("It ends for everyone at the table, and can't be undone.")
        }
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: scenePhase) { _, phase in
            // Only a real trip to the background drops the connection: `.inactive` also covers
            // Control Center, a notification banner pulled down and system alerts.
            switch phase {
            case .active: model.setActive(true)
            case .background: model.setActive(false)
            default: break
            }
        }
        .onChange(of: learning.coachLevel) { _, level in
            model.coachLevel = level
        }
    }

    /// Celebrations just under the top bar, held while a sheet covers the table.
    private var toastLayer: some View {
        VStack(spacing: 0) {
            AchievementToastLayer(store: achievements, canShow: model.sheet == nil)
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

    private var sheetBinding: Binding<OnlineTableSheet?> {
        Binding(get: { model.sheet }, set: { model.setSheet($0) })
    }

    @ViewBuilder private func sheetContent(_ item: OnlineTableSheet) -> some View {
        switch item {
        case .coach:
            CoachSheet(conversation: coach)
        case .rules:
            RulesQuickSheet()
        case .whatHappened:
            OnlineWhatHappenedSheet(info: model.whatHappened, players: model.players, trump: model.view?.trump,
                                    lastRound: model.lastRoundSummary) { summary in
                model.setSheet(.roundSummary(summary))
            }
        case let .roundSummary(summary):
            OnlineRoundSummarySheet(summary: summary, players: model.players,
                                    roundNumber: roundNumber(of: summary),
                                    target: model.view?.targetRank ?? model.summary?.targetRank ?? .ace)
        }
    }

    /// The summary in the view is the round before the current one, unless the game ended with it.
    private func roundNumber(of summary: RoundSummary) -> Int {
        guard let view = model.view else { return 1 }
        if view.phase == .finished, view.result == nil || view.result == summary.result { return view.roundNumber }
        return max(1, view.roundNumber - 1)
    }

    private var coachBinding: Binding<CoachLevel> {
        Binding(get: { model.coachLevel },
                set: { level in
                    model.coachLevel = level
                    if !model.isMock { learning.coachLevel = level }
                })
    }

    /// The coach sees the table as it is now (fresh chips and context each time). From a hint's "Why?",
    /// it asks why that hint applies straight away.
    private func openCoach(explainingHint: Bool) {
        guard model.canAskCoach else { return }
        model.prepareCoach(coach)
        if explainingHint, let question = model.explainHintQuestion {
            let lastAsked = coach.messages.last(where: { $0.role == .user })?.sentText
            if lastAsked != question.prompt { coach.ask(question) }
        }
        model.setSheet(.coach)
    }

    private func appear() {
        model.coachLevel = learning.coachLevel
        let store = achievements
        let progress = learning
        let online = session
        if !model.isMock {
            model.onMoves = { [weak store] events in store?.record(events) }
            model.onGameProgress = { [weak store] level, won in
                store?.recordGameProgress(teamLevel: level, wonGame: won)
            }
            model.onMistake = { [weak progress] skill in progress?.noteGameMistake(skill) }
            model.onRoundFinished = { [weak progress] in progress?.recordRoundPlayed() }
            model.onGameFinished = { [weak progress] won in progress?.recordGameFinished(won: won) }
        }
        model.onSummary = { [weak online] summary in online?.noteSummary(summary) }
        model.onSignedOut = { [weak online] in online?.tableReportedSignedOut() }
        online.activeTable = model
        online.push.visibleGameID = model.gameID
        model.start()
    }

    private func disappear() {
        model.stop()
        if session.activeTable === model { session.activeTable = nil }
        if session.push.visibleGameID == model.gameID { session.push.visibleGameID = nil }
        achievements.clearToasts()
    }

    private func endGame() {
        Task {
            if await session.deleteGame(id: model.gameID) {
                onClose()
            } else if !model.isGone, let message = session.takeErrorMessage() {
                // The games list (where the session shows problems) is hidden under the table.
                model.showNotice(message)
            }
        }
    }
}

/// Over the table: loading, a game that can't be shown, or the game-over card.
@MainActor
struct OnlineTableOverlay: View {
    let model: OnlineGameModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            if model.view == nil {
                loading
            } else if model.isGone {
                closed
            } else if model.isGameOver, let headline = model.gameOverHeadline {
                gameOver(headline)
            }
        }
    }

    @ViewBuilder private var loading: some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
        if let message = model.loadError {
            OnlineTableCard(title: "Can't open this table", message: message) {
                if !model.isGone {
                    Button("Try again") { Task { await model.refresh() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.felt)
                }
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .tint(Color.white)
                Text("Opening the table")
                    .foregroundStyle(Color.white)
            }
        }
    }

    @ViewBuilder private var closed: some View {
        Color.black.opacity(0.45)
            .ignoresSafeArea()
        OnlineTableCard(title: "This table is closed", message: model.loadError ?? "This game has ended.") {
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(Theme.felt)
        }
    }

    private func gameOver(_ headline: String) -> some View {
        VStack {
            Spacer()
            OnlineTableCard(title: headline, message: finalLevels) {
                if let summary = model.lastRoundSummary {
                    Button("Last round") { model.setSheet(.roundSummary(summary)) }
                        .buttonStyle(.bordered)
                }
                Button("Close", action: onClose)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.felt)
            }
            .padding(.bottom, 24)
        }
    }

    private var finalLevels: String {
        let us = model.level(of: 0)?.label ?? "?"
        let them = model.level(of: 1)?.label ?? "?"
        return "Final levels: Us \(us), Them \(them). Start a rematch from your club."
    }
}

/// A rounded card with a title, a message and buttons.
@MainActor
struct OnlineTableCard<Buttons: View>: View {
    let title: String
    let message: String
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                buttons
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}
