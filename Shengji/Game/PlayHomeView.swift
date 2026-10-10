import SwiftUI
import ShengjiCore

/// The Play tab: start or continue a game against three bots, your moves (achievements), and how much
/// help you get. For the `game`, `dealing`, `result` and `coach` demo scenes it opens the table straight
/// away from an in-memory game (seed 7) that never touches the saved game; `achievements` opens the badges.
@MainActor
struct PlayHomeView: View {
    let demoScene: DemoScene?

    init(demoScene: DemoScene? = nil) {
        self.demoScene = demoScene
    }

    @Environment(LearningStore.self) private var learning
    @Environment(AchievementStore.self) private var achievements
    @AppStorage("play.botSpeed") private var botSpeed: GameBotSpeed = .normal
    @AppStorage("play.predictWinner") private var predictionsOn: Bool = true
    @AppStorage("play.gameLength") private var gameLength: GameLengthOption = .toAce
    @AppStorage("play.moveCelebrations") private var celebrationsOn: Bool = true

    @State private var activeGame: GameController? = nil
    @State private var savedGame: SavedGame? = nil
    @State private var confirmingNewGame = false
    @State private var demoOpened = false
    @State private var showsAchievements = false

    /// Screenshot scenes never read or write the real saved game (games started there live in memory).
    private var isDemoMode: Bool { demoScene != nil }

    private var store: SavedGameStore? { isDemoMode ? nil : SavedGameStore.standard }

    var body: some View {
        NavigationStack {
            Form {
                PlayHomeHeader()
                gameSection
                movesSection
                coachSection
                tableSection
            }
            .navigationTitle("Play")
            .navigationDestination(isPresented: $showsAchievements) {
                AchievementsView(category: .moves)
            }
        }
        .fullScreenCover(item: $activeGame, onDismiss: refreshSavedGame) { controller in
            GameTableView(controller: controller, demoCoach: demoScene == .coach ? CoachConversation.demo() : nil) {
                activeGame = nil
            }
            .environment(learning)
            .environment(achievements)
        }
        .onChange(of: celebrationsOn) { _, isOn in
            if !isOn { achievements.clearToasts() }
        }
        .confirmationDialog("Start a new game?", isPresented: $confirmingNewGame, titleVisibility: .visible) {
            Button("New game", role: .destructive) { startNewGame() }
            Button("Keep my saved game", role: .cancel) {}
        } message: {
            Text("Your saved game will be replaced.")
        }
        .onAppear(perform: refreshSavedGame)
        .task { await openDemoIfNeeded() }
    }

    // MARK: Sections

    private var gameSection: some View {
        Section {
            if let saved = savedGame {
                Button {
                    continueGame(saved)
                } label: {
                    PlayHomeActionLabel(title: "Continue", subtitle: "\(saved.summaryLine) · \(saved.targetLine)",
                                        systemImage: "play.fill", prominent: true)
                }
            }
            Button {
                if savedGame != nil {
                    confirmingNewGame = true
                } else {
                    startNewGame()
                }
            } label: {
                PlayHomeActionLabel(title: "New game", subtitle: "You and Partner against East and West",
                                    systemImage: "plus", prominent: savedGame == nil)
            }
        }
    }

    /// "Your moves": overall badge progress and the latest badges, leading to the achievements.
    private var movesSection: some View {
        Section {
            NavigationLink {
                AchievementsView(category: .moves)
            } label: {
                AchievementSummaryCard(title: "Your moves", systemImage: "star.circle.fill",
                                       fraction: achievements.progress.overallFraction,
                                       earned: overallCounts.earned, possible: overallCounts.possible,
                                       recent: achievements.recentlyEarned(limit: 3),
                                       emptyText: "Ruff, feed your partner points, hold the deal: the moves you make at the table earn badges here.")
            }
        }
    }

    private var overallCounts: (earned: Int, possible: Int) {
        let moves = achievements.tierCounts(in: .moves)
        let journey = achievements.tierCounts(in: .journey)
        return (moves.earned + journey.earned, moves.possible + journey.possible)
    }

    private var coachSection: some View {
        Section {
            Picker("Coach level", selection: coachBinding) {
                ForEach(CoachLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text(learning.coachLevel.blurb)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Coach")
        } footer: {
            Text("New to Shengji? Start in Guided. Move to Coached once following suit feels easy, then try Solo. Less help as you improve makes the learning stick.")
        }
    }

    private var tableSection: some View {
        Section {
            Picker("Bot speed", selection: $botSpeed) {
                ForEach(GameBotSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Predict the winner", isOn: $predictionsOn)
            Toggle("Move celebrations", isOn: $celebrationsOn)
            Picker("Play to", selection: $gameLength) {
                ForEach(GameLengthOption.allCases) { length in
                    Text(length.title).tag(length)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Table")
        } footer: {
            Text("Predict the winner: in Guided and Coached you'll sometimes guess who wins a trick before it's shown. Guessing first helps you remember. Move celebrations: a quick cheer when you pull off a named move, like a ruff. \(gameLength.detail) Game length applies to new games.")
        }
    }

    private var coachBinding: Binding<CoachLevel> {
        Binding(get: { learning.coachLevel }, set: { learning.coachLevel = $0 })
    }

    // MARK: Actions

    private func refreshSavedGame() {
        savedGame = store?.load()
    }

    private func configure(_ controller: GameController) {
        controller.speed = botSpeed
        controller.predictionsEnabled = predictionsOn
        controller.coachLevel = learning.coachLevel
    }

    private func startNewGame() {
        let settings = GameSettings(startRank: .two, targetRank: gameLength.targetRank)
        let controller = GameController.newGame(settings: settings, seed: UInt64.random(in: UInt64.min...UInt64.max),
                                                persistence: store, isDemo: isDemoMode, coachLevel: learning.coachLevel)
        configure(controller)
        savedGame = nil
        activeGame = controller
    }

    private func continueGame(_ saved: SavedGame) {
        let controller = GameController.resume(saved, persistence: store, coachLevel: learning.coachLevel)
        configure(controller)
        activeGame = controller
    }

    @MainActor
    private func openDemoIfNeeded() async {
        guard let scene = demoScene, scene.isGameScene, !demoOpened else { return }
        demoOpened = true
        // Let the tab finish appearing before presenting the table (or the badges) over it.
        try? await Task.sleep(nanoseconds: 300_000_000)
        if scene == .achievements {
            showsAchievements = true
        } else {
            activeGame = GameController.demo(scene)
        }
    }
}

/// Title row of the Play tab.
@MainActor
private struct PlayHomeHeader: View {
    var body: some View {
        Section {
            HStack(spacing: 14) {
                CardRow(cards: [Card(.ace, .spades), Card(.king, .hearts), .bigJoker()], cardWidth: 34, spacing: -16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("升级 Shengji")
                        .font(.title3.weight(.bold))
                    Text("Practise against three friendly bots. Your partner sits opposite you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A big tappable row: icon, title and a short subtitle.
@MainActor
private struct PlayHomeActionLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var prominent: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(prominent ? Color.white : Theme.felt)
                .frame(width: 36, height: 36)
                .background(Circle().fill(prominent ? Theme.felt : Theme.felt.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
