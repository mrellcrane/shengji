import Foundation
import Observation
import ShengjiCore

/// Runs one game at the table: the engine state, the bots, the coach banner and every
/// piece of UI state the Play tab draws. SwiftUI-free so it can be type-checked and driven headless.
///
/// Bots act from a single driver `Task` that sleeps between actions (scaled by `speed`, or by
/// `delayScaleOverride` = 0 for tests). Every user action restarts the driver, so there is never
/// more than one live driver and a stale sleep never delays the next action.
@MainActor
@Observable
final class GameController: Identifiable {
    // MARK: Engine state

    private(set) var game: GameState
    private(set) var round: Round
    @ObservationIgnored private var rng: SeededGenerator

    // MARK: Settings

    var coachLevel: CoachLevel
    var predictionsEnabled: Bool
    var speed: GameBotSpeed
    /// Replaces the speed's delay scale; 0 means no delays at all (tests, headless runs).
    @ObservationIgnored var delayScaleOverride: Double?
    /// Seats played by bots: everyone but you normally (East, Partner and West at a table of four);
    /// demos and headless runs add seat 0.
    var botSeats: Set<Int>
    /// Demo controllers live in memory only: they never save and never touch the saved game.
    let isDemo: Bool
    /// When true the bots and the dealer wait (used by the dealing demo). Any action of yours resumes.
    var autoplayPaused = false

    // MARK: UI state

    private(set) var stage: GameStage
    /// Selected card ids in your hand.
    private(set) var selection: Set<Int> = []
    private(set) var banner: GameCoachMessage?
    private(set) var prediction: GamePredictionPrompt?
    private(set) var roundSummary: RoundSummary?
    /// The round result panel is visible (you can hide it to look at the table).
    var isShowingResult = false
    private(set) var isBotThinking = false
    /// Kitty cards you just picked up as dealer (marked "new" while you bury).
    private(set) var newKittyCardIDs: Set<Int> = []
    /// Trick number (1-based, this round) of the last "who wins?" prompt.
    private(set) var lastPredictionTrick: Int?
    /// Set if the table cannot continue (an engine error); the driver stops.
    private(set) var stallMessage: String?
    /// The hint ladder for the position it was asked in (see `activeHint`).
    private(set) var hintLadder: HintLadder?
    /// The banner message showing the current hint step (for the "Why?" chip).
    private(set) var hintBannerID: UUID?
    /// Your last rejected play or bury, for the coach (see `lastIllegal`).
    private(set) var illegalAttempt: IllegalAttempt?

    // MARK: Learning hooks (wired to LearningStore by the views; nil in demos and tests)

    @ObservationIgnored var onMistake: (@MainActor (SkillID) -> Void)?
    @ObservationIgnored var onPrediction: (@MainActor (_ correct: Bool, _ seconds: Double) -> Void)?
    @ObservationIgnored var onRoundFinished: (@MainActor () -> Void)?
    @ObservationIgnored var onGameFinished: (@MainActor (_ won: Bool) -> Void)?

    // MARK: Achievement hooks (wired to AchievementStore by the views; nil in demos and tests)

    /// Moves you made: after each trick, after the deal closes, and when the round is scored.
    @ObservationIgnored var onMoves: (@MainActor ([MoveEvent]) -> Void)?
    /// After each scored round: your team's level and whether you just won the game.
    @ObservationIgnored var onGameProgress: (@MainActor (_ teamLevel: Rank, _ wonGame: Bool) -> Void)?

    // MARK: Private bookkeeping

    private let persistence: SavedGameStore?
    @ObservationIgnored private var driverTask: Task<Void, Never>?
    @ObservationIgnored private var driverGeneration = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var pendingSummary: RoundSummary?
    @ObservationIgnored private var roundRecorded = false
    @ObservationIgnored private var longPause = false
    @ObservationIgnored private var hadDeclarationOption = false
    @ObservationIgnored private var buryPromptPrefix: String?
    private let buryPromptID = UUID()
    /// Where the hint ladder and the illegal attempt were recorded; they lapse once the position moves on.
    @ObservationIgnored private var hintPosition: TablePosition?
    @ObservationIgnored private var illegalPosition: TablePosition?
    /// "Your throw failed…" text, added to the explanation when the trick ends (`isYours`: warning style).
    @ObservationIgnored private var throwNote: (text: String, isYours: Bool)?

    /// Base delays in seconds at Normal speed.
    enum Delay {
        static let deal = 0.035
        static let botPlay = 0.7
        static let botBury = 2.2
        static let botRespond = 0.9
        static let windowAutoContinue = 4.0
        static let trickPause = 1.3
        static let trickPauseAfterPrediction = 2.4
    }

    // MARK: Creating

    init(game: GameState, round: Round, rng: SeededGenerator, persistence: SavedGameStore?, isDemo: Bool,
         coachLevel: CoachLevel = .guided, speed: GameBotSpeed = .normal, predictionsEnabled: Bool = true) {
        self.game = game
        self.round = round
        self.rng = rng
        self.persistence = isDemo ? nil : persistence
        self.isDemo = isDemo
        self.coachLevel = coachLevel
        self.speed = speed
        self.predictionsEnabled = predictionsEnabled
        self.botSeats = Set(1..<round.players)
        self.stage = GameController.stage(for: round)
        restoreUIState()
    }

    /// A fresh game. Replaces (deletes) any saved game when `persistence` is given.
    static func newGame(settings: GameSettings, seed: UInt64, persistence: SavedGameStore?,
                        isDemo: Bool = false, coachLevel: CoachLevel = .guided) -> GameController {
        var rng = SeededGenerator(seed: seed)
        let game = GameState(settings: settings)
        let round = game.makeRound(rng: &rng)
        if !isDemo { persistence?.delete() }
        let controller = GameController(game: game, round: round, rng: rng, persistence: persistence,
                                        isDemo: isDemo, coachLevel: coachLevel)
        controller.save()
        return controller
    }

