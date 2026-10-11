import Foundation
import ShengjiCore

/// A whole online game run in memory with the Swift engine and bots, the way the server runs it:
/// all cards dealt at once, turn-based bidding, then burying and play. The demo server keeps one per
/// game; the viewer is always seat 0. SwiftUI-free.
struct OnlineDemoGame: Sendable {
    struct Bidding: Sendable {
        var turn: Int
        /// Passes since the last declaration (or since bidding opened).
        var passes: Int
        var history: [SeatView.Bid]
    }

    /// Why an action was refused (status code, error code and message for the error body).
    struct Rejection: Error, Equatable {
        var status: Int
        var code: String
        var message: String?

        static func illegal(_ message: String) -> Rejection { Rejection(status: 400, code: "illegal", message: message) }
        static let notYourTurn = Rejection(status: 403, code: "not_your_turn", message: nil)
    }

    var id: String
    var clubId: String
    var creatorID: String
    var createdAt: Date
    var updatedAt: Date
    /// Absolute seat order; seat 0 is the demo user.
    var players: [SeatView.Player]
    var botLevels: [Int: BotLevel]
    var game: GameState
    var round: Round
    var bidding: Bidding?
    var rng: SeededGenerator
    var version: Int
    var lastEvent: String?
    /// A finished game kept only for its summary (no round on the table).
    var archived = false

    /// Deals the first round with bidding open at `firstBidder`.
    static func start(id: String, clubId: String, creatorID: String, players: [SeatView.Player],
                      botLevels: [Int: BotLevel], settings: GameSettings, seed: UInt64, firstBidder: Int,
                      now: Date) -> OnlineDemoGame {
        var rng = SeededGenerator(seed: seed)
        let game = GameState(settings: settings)
        var round = game.makeRound(rng: &rng)
        round.dealAll()
        return OnlineDemoGame(id: id, clubId: clubId, creatorID: creatorID, createdAt: now, updatedAt: now,
                              players: players, botLevels: botLevels, game: game, round: round,
                              bidding: Bidding(turn: firstBidder, passes: 0, history: []), rng: rng, version: 1,
                              lastEvent: "The cards are dealt.")
    }

    /// Continues a game whose earlier rounds are already in `game` (the next round is dealt now).
    static func resume(id: String, clubId: String, creatorID: String, players: [SeatView.Player],
                       game: GameState, seed: UInt64, now: Date) -> OnlineDemoGame {
        var rng = SeededGenerator(seed: seed)
        var round = game.makeRound(rng: &rng)
        round.dealAll()
        return OnlineDemoGame(id: id, clubId: clubId, creatorID: creatorID, createdAt: now, updatedAt: now,
                              players: players, botLevels: [:], game: game, round: round,
                              bidding: Bidding(turn: game.nextDealer ?? 0, passes: 0, history: []), rng: rng,
                              version: 1, lastEvent: "A new round is dealt.")
    }

    var isOver: Bool { archived || game.winner != nil }

    /// Whose action the game waits for.
    var actingSeat: Int? {
        if isOver { return nil }
        if let bidding { return bidding.turn }
        switch round.phase {
        case .burying: return round.dealer
        case .playing: return round.turn
        case .dealing, .finished: return nil
        }
    }

    func name(_ seat: Int) -> String {
        OnlineGameText.name(seat, players: players)
    }

    // MARK: Acting

    /// Applies one action for `seat`. Returns the outcome of a failed throw, if any.
    @discardableResult
    mutating func act(_ action: OnlineAction, by seat: Int, now: Date = Date()) throws -> OnlineOutcome? {
        guard !isOver else { throw Rejection.illegal("This game is over.") }
        guard actingSeat == seat else { throw Rejection.notYourTurn }
        var outcome: OnlineOutcome?
        switch action {
        case let .bid(choice):
            guard var state = bidding else { throw Rejection.illegal("Bidding is over for this round.") }
            let declaration = Declaration(player: seat, cards: choice.cards, suit: choice.suit, strength: choice.strength)
            do {
                try round.declare(declaration)
            } catch let error as RoundError {
                throw Rejection.illegal(error.explanation)
            }
            state.history.append(SeatView.Bid(player: seat, declaration: declaration))
            state.passes = 0
            state.turn = Seats.next(after: seat, players: round.players)
            bidding = state
            lastEvent = OnlineGameText.declarationLine(declaration, players: players)
        case .pass:
            guard var state = bidding else { throw Rejection.illegal("Bidding is over for this round.") }
            state.history.append(SeatView.Bid(player: seat, declaration: nil))
            state.passes += 1
            state.turn = Seats.next(after: seat, players: round.players)
            bidding = state
            lastEvent = "\(name(seat)) passed."
            // Everyone passes with nothing declared, or everyone else passes after a declaration.
            let needed = round.declaration == nil ? round.players : round.players - 1
            if state.passes >= needed {
                bidding = nil
                round.finishDealing()
            }
        case let .bury(cards, calls):
            guard bidding == nil, round.phase == .burying else { throw Rejection.illegal("You can't bury now.") }
            do {
                try round.bury(cards, calls: calls)
            } catch let error as RoundError {
                throw Rejection.illegal(error.explanation)
            }
            lastEvent = calls.isEmpty ? "\(name(seat)) buried the kitty."
                : "\(name(seat)) buried the kitty and called \(calls.spokenList)."
        case let .play(cards):
            guard bidding == nil else { throw Rejection.illegal("Bidding isn't over yet.") }
            let result: PlayOutcome
            do {
                result = try round.play(cards, by: seat)
            } catch let error as RoundError {
                throw Rejection.illegal(error.explanation)
            }
            var played = cards
            if case let .throwFailed(forced, blocker) = result {
                played = forced
                outcome = .throwFailed(forced: forced, blocker: blocker)
            }
            lastEvent = "\(name(seat)) played \(round.trump.sorted(played).shortText)"
            if round.phase == .finished { finishRound() }
        }
        updatedAt = now
        return outcome
    }

