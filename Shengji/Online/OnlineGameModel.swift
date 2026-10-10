import Foundation
import Observation
import ShengjiCore

/// Sheets the online table can show.
enum OnlineTableSheet: Identifiable, Equatable {
    case coach
    case rules
    case whatHappened
    case roundSummary(RoundSummary)

    var id: String {
        switch self {
        case .coach: return "coach"
        case .rules: return "rules"
        case .whatHappened: return "whatHappened"
        case .roundSummary: return "roundSummary"
        }
    }
}

/// The main button under the table.
enum OnlinePrimaryAction: Equatable, Sendable {
    case none
    /// Bidding: pass (declarations are their own buttons).
    case pass(enabled: Bool)
    case bury(count: Int, enabled: Bool)
    case play(enabled: Bool)
    /// Your move wasn't sent (offline): send it again.
    case retry
}

/// A finished trick shown on the table for a moment after the next one starts.
struct OnlineTrickFlash: Equatable, Sendable {
    /// 1-based trick number within the round.
    var number: Int
    var trick: TrickRecord
}

/// "What happened": the tricks since your last move (at most the last two), with winners and points.
struct OnlineWhatHappened: Equatable {
    struct Entry: Equatable, Identifiable {
        var number: Int
        var trick: TrickRecord
        var line: String
        var id: Int { number }
    }

    var title: String
    /// Oldest first.
    var tricks: [Entry]
    /// e.g. the end of the previous round.
    var note: String?
    /// "Mei led K♠." for the trick on the table now.
    var currentLead: String?
}

/// One online game at the table: the server's seat view, your selection, the action bar, live updates,
/// hints, the coach and achievements. SwiftUI-free (`OnlineTableView` draws it).
///
/// Every state from the server (an action's reply, a live update, a poll or a refresh) goes through
/// `receive`, which keeps only versions newer than the one on screen.
@MainActor
@Observable
final class OnlineGameModel: Identifiable {
    let gameID: String
    let isMock: Bool

    private(set) var summary: OnlineGameSummary?
    private(set) var view: SeatView?
    private(set) var version: Int?
    private(set) var isLoading = false
    /// Shown instead of the table when it can't be loaded.
    private(set) var loadError: String?
    /// The game was deleted (or you were signed out): the table can only be closed.
    private(set) var isGone = false
    private(set) var isSending = false
    /// A move that wasn't sent because you were offline (Retry sends it again).
    private(set) var pendingAction: OnlineAction?
    /// Selected card ids in your hand.
    private(set) var selection: Set<Int> = []
    private(set) var banner: GameCoachMessage?
    private(set) var flash: OnlineTrickFlash?
    private(set) var liveStatus: OnlineLiveUpdates.Status = .stopped
    /// The sheet over the table (see `setSheet`).
    private(set) var sheet: OnlineTableSheet?
    private(set) var hintDecision: BotDecision?
    private(set) var hintLadder: HintLadder?
    private(set) var hintBannerID: UUID?
    private(set) var illegalAttempt: IllegalAttempt?
    private(set) var lastNudge: Date?
    var coachLevel: CoachLevel = .guided
    /// Reminders reach the other player (false while the server sends no notifications: a reminder
    /// would reach nobody, so the table doesn't offer one).
    var canRemind = true

    /// Hints for your play or bury from a seat view (nil: no Hint button). `OnlineSession.makeTable`
    /// plugs in `Bot(seat: 0).decide(view:)`.
    @ObservationIgnored var hintProvider: ((SeatView) -> BotDecision?)?