    /// Continues a saved game.
    static func resume(_ saved: SavedGame, persistence: SavedGameStore?, coachLevel: CoachLevel = .guided) -> GameController {
        let controller = GameController(game: saved.game, round: saved.round, rng: saved.rng,
                                        persistence: persistence, isDemo: false, coachLevel: coachLevel,
                                        speed: saved.botSpeed, predictionsEnabled: saved.predictionsEnabled)
        controller.lastPredictionTrick = saved.lastPredictionTrick
        return controller
    }

    nonisolated static func stage(for round: Round) -> GameStage {
        switch round.phase {
        case .dealing: return round.isDealingComplete ? .declareWindow : .dealing
        case .burying: return .burying
        case .playing: return .playing
        case .finished: return .roundOver
        }
    }

    /// Banner and flags that match `stage` after creating or loading.
    private func restoreUIState() {
        switch stage {
        case .dealing:
            banner = GameCoachMessage(GameCoachText.dealingIntro(round: round, game: game, coach: coachLevel),
                                      concept: "Declaring")
        case .declareWindow:
            if let declaration = round.declaration, declaration.player == Seats.human, !isBot(Seats.human) {
                // Saved just after you declared (the stage isn't saved): the bots still get their answer.
                stage = .botsRespond
                banner = GameCoachMessage(GameCoachText.declarationLine(declaration, players: players), concept: "Declaring",
                                          kind: .success)
            } else {
                openDeclareWindow(messages: [])
            }
        case .burying:
            if let dealer = round.dealer, !isBot(dealer) {
                newKittyCardIDs = Set(round.kitty.map(\.id))
                buryPromptPrefix = GameCoachText.shortDealerReason(round: round, game: game)
                refreshBuryPrompt()
            } else {
                banner = GameCoachMessage(GameCoachText.join([GameCoachText.dealerExplanation(round: round, game: game),
                                                              kittyPickupLine]),
                                          concept: "The kitty")
            }
        case .playing:
            if round.tricks.isEmpty && round.currentTrick.isEmpty {
                banner = GameCoachMessage(GameCoachText.sentence(
                    "\(GameCoachText.subject(round.leader, "lead", "leads", players: players)) the first trick"))
            } else {
                banner = GameCoachMessage("Welcome back! This is trick \(round.tricks.count + 1).")
            }
        case .roundOver:
            roundRecorded = true
            roundSummary = game.history.last
            isShowingResult = roundSummary != nil
        case .botsRespond, .trickPause, .predicting:
            break
        }
    }

    // MARK: Derived state for the views

    var delayScale: Double { delayScaleOverride ?? speed.delayScale }

    func isBot(_ seat: Int) -> Bool { botSeats.contains(seat) }

    /// Seats at this table (4, 6 or 8).
    var players: Int { round.players }

    /// Every seat, you first.
    var seats: [Int] { Seats.all(players: players) }

    /// How the table names a seat: "East", "Partner" with 4 players, compass points with more.
    func name(_ seat: Int) -> String { Seats.name(seat, players: players) }

    /// "East picks up the kitty and buries 8 cards." for this table.
    private var kittyPickupLine: String {
        GameCoachText.kittyPickupLine(dealer: round.dealer, kittySize: round.kittySize, players: players)
    }

    func hand(of seat: Int) -> [Card] {
        round.hands.indices.contains(seat) ? round.hands[seat] : []
    }

    /// Your hand, plain suits on the left and trumps on the right.
    var hand: [Card] { round.trump.sorted(hand(of: Seats.human)) }

    var selectedCards: [Card] { hand.filter { selection.contains($0.id) } }

    func cardCount(of seat: Int) -> Int { hand(of: seat).count }

    func level(of team: Int) -> Rank {
        game.levels.indices.contains(team) ? game.levels[team] : game.settings.startRank
    }

    /// The level shown in the top bar. The round is scored as soon as its last trick lands, so while
    /// you are asked who won that trick the levels from before the round are shown (the new ones
    /// would give the answer away).
    func displayedLevel(of team: Int) -> Rank {
        if stage == .predicting, let summary = pendingSummary, summary.levelsBefore.indices.contains(team) {
            return summary.levelsBefore[team]
        }
        return level(of: team)
    }

    var isGameOver: Bool { game.winner != nil }

    var isFirstRound: Bool { game.history.isEmpty }

    var dealtCount: Int { round.hands.reduce(0) { $0 + $1.count } - (round.phase == .dealing ? 0 : round.kittySize) }

    /// Cards dealt to the players (100 with 4 players).
    var cardsToDeal: Int { round.handSize * players }

    /// Points the defenders need to take over the deal: 40 per deck (80 with 4 players).
    var takeoverThreshold: Int { Scoring.takeoverThreshold(decks: round.table.decks) }

    /// Points in all the cards: 100 per deck.
    var totalPoints: Int { round.table.totalPoints }

    /// False while dealing before anyone has declared (the suit is still open).
    var isTrumpSet: Bool { !(round.phase == .dealing && round.declaration == nil) }

    /// Defenders' points so far. While you are asked who won the trick on the table, its points are
    /// left out so the score in the top bar doesn't give the answer away.
    var defenderPoints: Int {
        let total = round.defenderTrickPoints
        guard stage == .predicting, let trick = round.tricks.last, round.isDefender(trick.winner) else { return total }
        return max(0, total - trick.points)
    }