    private mutating func finishRound() {
        guard let result = round.result else { return }
        game.record(result)
        guard game.winner == nil else { return }
        round = game.makeRound(rng: &rng)
        round.dealAll()
        bidding = Bidding(turn: game.nextDealer ?? 0, passes: 0, history: [])
    }

    /// One automatic action (bot logic) for whoever must act. False if nothing could be done.
    @discardableResult
    mutating func autoStep(now: Date = Date()) -> Bool {
        guard let seat = actingSeat else { return false }
        let bot = Bot(seat: seat, level: botLevels[seat] ?? .standard)
        if bidding != nil {
            if let declaration = bot.declaration(in: round), attempt(.bid(declaration), by: seat, now: now) {
                return true
            }
            return attempt(.pass, by: seat, now: now)
        }
        switch round.phase {
        case .burying:
            let cards = bot.cardsToBury(in: round).cards
            if attempt(.bury(cards, calls: bot.friendCalls(in: round, buried: cards)), by: seat, now: now) { return true }
            let fallback = Array(round.hands[seat].prefix(round.kittySize))
            return attempt(.bury(fallback, calls: bot.friendCalls(in: round, buried: fallback)), by: seat, now: now)
        case .playing:
            if attempt(.play(bot.decide(in: round).cards), by: seat, now: now) { return true }
            guard let fallback = GameController.fallbackPlay(for: seat, in: round) else { return false }
            return attempt(.play(fallback), by: seat, now: now)
        case .dealing, .finished:
            return false
        }
    }

    /// True if the action was accepted.
    private mutating func attempt(_ action: OnlineAction, by seat: Int, now: Date) -> Bool {
        do {
            _ = try act(action, by: seat, now: now)
            return true
        } catch {
            return false
        }
    }

    /// Bots (and, in the demo, friends) act until a seat in `humans` must act or `stop` says so.
    mutating func runAutomatic(humans: Set<Int>, now: Date = Date(), stop: (OnlineDemoGame) -> Bool = { _ in false }) {
        var steps = 0
        while let seat = actingSeat, !humans.contains(seat), !stop(self), steps < 600 {
            guard autoStep(now: now) else { break }
            steps += 1
        }
    }

    // MARK: What seat 0 sees

    func view() -> SeatView {
        var view = round.seatView(for: 0, players: players, game: game)
        if archived {
            view.phase = .finished
            view.hand = []
            view.handCounts = Array(repeating: 0, count: players.count)
            view.turn = nil
            view.bidding = nil
            view.kitty = nil
            view.currentTrick = []
            view.tricks = []
            view.declaration = nil
            view.declarationHistory = []
            view.roundNumber = max(1, game.roundsPlayed)
            view.defenderTrickPoints = 0
            view.result = nil
        } else if let bidding {
            view.phase = .bidding
            view.turn = nil
            view.bidding = SeatView.Bidding(turn: bidding.turn, history: bidding.history,
                                            available: bidding.turn == 0 ? round.availableDeclarations(for: 0) : [])
        }
        view.gameWinnerTeam = game.winner
        return view
    }

    func summary() -> OnlineGameSummary {
        let view = view()
        let acting = actingSeat
        return OnlineGameSummary(id: id, clubId: clubId, createdAt: OnlineDates.string(createdAt),
                                 updatedAt: OnlineDates.string(updatedAt), status: isOver ? .finished : .active,
                                 players: players, teamLevels: game.levels, targetRank: game.settings.targetRank,
                                 roundNumber: view.roundNumber, phase: view.phase, turn: acting, yourTurn: acting == 0,
                                 winnerTeam: game.winner, lastEvent: lastEvent,
                                 startedByYou: players.first?.userID == creatorID)
    }

    var state: OnlineGameState { OnlineGameState(game: summary(), view: view(), version: version) }
}