    // Hooks (wired by the view; nil in demo tables and checks).
    @ObservationIgnored var onMoves: (@MainActor ([MoveEvent]) -> Void)?
    @ObservationIgnored var onGameProgress: (@MainActor (_ teamLevel: Rank, _ wonGame: Bool) -> Void)?
    @ObservationIgnored var onMistake: (@MainActor (SkillID) -> Void)?
    @ObservationIgnored var onRoundFinished: (@MainActor () -> Void)?
    @ObservationIgnored var onGameFinished: (@MainActor (_ won: Bool) -> Void)?
    @ObservationIgnored var onSummary: (@MainActor (OnlineGameSummary) -> Void)?
    @ObservationIgnored var onSignedOut: (@MainActor () -> Void)?

    /// Seconds a finished trick stays on the table once the next one starts (0: never shown).
    @ObservationIgnored var flashSeconds: Double = 2.5
    /// Seconds between closing one sheet and opening a queued round summary.
    @ObservationIgnored var sheetGap: Double = 0.5

    @ObservationIgnored private let api: OnlineAPI
    @ObservationIgnored private let ledger: OnlineGameLedger
    @ObservationIgnored private let liveConnector: OnlineLiveConnector?
    @ObservationIgnored private var live: OnlineLiveUpdates?
    @ObservationIgnored private var flashTask: Task<Void, Never>?
    @ObservationIgnored private var sheetTask: Task<Void, Never>?
    @ObservationIgnored private var queuedSummary: RoundSummary?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var hintVersion: Int?
    @ObservationIgnored private var illegalVersion: Int?

    static let nudgeInterval: TimeInterval = 10 * 60

    init(gameID: String, api: OnlineAPI, summary: OnlineGameSummary? = nil, liveConnector: OnlineLiveConnector?,
         ledger: OnlineGameLedger) {
        self.gameID = gameID
        self.api = api
        self.isMock = api.isMock
        self.summary = summary
        self.liveConnector = api.isMock ? nil : liveConnector
        self.ledger = ledger
    }

    // MARK: Lifecycle