    /// The previous trick can be reviewed (not while you are predicting its winner).
    var canReviewLastTrick: Bool { !round.tricks.isEmpty && stage != .predicting }

    var isHumanTurn: Bool {
        stage == .playing && round.turn == Seats.human && !isBot(Seats.human)
    }

    var isHumanBurying: Bool {
        stage == .burying && round.dealer == Seats.human && !isBot(Seats.human)
    }

    var availableDeclarations: [Declaration] {
        guard stage == .dealing || stage == .declareWindow, !isBot(Seats.human) else { return [] }
        return round.availableDeclarations(for: Seats.human)
    }

    /// Lead: at least one card. Follow: exactly as many cards as were led.
    var isPlausiblePlay: Bool {
        let lead = round.currentLead
        return lead.isEmpty ? !selection.isEmpty : selection.count == lead.count
    }

    var canPlay: Bool { isHumanTurn && isPlausiblePlay }

    var canBury: Bool { isHumanBurying && selection.count == round.kittySize }

    /// Hints are offered in Guided and Coached.
    var hintsAvailable: Bool { coachLevel != .solo }

    var canHint: Bool { hintsAvailable && (isHumanTurn || isHumanBurying) }

    /// Guided marks trumps with the gold edge.
    var markTrumps: Bool { coachLevel == .guided }

    /// Guided: when you are following and hold enough cards of the led group, the others are dimmed.
    var dimmedCardIDs: Set<Int> {
        guard coachLevel == .guided, isHumanTurn, let first = round.currentLead.first else { return [] }
        let trump = round.trump
        let group = trump.group(first)
        let mine = hand(of: Seats.human)
        let inGroup = mine.filter { trump.group($0) == group }
        guard inGroup.count >= round.currentLead.count else { return [] }
        return Set(mine.filter { trump.group($0) != group }.map(\.id))
    }

    /// The trick in the middle of the table.
    var trickDisplay: TableTrickDisplay {
        switch stage {
        case .trickPause, .roundOver:
            guard let t = round.tricks.last else { return .empty }
            return TableTrickDisplay(plays: t.plays, winner: t.winner, isFinished: true, points: t.points)
        case .predicting:
            guard let t = round.tricks.last else { return .empty }
            return TableTrickDisplay(plays: t.plays, winner: nil, isFinished: true, points: t.points)
        case .playing:
            let plays = round.currentTrick
            return TableTrickDisplay(plays: plays, winner: nil, isFinished: false,
                                     points: plays.flatMap(\.cards).points)
        case .dealing, .declareWindow, .botsRespond, .burying:
            return .empty
        }
    }

    /// Guided only: who is winning the trick in progress.
    var leadingSeat: Int? {
        guard coachLevel == .guided, stage == .playing, round.currentTrick.count >= 2 else { return nil }
        let index = Rules.winningIndex(round.currentTrick, trump: round.trump)
        return round.currentTrick.indices.contains(index) ? round.currentTrick[index].player : nil
    }

    /// Whose action the table is waiting for.
    var turnSeat: Int? {
        switch stage {
        case .playing: return round.turn
        case .burying: return round.dealer
        case .dealing, .declareWindow, .botsRespond, .trickPause, .predicting, .roundOver: return nil
        }
    }

    func role(of seat: Int) -> GameSeatRole? {
        guard let dealer = round.dealer else { return nil }
        if seat == dealer { return .dealer }
        return Seats.team(of: seat) == Seats.team(of: dealer) ? .declarer : .defender
    }

    func seatInfo(_ seat: Int) -> GameSeatInfo {
        let turn = turnSeat
        let display = trickDisplay
        return GameSeatInfo(seat: seat, name: name(seat), team: Seats.team(of: seat),
                            cardCount: cardCount(of: seat), role: role(of: seat),
                            isTurn: turn == seat, isThinking: isBotThinking && turn == seat,
                            isTrickWinner: display.winner == seat, isLeading: leadingSeat == seat,
                            shortName: Seats.shortName(seat, players: players))
    }

    var primaryAction: GamePrimaryAction {
        switch stage {
        case .dealing: return autoplayPaused && !isBot(Seats.human) ? .resumeDeal : .none
        case .botsRespond, .predicting: return .none
        case .declareWindow: return isBot(Seats.human) ? .none : .continueDeal
        case .burying: return isHumanBurying ? .bury(count: selection.count, enabled: canBury) : .none
        case .playing: return isHumanTurn ? .play(enabled: canPlay) : .none
        case .trickPause: return .nextTrick
        case .roundOver: return isShowingResult ? .none : .showResult
        }
    }

    /// Short status next to the main button.
    var statusText: String {
        switch stage {
        case .dealing:
            return autoplayPaused ? "Dealing paused" : "Dealing \(dealtCount)/\(cardsToDeal)"
        case .declareWindow:
            return availableDeclarations.isEmpty ? "All cards dealt" : "Last chance to declare"
        case .botsRespond:
            return "Others may respond…"
        case .burying:
            if isHumanBurying { return "Pick \(round.kittySize) to bury" }
            return "\(round.dealer.map(name) ?? "Dealer") is burying…"
        case .playing:
            if isHumanTurn {
                let lead = round.currentLead
                return lead.isEmpty ? "Your lead" : "Play \(lead.count) card\(lead.count == 1 ? "" : "s")"
            }
            if let turn = round.turn { return "\(name(turn)) to play" }
            return ""
        case .trickPause:
            return "Tap the table to go on"
        case .predicting:
            return "Who wins?"
        case .roundOver:
            return isGameOver ? "Game over" : "Round over"
        }
    }

    // MARK: Driver

    private enum DriverStep: Equatable {
        case dealCard
        case closeWindow
        case botsRespond
        case botBury
        case botPlay(Int)
        case endTrickPause

        var isBotAction: Bool {
            switch self {
            case .botsRespond, .botBury, .botPlay: return true
            case .dealCard, .closeWindow, .endTrickPause: return false
            }
        }
    }

    /// What the table does next on its own, and after how long (seconds at Normal speed).
    private func plannedStep() -> (step: DriverStep, delay: Double)? {
        guard !autoplayPaused, stallMessage == nil else { return nil }
        switch stage {
        case .dealing:
            return (.dealCard, Delay.deal)
        case .declareWindow:
            if isBot(Seats.human) { return (.closeWindow, 0) }
            if round.availableDeclarations(for: Seats.human).isEmpty { return (.closeWindow, Delay.windowAutoContinue) }
            return nil
        case .botsRespond:
            return (.botsRespond, Delay.botRespond)
        case .burying:
            guard let dealer = round.dealer, isBot(dealer) else { return nil }
            return (.botBury, Delay.botBury)
        case .playing:
            guard let turn = round.turn, isBot(turn) else { return nil }
            return (.botPlay(turn), Delay.botPlay)
        case .trickPause:
            return (.endTrickPause, longPause ? Delay.trickPauseAfterPrediction : Delay.trickPause)
        case .predicting, .roundOver:
            return nil
        }
    }

    private func perform(_ step: DriverStep) {
        switch step {
        case .dealCard: dealOne()
        case .closeWindow: finishDealingNow(prefix: nil)
        case .botsRespond: botsRespond()
        case .botBury: botBury()
        case let .botPlay(seat): botPlay(seat)
        case .endTrickPause: endTrickPause()
        }
    }

    /// Starts (or resumes) the bots. Call when the table appears.
    func start() {
        isRunning = true
        restartDriver()
    }

    /// Holds the bots while a sheet is open over the table; `start()` resumes.
    func pause() { tearDown() }

    /// Lets the bots and the dealer carry on after `autoplayPaused` (the dealing demo stops mid-deal).
    func resumeAutoplay() {
        guard autoplayPaused else { return }
        autoplayPaused = false
        restartDriver()
    }

    /// Stops the bots. Call when the table goes away.
    func tearDown() {
        isRunning = false
        driverGeneration &+= 1
        driverTask?.cancel()
        driverTask = nil
        setThinking(false)
    }