    /// The table opened: load it and listen for updates.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        startLive()
        Task { await refresh() }
    }

    /// The table closed.
    func stop() {
        isStarted = false
        live?.stop()
        live = nil
        liveStatus = .stopped
        flashTask?.cancel()
        flashTask = nil
        sheetTask?.cancel()
        sheetTask = nil
    }

    /// The app went to the background (false) or came back (true). A closed table stays disconnected.
    func setActive(_ active: Bool) {
        guard isStarted, !isGone else { return }
        if active {
            if let live { live.resume() } else { startLive() }
            Task { await refresh() }
        } else {
            live?.stop()
        }
    }

    /// Signed out while the table was open.
    func sessionEnded() {
        stop()
        isGone = true
        loadError = "You're signed out. Sign in again to keep playing."
    }

    private func startLive() {
        guard !isGone, let connector = liveConnector, let url = api.liveURL(gameID: gameID) else { return }
        let updates = live ?? OnlineLiveUpdates(connector: connector)
        updates.onState = { [weak self] state in
            self?.receive(state)
        }
        updates.onStatus = { [weak self] status in
            self?.liveStatus = status
        }
        updates.onPoll = { [weak self] in
            await self?.refresh()
        }
        live = updates
        updates.start(url: url)
    }

    /// Fetches the game (opening, polling, returning to the app, after a notification).
    /// `authoritative`: apply the server's answer even if its version is lower than the one on screen.
    func refresh(authoritative: Bool = false) async {
        guard !isGone else { return }
        if view == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let state = try await api.game(id: gameID)
            loadError = nil
            receive(state, authoritative: authoritative)
        } catch let error as OnlineError {
            switch error {
            case .signedOut:
                onSignedOut?()
            case .notFound, .forbidden:
                isGone = true
                loadError = "This game has ended or was deleted."
                live?.stop()
            default:
                if view == nil { loadError = error.message }
            }
        } catch {
            if view == nil, !(error is CancellationError) { loadError = OnlineError.offlineMessage }
        }
    }

    // MARK: Applying server states

    /// A state from anywhere (action reply, live update, poll). Older or equal versions are ignored,
    /// except an authoritative one (a fresh GET after a stale-version reply): that is applied even if its
    /// version is lower (a server that was reset).
    func receive(_ state: OnlineGameState, authoritative: Bool = false) {
        if let version {
            if authoritative ? state.version == version : state.version <= version { return }
        }
        apply(state)
    }

    private struct Position: Equatable {
        var round: Int
        var phase: SeatView.Phase
        var tricks: Int
        var cardsInTrick: Int
        var handCount: Int
        var bids: Int
        var acting: Int?
    }

    private var position: Position? {
        guard let view else { return nil }
        return Position(round: view.roundNumber, phase: view.phase, tricks: view.tricks.count,
                        cardsInTrick: view.currentTrick.count, handCount: view.hand.count,
                        bids: view.bidding?.history.count ?? 0, acting: OnlineGameText.actingSeat(view))
    }

    private func apply(_ state: OnlineGameState) {
        let old = view
        let oldPosition = position
        summary = state.game
        view = state.view
        version = state.version
        onSummary?(state.game)

        let moved = position != oldPosition
        let handIDs = Set(state.view.hand.map(\.id))
        selection = moved ? [] : selection.intersection(handIDs)
        if moved {
            // A move that wasn't sent belongs to the old position (Retry would only be refused now).
            pendingAction = nil
            hintLadder = nil
            hintBannerID = nil
            if let text = OnlineGameText.banner(old: old, new: state.view) {
                banner = GameCoachMessage(text)
            } else if old == nil {
                banner = nil
            }
        }
        flashIfNeeded(old: old, new: state.view)
        refreshHint()
        recordProgress(state.view)
    }

    private func flashIfNeeded(old: SeatView?, new view: SeatView) {
        guard flashSeconds > 0, view.phase == .playing, let last = view.tricks.last else { return }
        if let old {
            guard old.roundNumber == view.roundNumber, view.tricks.count > old.tricks.count else { return }
        }
        showFlash(OnlineTrickFlash(number: view.tricks.count, trick: last))
    }

    private func showFlash(_ newFlash: OnlineTrickFlash) {
        flash = newFlash
        flashTask?.cancel()
        let seconds = flashSeconds
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.flash == newFlash else { return }
            self.flash = nil
        }
    }

    /// Tap the table: back to the trick in progress.
    func skipFlash() {
        flashTask?.cancel()
        flashTask = nil
        if flash != nil { flash = nil }
    }

    private func recordProgress(_ view: SeatView) {
        let (entry, report) = OnlineProgress.update(ledger.entry(for: gameID), with: view)
        if ledger.entry(for: gameID) != entry {
            ledger.set(entry, for: gameID)
        }
        if !report.moves.isEmpty { onMoves?(report.moves) }
        if report.roundFinished {
            if let level = report.teamLevel { onGameProgress?(level, report.wonGame) }
            onRoundFinished?()
            if report.gameFinished { onGameFinished?(report.wonGame) }
        }
        if let summary = report.showSummary { presentRoundSummary(summary) }
    }

    // MARK: Reading

    var players: [SeatView.Player] { view?.players ?? summary?.players ?? [] }

    func name(_ seat: Int) -> String { OnlineGameText.name(seat, players: players) }

    var isGameOver: Bool {
        view?.gameWinnerTeam != nil || summary?.status == .finished
    }

    /// "You and Mei win the game!" once it is over.
    var gameOverHeadline: String? {
        guard isGameOver else { return nil }
        guard let winner = view?.gameWinnerTeam ?? summary?.winnerTeam else { return "This game is over." }
        let team = OnlineGameText.teamName(winner, players: players)
        return winner == 0 ? "\(team) win the game!" : "\(team) win the game."
    }

    var actingSeat: Int? { view.map(OnlineGameText.actingSeat) ?? nil }

    var isBiddingTurn: Bool {
        guard let view, !isGameOver else { return false }
        return view.phase == .bidding && view.bidding?.turn == Seats.human
    }

    var isBuryingTurn: Bool {
        guard let view, !isGameOver else { return false }
        return view.phase == .burying && OnlineGameText.actingSeat(view) == Seats.human
    }

    var isPlayingTurn: Bool {
        guard let view, !isGameOver else { return false }
        return view.phase == .playing && view.turn == Seats.human
    }

    var isYourTurn: Bool { isBiddingTurn || isBuryingTurn || isPlayingTurn }

    /// Declarations you can make now (bidding, your turn).
    var availableBids: [Declaration] { isBiddingTurn ? (view?.bidding?.available ?? []) : [] }

    /// Your hand, plain suits on the left and trumps on the right.
    var hand: [Card] {
        guard let view else { return [] }
        return view.trump.sorted(view.hand)
    }

    var selectedCards: [Card] { hand.filter { selection.contains($0.id) } }

    var statusText: String {
        guard let view else { return isLoading ? "Opening the table" : "" }
        if pendingAction != nil { return "Not sent" }
        if isSending { return "Sending" }
        return OnlineGameText.statusText(view, gameOver: isGameOver)
    }

    var primaryAction: OnlinePrimaryAction {
        if pendingAction != nil { return .retry }
        guard view != nil, !isGameOver, !isGone else { return .none }
        if isBiddingTurn { return .pass(enabled: !isSending) }
        if isBuryingTurn {
            return .bury(count: selection.count, enabled: selection.count == Round.kittySize && !isSending)
        }
        if isPlayingTurn { return .play(enabled: isPlausiblePlay && !isSending) }
        return .none
    }

    /// Lead: at least one card. Follow: as many cards as were led.
    var isPlausiblePlay: Bool {
        guard let view else { return false }
        let lead = view.currentLead
        return lead.isEmpty ? !selection.isEmpty : selection.count == lead.count
    }

    var isTrumpSet: Bool {
        guard let view else { return false }
        return view.phase != .bidding || view.declaration != nil
    }

    func level(of team: Int) -> Rank? {
        guard let levels = view?.teamLevels ?? summary?.teamLevels, levels.indices.contains(team) else { return nil }
        return levels[team]
    }

    var defenderPoints: Int { view?.defenderTrickPoints ?? 0 }

    var dealerText: String {
        guard let dealer = view?.dealer else { return "Dealer: first to declare" }
        return "Dealer: \(name(dealer))"
    }

    /// "Round 3 · Dealer: Ana" for the top bar.
    var roundAndDealerText: String {
        "Round \(view?.roundNumber ?? summary?.roundNumber ?? 1) · \(dealerText)"
    }

    /// Guided marks trumps with the gold edge.
    var markTrumps: Bool { coachLevel == .guided }

    /// Guided: when you are following and hold enough cards of the led group, the others are dimmed.
    var dimmedCardIDs: Set<Int> {
        guard coachLevel == .guided, isPlayingTurn, let view, let first = view.currentLead.first else { return [] }
        let trump = view.trump
        let group = trump.group(first)
        let inGroup = view.hand.filter { trump.group($0) == group }
        guard inGroup.count >= view.currentLead.count else { return [] }
        return Set(view.hand.filter { trump.group($0) != group }.map(\.id))
    }

    /// While you bury: the kitty cards you picked up.
    var newCardIDs: Set<Int> {
        guard isBuryingTurn, let kitty = view?.kitty else { return [] }
        return Set(kitty.map(\.id)).intersection(view?.hand.map(\.id) ?? [])
    }

    /// The cards in the middle: a finished trick for a moment, else the trick in progress.
    var trickDisplay: TableTrickDisplay {
        if let flash {
            return TableTrickDisplay(plays: flash.trick.plays, winner: flash.trick.winner, isFinished: true,
                                     points: flash.trick.points)
        }
        guard let view else { return .empty }
        switch view.phase {
        case .playing:
            return TableTrickDisplay(plays: view.currentTrick, winner: nil, isFinished: false,
                                     points: view.currentTrick.flatMap(\.cards).points)
        case .finished:
            guard let last = view.tricks.last else { return .empty }
            return TableTrickDisplay(plays: last.plays, winner: last.winner, isFinished: true, points: last.points)
        case .dealing, .bidding, .burying:
            return .empty
        }
    }

    /// Guided only: who is winning the trick in progress.
    var leadingSeat: Int? {
        guard coachLevel == .guided, flash == nil, let view, view.phase == .playing, view.currentTrick.count >= 2 else {
            return nil
        }
        let index = Rules.winningIndex(view.currentTrick, trump: view.trump)
        return view.currentTrick.indices.contains(index) ? view.currentTrick[index].player : nil
    }

    func role(of seat: Int) -> GameSeatRole? {
        guard let dealer = view?.dealer else { return nil }
        if seat == dealer { return .dealer }
        return Seats.team(of: seat) == Seats.team(of: dealer) ? .declarer : .defender
    }

    func seatInfo(_ seat: Int) -> GameSeatInfo {
        let counts = view?.handCounts ?? []
        let display = trickDisplay
        return GameSeatInfo(seat: seat, name: name(seat), team: Seats.team(of: seat),
                            cardCount: counts.indices.contains(seat) ? counts[seat] : 0, role: role(of: seat),
                            isTurn: !isGameOver && actingSeat == seat, isThinking: false,
                            isTrickWinner: display.winner == seat, isLeading: leadingSeat == seat)
    }

    // MARK: Selecting cards

    var canSelectCards: Bool {
        guard let view, !isGameOver else { return false }
        switch view.phase {
        case .burying: return isBuryingTurn
        case .playing: return true
        case .dealing, .bidding, .finished: return false
        }
    }

    func toggle(_ card: Card) {
        guard canSelectCards, view?.hand.contains(card) == true else { return }
        if selection.contains(card.id) {
            selection.remove(card.id)
        } else {
            selection.insert(card.id)
        }
        selectionChanged()
    }

    /// Long press: the whole pair or tractor holding the card (or deselects it if already selected).
    func selectCombo(containing card: Card) {
        guard canSelectCards, let view else { return }
        let combo = GameController.combo(containing: card, in: view.hand, trump: view.trump)
        guard !combo.isEmpty else { return }
        let ids = Set(combo.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
        selectionChanged()
    }

    func clearSelection() {
        if !selection.isEmpty { selection = [] }
        selectionChanged()
    }

    /// Choosing other cards after a move wasn't sent: the main button goes back to Play or Bury.
    private func selectionChanged() {
        guard let pendingAction, !isSending else { return }
        switch pendingAction {
        case .play, .bury: self.pendingAction = nil
        case .bid, .pass: break
        }
    }

    // MARK: Actions

    func bid(_ declaration: Declaration) {
        guard isBiddingTurn else { return }
        send(.bid(declaration))
    }

    func pass() {
        guard isBiddingTurn else { return }
        send(.pass)
    }

    func bury() {
        guard isBuryingTurn else { return }
        let cards = selectedCards
        guard cards.count == Round.kittySize else {
            banner = GameCoachMessage("Choose exactly \(Round.kittySize) cards to bury (you chose \(cards.count)).",
                                      concept: "The kitty", kind: .warning)
            return
        }
        send(.bury(cards))
    }

    /// Checks the play with the rules first (instant feedback), then sends it.
    func play() {
        guard isPlayingTurn, isPlausiblePlay, let view else { return }
        let cards = selectedCards
        let lead = view.currentLead
        if lead.isEmpty {
            if let violation = Rules.validateLead(cards, hand: view.hand, trump: view.trump) {
                reject(.illegalLead(violation), cards: cards, lead: lead)
                return
            }
        } else if let violation = Rules.validateFollow(cards, hand: view.hand, lead: lead, trump: view.trump) {
            reject(.illegalFollow(violation), cards: cards, lead: lead)
            return
        }
        send(.play(cards))
    }

    /// Sends the move that wasn't sent.
    func retry() {
        guard let action = pendingAction else { return }
        send(action)
    }

    private func reject(_ error: RoundError, cards: [Card], lead: [Card]) {
        illegalAttempt = IllegalAttempt(cards: cards, error: error)
        illegalVersion = version
        banner = GameCoachMessage(error.explanation, concept: GameCoachText.concept(for: error), kind: .warning)
        if let skill = GameCoachText.mistakeSkill(for: error, lead: lead) {
            onMistake?(skill)
        }
    }

    private func send(_ action: OnlineAction) {
        guard !isSending else { return }
        isSending = true
        Task { await perform(action) }
    }

    /// Sends one action with the version on screen and applies the answer.
    func perform(_ action: OnlineAction) async {
        isSending = true
        defer { isSending = false }
        guard let version, let before = view else { return }
        do {
            let response = try await api.act(gameID: gameID, version: version, action: action)
            pendingAction = nil
            noteMove(action, before: before)
            receive(response.state)
            if let outcome = response.outcome, outcome.isThrowFailed, let forced = outcome.forced {
                let line = OnlineGameText.throwFailedLine(forced: forced, blocker: outcome.blocker, view: response.view)
                banner = GameCoachMessage(line, concept: "Throws", kind: .warning)
            }
        } catch let error as OnlineError {
            await handleActionError(error, action: action, before: before)
        } catch is CancellationError {
            return
        } catch {
            await handleActionError(.offline, action: action, before: before)
        }
    }

    private func handleActionError(_ error: OnlineError, action: OnlineAction, before: SeatView) async {
        switch error {
        case let .stale(state):
            pendingAction = nil
            if let version, state.version < version {
                // Older than the table on screen: a live update overtook this reply (or the server was
                // reset). Ask again and believe that answer.
                await refresh(authoritative: true)
            } else {
                receive(state)
            }
            if OnlineGameModel.moveLanded(action, before: before, after: view ?? state.view) {
                // The first try reached the server even though its reply was lost.
                noteMove(action, before: before)
                banner = GameCoachMessage(OnlineGameModel.moveLandedMessage, kind: .success)
            } else {
                banner = GameCoachMessage(OnlineError.staleMessage)
            }
        case let .illegal(message):
            pendingAction = nil
            banner = GameCoachMessage(message, kind: .warning)
        case .notYourTurn:
            pendingAction = nil
            banner = GameCoachMessage(OnlineError.notYourTurnMessage)
            await refresh()
        case .offline:
            if let view, OnlineGameModel.moveLanded(action, before: before, after: view) {
                // The reply was lost, but the live update had already shown the move on the table (the
                // server sends it to live connections before it answers): there is nothing to send again.
                pendingAction = nil
                noteMove(action, before: before)
                banner = GameCoachMessage(OnlineGameModel.moveLandedMessage, kind: .success)
            } else {
                pendingAction = action
                banner = GameCoachMessage(OnlineError.moveNotSentMessage, kind: .warning)
            }
        case .signedOut:
            pendingAction = nil
            onSignedOut?()
        case .notFound:
            pendingAction = nil
            isGone = true
            loadError = "This game has ended or was deleted."
            live?.stop()
        default:
            pendingAction = nil
            banner = GameCoachMessage(error.message, kind: .warning)
        }
    }

    static let moveLandedMessage = "Your move went through."

    /// True if the server's table shows that `action`, chosen at `before`, was already played (its
    /// reply was lost after a live update showed it, or Retry was refused as stale), within the same
    /// round: a play's or burial's cards left your hand (a throw that failed plays only part of them,
    /// and only your own move takes cards from your hand); a bid or pass is the next entry in the
    /// bidding after your turn (or bidding is over, which can't happen without your turn being taken).
    static func moveLanded(_ action: OnlineAction, before: SeatView, after: SeatView) -> Bool {
        guard after.roundNumber == before.roundNumber else { return false }
        let cards: [Card]
        switch action {
        case let .play(chosen), let .bury(chosen):
            cards = chosen
        case .bid, .pass:
            guard let bidding = before.bidding, bidding.turn == Seats.human else { return false }
            guard let next = after.bidding else { return after.phase != .bidding }
            return next.history.count > bidding.history.count && next.history[bidding.history.count].player == Seats.human
        }
        guard !cards.isEmpty else { return false }
        let beforeIDs = Set(before.hand.map(\.id))
        let afterIDs = Set(after.hand.map(\.id))
        return cards.contains { beforeIDs.contains($0.id) && !afterIDs.contains($0.id) }
    }

    /// A message from outside the table, such as the server refusing to end the game.
    func showNotice(_ text: String) {
        banner = GameCoachMessage(text, kind: .warning)
    }

    /// Remembers where you last played, for "What happened".
    private func noteMove(_ action: OnlineAction, before: SeatView) {
        guard case .play = action else { return }
        var entry = ledger.entry(for: gameID) ?? OnlineGameLedger.baseline(for: before)
        entry.lastMoveRound = before.roundNumber
        entry.lastMoveTrick = before.tricks.count
        ledger.set(entry, for: gameID)
    }

    // MARK: Nudging

    var canNudge: Bool {
        guard canRemind, !isGameOver, !isGone, let view, let seat = OnlineGameText.actingSeat(view), seat != Seats.human,
              view.players.indices.contains(seat), !view.players[seat].isBot else { return false }
        if let lastNudge, Date().timeIntervalSince(lastNudge) < OnlineGameModel.nudgeInterval { return false }
        return true
    }

    /// Reminds the player whose turn it is (the server allows one nudge per game every 10 minutes).
    func nudge() async {
        guard canNudge, let seat = actingSeat else { return }
        let who = name(seat)
        do {
            try await api.nudge(gameID: gameID)
            lastNudge = Date()
            // The demo server lets a nudged friend play at once.
            if isMock { await refresh() }
            banner = GameCoachMessage("We sent \(who) a reminder.", kind: .success)
        } catch let error as OnlineError {
            if case .signedOut = error {
                onSignedOut?()
                return
            }
            if case .rateLimited = error { lastNudge = Date() }
            banner = GameCoachMessage(error.message, kind: .warning)
        } catch {
            banner = GameCoachMessage(OnlineError.offlineMessage, kind: .warning)
        }
    }

    // MARK: Hints

    private var canHintNow: Bool { isPlayingTurn || isBuryingTurn }

    private func refreshHint() {
        guard let view, let hintProvider, canHintNow else {
            hintDecision = nil
            hintVersion = nil
            return
        }
        guard hintVersion != version else { return }
        hintDecision = hintProvider(view)
        hintVersion = version
    }

    /// The Hint button shows only when a hint exists for this moment (and not in Solo).
    var hintsAvailable: Bool { coachLevel != .solo && canHintNow && hintDecision != nil && !isGameOver }

    var activeHint: HintLadder? { hintsAvailable ? hintLadder : nil }

    /// Hint, then Another hint, then Show me.
    var hintButtonTitle: String {
        guard var next = activeHint else { return HintStep.nudge.buttonTitle }
        next.advance()
        return (next.step ?? .show).buttonTitle
    }

    var isShowingHint: Bool {
        guard activeHint != nil, let id = hintBannerID else { return false }
        return banner?.id == id
    }

    /// One more step of help: what to notice, the principle, then the cards (selected for you).
    func showHint() {
        guard hintsAvailable, let decision = hintDecision else { return }
        var ladder = hintLadder ?? HintLadder(decision: decision)
        if !ladder.isComplete { ladder.advance() }
        hintLadder = ladder
        if ladder.step == .show {
            let mine = Set(view?.hand.map(\.id) ?? [])
            selection = Set(ladder.highlightedCards.map(\.id)).intersection(mine)
            selectionChanged()
        }
        let text = ladder.text.isEmpty ? ladder.decision.reason : ladder.text
        let message = GameCoachMessage(text.isEmpty ? "Look at what was led, and what you hold in that suit." : text,
                                       concept: ladder.concept, kind: .hint)
        hintBannerID = message.id
        banner = message
    }

    // MARK: Coach

    /// Your last rejected play in this position (for the coach).
    var lastIllegal: IllegalAttempt? {
        guard let illegalAttempt, illegalVersion == version else { return nil }
        return illegalAttempt
    }

    var canAskCoach: Bool { view != nil }

    var coachContext: String? {
        guard let view else { return nil }
        return CoachContext.describe(view: view, hint: activeHint, selection: selectedCards, lastIllegal: lastIllegal)
    }

    var coachSuggestions: [SuggestedQuestion] {
        guard let view else { return [] }
        return SuggestedQuestions.forTable(view: view, hint: activeHint, selection: selectedCards, lastIllegal: lastIllegal)
    }

    func prepareCoach(_ conversation: CoachConversation) {
        conversation.prepare(scope: .table, context: coachContext, suggestions: coachSuggestions)
    }

    var explainHintQuestion: SuggestedQuestion? {
        activeHint.map { SuggestedQuestions.explainHint($0) }
    }

    // MARK: Sheets

    /// Sets or clears the sheet (the view's sheet binding). Closing one opens a queued round summary.
    func setSheet(_ newSheet: OnlineTableSheet?) {
        guard newSheet != sheet else { return }
        sheet = newSheet
        guard newSheet == nil, let summary = queuedSummary else { return }
        queuedSummary = nil
        sheetTask?.cancel()
        let gap = sheetGap
        sheetTask = Task { [weak self] in
            if gap > 0 { try? await Task.sleep(nanoseconds: UInt64(gap * 1_000_000_000)) }
            guard !Task.isCancelled, let self, self.sheet == nil else { return }
            self.sheet = .roundSummary(summary)
        }
    }

    /// A new round began since you last looked: show how the last one went (after any open sheet).
    func presentRoundSummary(_ summary: RoundSummary) {
        if sheet == nil {
            sheet = .roundSummary(summary)
        } else if sheet != .roundSummary(summary) {
            queuedSummary = summary
        }
    }

    var lastRoundSummary: RoundSummary? { view?.lastRoundSummary }

    var whatHappened: OnlineWhatHappened {
        guard let view else { return OnlineWhatHappened(title: "What happened", tricks: [], note: nil, currentLead: nil) }
        let count = view.tricks.count
        var start = max(0, count - 2)
        var title = "Recent tricks"
        if let entry = ledger.entry(for: gameID), entry.lastMoveRound == view.roundNumber, let trick = entry.lastMoveTrick,
           trick < count {
            start = max(trick, count - 2)
            title = "Since your last move"
        }
        let entries = (start..<count).map { index in
            OnlineWhatHappened.Entry(number: index + 1, trick: view.tricks[index],
                                     line: OnlineGameText.trickLine(view.tricks[index], view: view))
        }
        var note: String?
        if entries.isEmpty {
            if let summary = view.lastRoundSummary {
                note = "Round \(max(1, view.roundNumber - 1)) is over: \(OnlineGameText.roundHeadline(summary, players: view.players))."
            } else {
                note = "No tricks have finished yet this round."
            }
        }
        return OnlineWhatHappened(title: entries.isEmpty ? "What happened" : title, tricks: entries, note: note,
                                  currentLead: OnlineGameText.leadLine(view))
    }
}