    /// Cancels any running driver and starts a new one for the current state.
    private func restartDriver() {
        driverTask?.cancel()
        driverTask = nil
        driverGeneration &+= 1
        guard isRunning else { return }
        let generation = driverGeneration
        driverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let planned = self?.plannedStep() else { break }
                let seconds = planned.delay * (self?.delayScale ?? 0)
                self?.setThinking(planned.step.isBotAction)
                if seconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                } else {
                    await Task.yield()
                }
                if Task.isCancelled { break }
                guard let self else { break }
                // The state may have changed while sleeping; only act if the same step is still due.
                guard let current = self.plannedStep(), current.step == planned.step else { continue }
                self.perform(current.step)
            }
            self?.driverFinished(generation: generation)
        }
    }

    private func driverFinished(generation: Int) {
        guard generation == driverGeneration else { return }
        driverTask = nil
        setThinking(false)
    }

    private func setThinking(_ value: Bool) {
        if isBotThinking != value { isBotThinking = value }
    }

    /// Runs the table without delays or tasks until nothing more happens on its own, `stop` returns true,
    /// or `maxSteps` is reached. Used by demos and the headless check. Returns the number of steps.
    @discardableResult
    func advanceSynchronously(maxSteps: Int = 5_000, until stop: (GameController) -> Bool = { _ in false }) -> Int {
        var steps = 0
        while steps < maxSteps, !stop(self), let planned = plannedStep() {
            perform(planned.step)
            steps += 1
        }
        return steps
    }

    // MARK: Dealing and declaring

    private func dealOne() {
        guard stage == .dealing else { return }
        guard let dealt = round.dealNext() else {
            openDeclareWindow(messages: [])
            return
        }
        var messages: [String] = []
        if isBot(dealt.player), let line = botDeclares(dealt.player) {
            messages.append(line)
        }
        if round.isDealingComplete {
            // Every bot gets one last look once the deal is complete.
            for seat in Array(seats.dropFirst()) + [Seats.human] where isBot(seat) {
                if let line = botDeclares(seat) { messages.append(line) }
            }
            openDeclareWindow(messages: messages)
            return
        }
        if !messages.isEmpty {
            banner = GameCoachMessage(GameCoachText.join(messages), concept: "Declaring")
        } else if dealt.player == Seats.human, !isBot(Seats.human) {
            nudgeIfYouCanDeclare()
        }
    }

    /// The first time you could declare, say so (Guided and Coached).
    private func nudgeIfYouCanDeclare() {
        let options = round.availableDeclarations(for: Seats.human)
        if options.isEmpty {
            hadDeclarationOption = false
            return
        }
        guard !hadDeclarationOption else { return }
        hadDeclarationOption = true
        if let text = GameCoachText.canDeclareNudge(options, current: round.declaration, coach: coachLevel,
                                                    players: players) {
            banner = GameCoachMessage(text, concept: "Declaring", kind: .hint)
        }
    }

    /// Asks a bot whether to declare and applies it. Returns the banner line.
    private func botDeclares(_ seat: Int) -> String? {
        guard let d = Bot(seat: seat).declaration(in: round) else { return nil }
        do {
            try round.declare(d)
        } catch {
            return nil
        }
        if seat != Seats.human { hadDeclarationOption = false }
        return GameCoachText.declarationLine(d, players: players)
    }

    private func openDeclareWindow(messages: [String]) {
        stage = .declareWindow
        var lines = messages
        if !isBot(Seats.human) {
            if round.availableDeclarations(for: Seats.human).isEmpty {
                lines.append("All cards are dealt.")
            } else {
                lines.append("All cards are dealt. You can still declare, or tap Continue.")
            }
        }
        banner = GameCoachMessage(GameCoachText.join(lines), concept: "Declaring")
    }

    /// You reveal trump-rank cards (or a joker pair) to set the trump suit.
    func declare(_ declaration: Declaration) {
        guard stage == .dealing || stage == .declareWindow, !isBot(Seats.human) else { return }
        autoplayPaused = false
        do {
            try round.declare(declaration)
        } catch let error as RoundError {
            banner = GameCoachMessage(error.explanation, concept: "Declaring", kind: .warning)
            return
        } catch {
            return
        }
        hadDeclarationOption = true
        var text = GameCoachText.declarationLine(declaration, players: players)
        if round.dealer == nil {
            text += " If nobody beats it, you'll be the dealer."
        }
        banner = GameCoachMessage(text, concept: "Declaring", kind: .success)
        if stage == .declareWindow { stage = .botsRespond }
        restartDriver()
    }

    /// Closes the declaring window ("Continue").
    func continueAfterDeal() {
        guard stage == .declareWindow else { return }
        autoplayPaused = false
        finishDealingNow(prefix: nil)
        restartDriver()
    }

    private func botsRespond() {
        guard stage == .botsRespond else { return }
        var messages: [String] = []
        for seat in seats.dropFirst() where isBot(seat) {
            if let line = botDeclares(seat) { messages.append(line) }
        }
        if !isBot(Seats.human), !round.availableDeclarations(for: Seats.human).isEmpty {
            stage = .declareWindow
            let lead = messages.isEmpty ? "Nobody overrides you." : GameCoachText.join(messages)
            banner = GameCoachMessage("\(lead) You can declare again, or tap Continue.", concept: "Declaring")
            return
        }
        finishDealingNow(prefix: messages.isEmpty ? nil : GameCoachText.join(messages))
    }

    private func finishDealingNow(prefix: String?) {
        guard round.phase == .dealing, round.isDealingComplete else { return }
        round.finishDealing()
        reportMoves { MoveDetector.moves(inDeclarationsOf: $0) }
        stage = GameController.stage(for: round)
        selection = []
        if let dealer = round.dealer, !isBot(dealer) {
            newKittyCardIDs = Set(round.kitty.map(\.id))
            buryPromptPrefix = GameCoachText.join([prefix, GameCoachText.shortDealerReason(round: round, game: game)])
            refreshBuryPrompt()
        } else {
            let why = GameCoachText.dealerExplanation(round: round, game: game)
            banner = GameCoachMessage(GameCoachText.join([prefix, why, kittyPickupLine]), concept: "The kitty")
        }
        save()
    }

    // MARK: Burying

    private func refreshBuryPrompt() {
        guard isHumanBurying else { return }
        let count = selection.count
        var text = GameCoachText.join([buryPromptPrefix,
                                       "You're the dealer: choose \(round.kittySize) cards to bury (\(count)/\(round.kittySize))."])
        if coachLevel == .guided {
            text += " Cards marked new came from the kitty."
        }
        banner = GameCoachMessage(text, concept: "The kitty", kind: .info, id: buryPromptID)
    }

    private var bannerIsBuryPrompt: Bool { banner?.id == buryPromptID }

    private func botBury() {
        guard stage == .burying, let dealer = round.dealer, isBot(dealer) else { return }
        let decision = Bot(seat: dealer).cardsToBury(in: round)
        var buried = false
        if (try? round.bury(decision.cards)) != nil {
            buried = true
        } else {
            // Defensive fallback: the lowest cards that are not trumps where possible.
            let sorted = round.trump.sorted(hand(of: dealer))
            let plain = sorted.filter { !round.trump.isTrump($0) }
            let pick = Array((plain + sorted.filter { round.trump.isTrump($0) }).prefix(round.kittySize))
            buried = (try? round.bury(pick)) != nil
        }
        guard buried else {
            stall("The dealer couldn't bury the kitty.")
            return
        }
        if dealer == Seats.human { selection = [] }
        let size = round.kittySize
        let line = dealer == Seats.human ? "The bot buried \(size) cards for you." : "\(name(dealer)) buried \(size) cards face down."
        beginPlay(prefix: line)
    }

    /// You bury the selected cards (8, or 6 at a table of six).
    func burySelected() {
        guard canBury else { return }
        let cards = hand(of: Seats.human).filter { selection.contains($0.id) }
        do {
            try round.bury(cards)
        } catch let error as RoundError {
            noteIllegal(cards, error: error)
            banner = GameCoachMessage(error.explanation, concept: "The kitty", kind: .warning)
            return
        } catch {
            return
        }
        let points = cards.points
        let line = points > 0
            ? "You buried \(cards.count) cards with \(points) points. They count for the defenders if they win the last trick."
            : "You buried \(cards.count) cards with no points. Safe!"
        beginPlay(prefix: line)
        restartDriver()
    }

    private func beginPlay(prefix: String) {
        stage = GameController.stage(for: round)
        selection = []
        newKittyCardIDs = []
        buryPromptPrefix = nil
        let leader = round.leader
        let leadLine = leader == Seats.human
            ? "You lead the first trick."
            : "\(name(leader)) leads the first trick."
        let reminder = coachLevel == .guided ? "Remember: follow the led suit if you can." : nil
        banner = GameCoachMessage(GameCoachText.join([prefix, leadLine, reminder]))
        save()
    }

    // MARK: Selecting cards

    var canSelectCards: Bool {
        switch stage {
        case .burying: return isHumanBurying
        case .playing, .trickPause, .predicting: return !isBot(Seats.human)
        case .dealing, .declareWindow, .botsRespond, .roundOver: return false
        }
    }

    func toggle(_ card: Card) {
        guard canSelectCards, hand(of: Seats.human).contains(card) else { return }
        if selection.contains(card.id) {
            selection.remove(card.id)
        } else {
            selection.insert(card.id)
        }
        if bannerIsBuryPrompt { refreshBuryPrompt() }
    }

    /// Long press: selects the whole pair or tractor containing the card (or deselects it if already selected).
    func selectCombo(containing card: Card) {
        guard canSelectCards else { return }
        let combo = GameController.combo(containing: card, in: hand(of: Seats.human), trump: round.trump)
        guard !combo.isEmpty else { return }
        let ids = Set(combo.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
        if bannerIsBuryPrompt { refreshBuryPrompt() }
    }

    /// The longest tractor holding `card`, else its pair, else the card alone. With three or more
    /// decks, every copy of the card held (a triple) and tractors of triples come first.
    nonisolated static func combo(containing card: Card, in hand: [Card], trump: Trump) -> [Card] {
        guard hand.contains(card) else { return [] }
        let group = trump.group(card)
        let groupCards = hand.filter { trump.group($0) == group }
        let twinCount = groupCards.filter { $0.face == card.face }.count
        if twinCount >= 3 {
            for width in stride(from: twinCount, through: 3, by: -1) {
                let longestSets = Combos.longestRun(in: groupCards, width: width, trump: trump)
                for length in stride(from: longestSets, through: 2, by: -1) {
                    if let tractor = Combos.setTractors(in: groupCards, width: width, length: length, trump: trump)
                        .first(where: { t in t.contains { $0.face == card.face } }) {
                        return tractor
                    }
                }
            }
            return groupCards.filter { $0.face == card.face }
        }
        let longest = Combos.longestRun(in: groupCards, trump: trump)
        if longest >= 2 {
            for length in stride(from: longest, through: 2, by: -1) {
                if let tractor = Combos.tractors(in: groupCards, length: length, trump: trump)
                    .first(where: { t in t.contains { $0.face == card.face } }) {
                    return tractor
                }
            }
        }
        let twins = groupCards.filter { $0.face == card.face }
        return twins.count >= 2 ? Array(twins.prefix(2)) : [card]
    }

    func clearSelection() {
        guard !selection.isEmpty else { return }
        selection = []
        if bannerIsBuryPrompt { refreshBuryPrompt() }
    }

    // MARK: Hints

    /// The position at the table: when it moves on, the hint ladder and the last illegal attempt lapse.
    struct TablePosition: Equatable {
        var phase: RoundPhase
        var tricks: Int
        var cardsInTrick: Int
        var handCount: Int
    }

    var tablePosition: TablePosition {
        TablePosition(phase: round.phase, tricks: round.tricks.count, cardsInTrick: round.currentTrick.count,
                      handCount: hand(of: Seats.human).count)
    }

    /// The hint ladder for the position on the table (nil before the first hint, or once play moved on).
    var activeHint: HintLadder? {
        guard let hintLadder, hintPosition == tablePosition, canHint else { return nil }
        return hintLadder
    }

    /// The Hint button's title: Hint, then Another hint, then Show me. It names the step the next tap
    /// really reveals (the ladder skips a step whose text is empty), and stays Show me once complete.
    var hintButtonTitle: String {
        guard var next = activeHint else { return HintStep.nudge.buttonTitle }
        next.advance()
        return (next.step ?? .show).buttonTitle
    }

    /// The coach banner is showing the current hint step (it offers "Why?").
    var isShowingHint: Bool {
        guard activeHint != nil, let id = hintBannerID else { return false }
        return banner?.id == id
    }

    /// Guided and Coached: one more step of help for your play or bury, least help first:
    /// what to notice, then the principle, then the cards (selected for you) and the reason.
    /// At the last step another tap selects the suggested cards again.
    func showHint() {
        guard canHint else { return }
        let position = tablePosition
        var ladder: HintLadder
        if let current = hintLadder, hintPosition == position {
            ladder = current
        } else {
            let decision = isHumanBurying ? Bot(seat: Seats.human).cardsToBury(in: round)
                                          : Bot(seat: Seats.human).decide(in: round)
            ladder = HintLadder(decision: decision)
        }
        if !ladder.isComplete { ladder.advance() }
        hintLadder = ladder
        hintPosition = position
        if ladder.step == .show {
            let mine = Set(hand(of: Seats.human).map(\.id))
            selection = Set(ladder.highlightedCards.map(\.id)).intersection(mine)
        }
        let text = ladder.text.isEmpty ? ladder.decision.reason : ladder.text
        let message = GameCoachMessage(text.isEmpty ? "Look at what was led, and what you hold in that suit." : text,
                                       concept: ladder.concept, kind: .hint)
        hintBannerID = message.id
        banner = message
    }

    // MARK: Illegal attempts

    /// Your last rejected play (or bury) in this position, with the rule it broke (for the coach).
    var lastIllegal: IllegalAttempt? {
        guard let illegalAttempt, illegalPosition == tablePosition else { return nil }
        return illegalAttempt
    }

    private func noteIllegal(_ cards: [Card], error: RoundError) {
        illegalAttempt = IllegalAttempt(cards: cards, error: error)
        illegalPosition = tablePosition
    }

    // MARK: Playing

    /// Plays the selected cards for you.
    func playSelected() {
        guard isHumanTurn, isPlausiblePlay else { return }
        autoplayPaused = false
        let cards = selectedCards
        let lead = round.currentLead
        if let error = round.legalityError(for: cards, by: Seats.human) {
            reject(error, cards: cards, lead: lead)
            return
        }
        let before = round.tricks.count
        do {
            let outcome = try round.play(cards, by: Seats.human)
            selection = []
            banner = nil
            if case let .throwFailed(forced, blocker) = outcome {
                let note = GameCoachText.throwFailedLine(player: Seats.human, forced: forced,
                                                         blocker: blocker, trump: round.trump, players: players)
                throwNote = (note, true)
                banner = GameCoachMessage(note, concept: "Throws", kind: .warning)
            }
            afterPlay(tricksBefore: before)
        } catch let error as RoundError {
            reject(error, cards: cards, lead: lead)
            return
        } catch {
            banner = GameCoachMessage("That play didn't go through. Try again.", kind: .warning)
            return
        }
        restartDriver()
    }

    /// Rules are enforced and explained at every coach level.
    private func reject(_ error: RoundError, cards: [Card], lead: [Card]) {
        noteIllegal(cards, error: error)
        banner = GameCoachMessage(error.explanation, concept: GameCoachText.concept(for: error), kind: .warning)
        if let skill = GameCoachText.mistakeSkill(for: error, lead: lead) {
            onMistake?(skill)
        }
    }

    private func botPlay(_ seat: Int) {
        guard stage == .playing, round.turn == seat, isBot(seat) else { return }
        let before = round.tricks.count
        let decision = Bot(seat: seat).decide(in: round)
        var outcome = try? round.play(decision.cards, by: seat)
        if outcome == nil, let fallback = GameController.fallbackPlay(for: seat, in: round) {
            outcome = try? round.play(fallback, by: seat)
        }
        guard let outcome else {
            stall("\(name(seat)) couldn't find a legal play.")
            return
        }
        if seat == Seats.human { selection = [] }
        if case let .throwFailed(forced, blocker) = outcome {
            let note = GameCoachText.throwFailedLine(player: seat, forced: forced, blocker: blocker, trump: round.trump,
                                                     players: players)
            throwNote = (note, seat == Seats.human)
            banner = GameCoachMessage(note, concept: "Throws", kind: seat == Seats.human ? .warning : .info)
        }
        afterPlay(tricksBefore: before)
    }

    /// A legal play found by brute force, in case a bot decision is rejected by the rules.
    nonisolated static func fallbackPlay(for seat: Int, in round: Round) -> [Card]? {
        guard round.hands.indices.contains(seat) else { return nil }
        let trump = round.trump
        let hand = trump.sorted(round.hands[seat])
        let lead = round.currentLead
        guard let leadCard = lead.first else {
            return hand.first.map { [$0] }
        }
        let n = lead.count
        let group = trump.group(leadCard)
        let suited = hand.filter { trump.group($0) == group }
        let others = hand.filter { trump.group($0) != group }
        var candidates: [[Card]] = [Rules.legalFollow(hand: hand, lead: lead, trump: trump)]
        if suited.count >= n {
            candidates.append(Array(suited.prefix(n)))
            let pairCards = Combos.pairs(in: suited, trump: trump).flatMap { $0 }
            let rest = suited.filter { !pairCards.contains($0) }
            candidates.append(Array((pairCards + rest).prefix(n)))
            if n >= 4 {
                for length in stride(from: n / 2, through: 2, by: -1) {
                    if let tractor = Combos.tractors(in: suited, length: length, trump: trump).first {
                        let remaining = suited.filter { !tractor.contains($0) }
                        let morePairs = Combos.pairs(in: remaining, trump: trump).flatMap { $0 }
                        let singles = remaining.filter { !morePairs.contains($0) }
                        candidates.append(Array((tractor + morePairs + singles).prefix(n)))
                    }
                }
            }
        } else {
            candidates.append(suited + Array(others.prefix(n - suited.count)))
        }
        return candidates.first { $0.count == n && round.legalityError(for: $0, by: seat) == nil }
    }

    private func afterPlay(tricksBefore: Int) {
        guard round.tricks.count > tricksBefore, let trick = round.tricks.last else { return }
        trickCompleted(trick)
    }

    private func trickCompleted(_ trick: TrickRecord) {
        let trickIndex = round.tricks.count - 1
        reportMoves { MoveDetector.moves(inTrick: trickIndex, of: $0) }
        if round.phase == .finished { recordRoundResult() }
        if shouldAskPrediction(for: trick) {
            prediction = GamePredictionPrompt(trickNumber: round.tricks.count, winner: trick.winner, askedAt: Date())
            lastPredictionTrick = round.tricks.count
            stage = .predicting
        } else {
            reveal(trick, predictionResult: nil)
        }
        save()
    }

    /// "Who wins?" prompts: Guided and Coached only, about 1 trick in 3, never two in a row,
    /// more likely on tricks with a ruff, pairs or a close call.
    private func shouldAskPrediction(for trick: TrickRecord) -> Bool {
        guard predictionsEnabled, coachLevel != .solo, !isBot(Seats.human), trick.plays.count == players else { return false }
        let number = round.tricks.count
        if let last = lastPredictionTrick, number - last < 2 { return false }
        let interest = GameCoachText.predictionInterest(trick, trump: round.trump)
        let chance: Double
        switch interest {
        case 0: chance = 0.3
        case 1: chance = 0.45
        default: chance = 0.65
        }
        return Double.random(in: 0..<1, using: &rng) < chance
    }

    /// Your answer to "Who wins this trick?".
    func answerPrediction(_ seat: Int) {
        guard stage == .predicting, let prompt = prediction, let trick = round.tricks.last else { return }
        let correct = seat == prompt.winner
        let seconds = max(0, Date().timeIntervalSince(prompt.askedAt))
        prediction = nil
        onPrediction?(correct, seconds)
        reveal(trick, predictionResult: (correct, seat))
        restartDriver()
    }

    private func reveal(_ trick: TrickRecord, predictionResult: (correct: Bool, guess: Int)?) {
        stage = .trickPause
        longPause = predictionResult != nil
        let isDefender = round.isDefender(trick.winner)
        let isLast = round.phase == .finished
        let note = throwNote
        throwNote = nil
        if let result = predictionResult {
            let explanation = GameCoachText.trickExplanation(trick, trump: round.trump, coach: coachLevel, detailed: true,
                                                             winnerIsDefender: isDefender, isLastTrick: isLast)
            let guessName = result.guess == Seats.human ? "yourself" : name(result.guess)
            let opener = result.correct ? "Yes, well spotted!" : "Not quite: you picked \(guessName)."
            banner = GameCoachMessage(GameCoachText.join([opener, explanation?.text]),
                                      concept: explanation?.concept ?? "Who wins?",
                                      kind: result.correct ? .success : .info)
            return
        }
        let noteKind: GameCoachMessage.Kind = note?.isYours == true ? .warning : .info
        if let explanation = GameCoachText.trickExplanation(trick, trump: round.trump, coach: coachLevel,
                                                            winnerIsDefender: isDefender, isLastTrick: isLast) {
            banner = GameCoachMessage(GameCoachText.join([note?.text, explanation.text]),
                                      concept: note == nil ? explanation.concept : "Throws",
                                      kind: noteKind)
        } else if let note {
            banner = GameCoachMessage(note.text, concept: "Throws", kind: noteKind)
        } else {
            banner = nil
        }
    }

    /// Tap on the table during the pause after a trick.
    func skipTrickPause() {
        guard stage == .trickPause else { return }
        endTrickPause()
        restartDriver()
    }

    private func endTrickPause() {
        guard stage == .trickPause else { return }
        longPause = false
        if round.phase == .finished {
            showRoundOver()
        } else {
            stage = .playing
        }
    }

    // MARK: End of round

    private func recordRoundResult() {
        guard let result = round.result, !roundRecorded else { return }
        roundRecorded = true
        let summary = game.record(result)
        pendingSummary = summary
        onRoundFinished?()
        reportMoves { MoveDetector.moves(inFinishedRound: $0) }
        let winner = summary.gameWinner ?? game.winner
        if let onGameProgress, !isBot(Seats.human) {
            let team = Seats.team(of: Seats.human)
            onGameProgress(level(of: team), winner == team)
        }
        if let winner {
            onGameFinished?(winner == Seats.team(of: Seats.human))
            persistence?.delete()
        }
    }

    /// Hands the moves you made to `onMoves` (only asked for when someone is listening).
    private func reportMoves(_ detect: (Round) -> [MoveEvent]) {
        guard let onMoves, !isBot(Seats.human) else { return }
        let events = detect(round)
        if !events.isEmpty { onMoves(events) }
    }

    private func showRoundOver() {
        stage = .roundOver
        roundSummary = pendingSummary ?? game.history.last
        pendingSummary = nil
        isShowingResult = roundSummary != nil
        if let summary = roundSummary {
            banner = GameCoachMessage(summary.result.outcome.summary, concept: "Scoring")
        }
    }

    /// Deals the next round.
    func startNextRound() {
        guard stage == .roundOver, !isGameOver else { return }
        round = game.makeRound(rng: &rng)
        resetRoundUI()
        save()
        restartDriver()
    }

    /// Starts again from level 2 with the same game length.
    func startNewGame() {
        let settings = game.settings
        if !isDemo { persistence?.delete() }
        rng = SeededGenerator(seed: UInt64.random(in: UInt64.min...UInt64.max))
        game = GameState(settings: settings)
        round = game.makeRound(rng: &rng)
        resetRoundUI()
        save()
        restartDriver()
    }

    private func resetRoundUI() {
        stage = GameController.stage(for: round)
        selection = []
        prediction = nil
        roundSummary = nil
        pendingSummary = nil
        isShowingResult = false
        newKittyCardIDs = []
        lastPredictionTrick = nil
        longPause = false
        hadDeclarationOption = false
        buryPromptPrefix = nil
        stallMessage = nil
        roundRecorded = false
        throwNote = nil
        hintLadder = nil
        hintPosition = nil
        hintBannerID = nil
        illegalAttempt = nil
        illegalPosition = nil
        banner = GameCoachMessage(GameCoachText.dealingIntro(round: round, game: game, coach: coachLevel),
                                  concept: "Declaring")
    }

    private func stall(_ reason: String) {
        stallMessage = reason
        banner = GameCoachMessage("\(reason) Save and reopen the game to try again.", kind: .warning)
    }

    // MARK: Saving

    /// Writes the game to disk (never for demos or finished games).
    func saveNow() { save() }

    private func save() {
        guard !isDemo, !isGameOver, let persistence else { return }
        persistence.save(SavedGame(game: game, round: round, rng: rng, botSpeed: speed,
                                   predictionsEnabled: predictionsEnabled,
                                   lastPredictionTrick: lastPredictionTrick))
    }

    /// "Save & quit" from the table menu.
    func saveAndQuit() {
        save()
        tearDown()
    }
}
