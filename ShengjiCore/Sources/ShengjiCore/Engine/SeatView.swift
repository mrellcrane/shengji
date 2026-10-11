import Foundation

/// Everything one seat can see at the table, with seats rotated so the viewer is seat 0
/// (seat 1 = the viewer's right, 2 = partner, 3 = left; team 0 = the viewer's team). Bigger tables
/// go on round the same way: with 6 or 8 players `players` has 6 or 8 entries, the viewer's team is
/// every even seat and the opponents every odd one. With an odd number of players (Finding Friends)
/// there are no fixed teams: the dealer's side is the dealer plus the friends found so far
/// (`friendCalls`), levels are per seat, and team 0 means the viewer's side.
///
/// This is the single model behind both offline and online play:
///  - offline, `Round.seatView(...)` builds it from the full round;
///  - online, the server sends it as JSON (this type's Codable form is the wire format: cards are
///    integer ids, suits and ranks their raw values, absent optionals may be omitted or null).
/// It never contains other players' hands, the undealt deck, or a kitty the viewer may not see.
public struct SeatView: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable {
        /// Offline only: cards still arriving, declarations allowed.
        case dealing
        /// Online only: everyone holds 25 cards and takes turns to declare or pass.
        case bidding
        case burying
        case playing
        case finished
    }

    public struct Player: Codable, Hashable, Sendable {
        public var name: String
        public var isBot: Bool
        /// Online user id (nil for bots and offline seats).
        public var userID: String?

        public init(name: String, isBot: Bool, userID: String? = nil) {
            self.name = name
            self.isBot = isBot
            self.userID = userID
        }
    }

    /// One turn in online bidding: a declaration, or a pass when `declaration` is nil.
    public struct Bid: Codable, Hashable, Sendable {
        public var player: Int
        public var declaration: Declaration?

        public init(player: Int, declaration: Declaration?) {
            self.player = player
            self.declaration = declaration
        }
    }

    /// Online bidding state (nil offline and once bidding is over).
    public struct Bidding: Codable, Hashable, Sendable {
        /// Whose turn it is to declare or pass.
        public var turn: Int?
        public var history: [Bid]
        /// Declarations the viewer could make right now (empty unless it is the viewer's turn).
        public var available: [Declaration]

        public init(turn: Int?, history: [Bid], available: [Declaration]) {
            self.turn = turn
            self.history = history
            self.available = available
        }
    }

    /// Players in seat order; index 0 is the viewer.
    public var players: [Player]
    /// Levels as [viewer's team, other team]. With Finding Friends one level per seat, the viewer's first.
    public var teamLevels: [Rank]
    public var targetRank: Rank
    /// 1-based round number within the game.
    public var roundNumber: Int
    public var phase: Phase
    /// Trump rank, and trump suit once known (nil = not decided yet, or a no-trump round).
    public var trump: Trump
    /// Set when nobody declared and the kitty flip fixed the trump suit.
    public var trumpFromKitty: Card?
    public var dealer: Int?
    /// The viewer's own cards (not sorted).
    public var hand: [Card]
    /// Cards held by each seat.
    public var handCounts: [Int]
    /// The current winning declaration (revealed cards are public).
    public var declaration: Declaration?
    public var declarationHistory: [Declaration]
    public var bidding: Bidding?
    /// Visible only to the dealer once they hold it, and to everyone when the round is finished.
    public var kitty: [Card]?
    public var currentTrick: [Play]
    public var leader: Int
    /// Whose turn it is to play or bury (nil when nobody needs to act).
    public var turn: Int?
    public var tricks: [TrickRecord]
    public var defenderTrickPoints: Int
    /// The finished round's result (phase `.finished`).
    public var result: RoundResult?
    /// The previous round's summary (online: shown while the next round has already started).
    public var lastRoundSummary: RoundSummary?
    /// Viewer-relative winning team when the game is over (with Finding Friends 0 if the viewer won).
    public var gameWinnerTeam: Int?
    /// Finding Friends: the friends the dealer called (nil before burying and at tables of fixed teams),
    /// each with the seat that played the called card once it has been played.
    public var friendCalls: [FriendCall]?

    public init(players: [Player], teamLevels: [Rank], targetRank: Rank, roundNumber: Int, phase: Phase, trump: Trump,
                trumpFromKitty: Card?, dealer: Int?, hand: [Card], handCounts: [Int], declaration: Declaration?,
                declarationHistory: [Declaration], bidding: Bidding?, kitty: [Card]?, currentTrick: [Play], leader: Int,
                turn: Int?, tricks: [TrickRecord], defenderTrickPoints: Int, result: RoundResult?,
                lastRoundSummary: RoundSummary?, gameWinnerTeam: Int?, friendCalls: [FriendCall]? = nil) {
        self.players = players
        self.teamLevels = teamLevels
        self.targetRank = targetRank
        self.roundNumber = roundNumber
        self.phase = phase
        self.trump = trump
        self.trumpFromKitty = trumpFromKitty
        self.dealer = dealer
        self.hand = hand
        self.handCounts = handCounts
        self.declaration = declaration
        self.declarationHistory = declarationHistory
        self.bidding = bidding
        self.kitty = kitty
        self.currentTrick = currentTrick
        self.leader = leader
        self.turn = turn
        self.tricks = tricks
        self.defenderTrickPoints = defenderTrickPoints
        self.result = result
        self.lastRoundSummary = lastRoundSummary
        self.gameWinnerTeam = gameWinnerTeam
        self.friendCalls = friendCalls
    }

    // MARK: Convenience

    /// True at a table with an odd number of players: no fixed teams, the dealer calls friends.
    public var findsFriends: Bool { table.findsFriends }

    /// Team of the dealer (viewer-relative), nil before the dealer is known. With Finding Friends: 0 while
    /// the viewer is the dealer or a friend found so far, else 1.
    public var declarerTeam: Int? {
        guard let dealer else { return nil }
        return findsFriends ? (isDeclarer(0) ? 0 : 1) : Seats.team(of: dealer)
    }

    /// The dealer's side as far as anyone can see, the dealer first and then in play order: the dealer's
    /// team, or with Finding Friends the dealer and the friends found so far. Empty before the dealer is known.
    public var declarers: [Int] {
        guard let dealer else { return [] }
        let n = playerCount
        let seats = findsFriends
            ? [dealer] + (friendCalls ?? []).compactMap(\.friend)
            : Seats.all(players: n).filter { Seats.team(of: $0) == Seats.team(of: dealer) }
        return Array(Set(seats)).sorted { Seats.normalized($0 - dealer, players: n) < Seats.normalized($1 - dealer, players: n) }
    }

    /// True if `seat` is known to be on the dealer's side.
    public func isDeclarer(_ seat: Int) -> Bool {
        guard let dealer else { return false }
        if findsFriends { return seat == dealer || (friendCalls ?? []).contains { $0.friend == seat } }
        return Seats.team(of: seat) == Seats.team(of: dealer)
    }

    /// True if `seat` is against the dealer's side. With Finding Friends a hidden friend counts as a
    /// defender until they play the called card.
    public func isDefender(_ seat: Int) -> Bool {
        dealer != nil && !isDeclarer(seat)
    }

    /// Friends called but not played yet.
    public var friendsToFind: Int { (friendCalls ?? []).filter { $0.friend == nil }.count }

    /// Cards of the lead of the trick in progress (empty if none yet).
    public var currentLead: [Card] { currentTrick.first?.cards ?? [] }

    /// Every card played so far this round (finished tricks plus the trick in progress).
    public var playedCards: [Card] { tricks.flatMap { $0.plays.flatMap(\.cards) } + currentTrick.flatMap(\.cards) }

    public var isViewerTurn: Bool { turn == 0 || bidding?.turn == 0 }

    /// Players and decks at this table (from the number of seats: 4 to 9).
    public var table: TableSize { TableSize(players: handCounts.isEmpty ? players.count : handCounts.count) }

    /// Number of seats.
    public var playerCount: Int { table.players }
}

// MARK: - Building views from a Round (offline, and the reference for the server)

extension Round {
    /// The view of `viewer`, rotated so the viewer is seat 0. `players` are in absolute seat order;
    /// `game` supplies levels, target and round number (defaults are used without it).
    public func seatView(for viewer: Int, players: [SeatView.Player]? = nil, game: GameState? = nil) -> SeatView {
        let n = self.players
        let v = Seats.normalized(viewer, players: n)
        func seat(_ s: Int) -> Int { Seats.normalized(s - v, players: n) }
        func rotateTeams<T>(_ values: [T]) -> [T] {
            guard values.count == 2 else { return values }
            var out = values
            out[(0 + v) % 2] = values[0]
            out[(1 + v) % 2] = values[1]
            return out
        }
        func rotate(_ d: Declaration) -> Declaration {
            Declaration(player: seat(d.player), cards: d.cards, suit: d.suit, strength: d.strength)
        }
        func rotate(_ p: Play) -> Play { Play(player: seat(p.player), cards: p.cards) }
        func rotate(_ t: TrickRecord) -> TrickRecord {
            TrickRecord(plays: t.plays.map(rotate), winner: seat(t.winner), points: t.points)
        }

        let absolutePlayers = players
            ?? Seats.all(players: n).map { SeatView.Player(name: Seats.name($0, players: n), isBot: $0 != Seats.human) }
        let rotatedPlayers = (0..<n).map { absolutePlayers[(($0 + v) % n) % max(absolutePlayers.count, 1)] }

        let levels: [Rank]
        if isFindingFriends {
            let all = game?.levels ?? Array(repeating: trumpRank, count: n)
            levels = (0..<n).map { all.indices.contains(($0 + v) % n) ? all[($0 + v) % n] : trumpRank }
        } else {
            levels = rotateTeams(game?.levels ?? [trumpRank, trumpRank])
        }
        let viewPhase: SeatView.Phase
        switch phase {
        case .dealing: viewPhase = .dealing
        case .burying: viewPhase = .burying
        case .playing: viewPhase = .playing
        case .finished: viewPhase = .finished
        }

        let kittyVisible: Bool
        switch phase {
        case .dealing: kittyVisible = false
        case .burying, .playing: kittyVisible = dealer == v
        case .finished: kittyVisible = true
        }

        let target = game?.settings.targetRank ?? .ace
        var lastSummary = game?.history.last
        if let summary = lastSummary {
            lastSummary = summary.rotated(by: v, target: target, players: n)
        }
        let winnerTeam = game?.winner.map { winner in
            game?.history.last.map { RoundResult.teamRotation(of: $0.result, by: v, players: n)(winner) } ?? winner
        }

        return SeatView(
            players: rotatedPlayers,
            teamLevels: levels,
            targetRank: target,
            roundNumber: (game?.roundsPlayed ?? 0) + (phase == .finished && game?.history.last?.result == result ? 0 : 1),
            phase: viewPhase,
            trump: trump,
            trumpFromKitty: trumpFromKitty,
            dealer: dealer.map(seat),
            hand: hands.indices.contains(v) ? hands[v] : [],
            handCounts: (0..<n).map { hands.indices.contains(($0 + v) % n) ? hands[($0 + v) % n].count : 0 },
            declaration: declaration.map(rotate),
            declarationHistory: declarationHistory.map(rotate),
            bidding: nil,
            kitty: kittyVisible ? kitty : nil,
            currentTrick: currentTrick.map(rotate),
            leader: seat(leader),
            turn: turn.map(seat) ?? ((phase == .burying) ? dealer.map(seat) : nil),
            tricks: tricks.map(rotate),
            defenderTrickPoints: defenderTrickPoints,
            result: result.map { $0.rotated(by: v, players: n) },
            lastRoundSummary: lastSummary,
            gameWinnerTeam: winnerTeam,
            friendCalls: isFindingFriends && phase != .dealing && phase != .burying
                ? friendCalls.map { $0.rotated(by: v, players: n) } : nil)
    }
}

extension FriendCall {
    /// The same call with the friend's seat seen from `viewer` (who becomes seat 0).
    public func rotated(by viewer: Int, players: Int) -> FriendCall {
        FriendCall(face: face, ordinal: ordinal, friend: friend.map { Seats.normalized($0 - viewer, players: players) })
    }
}

extension RoundResult {
    /// How team numbers change when `viewer` becomes seat 0: with fixed teams (t + viewer) % 2; with Finding
    /// Friends (team 0 = seat 0's side) they swap when the viewer was on the other side from seat 0.
    static func teamRotation(of result: RoundResult, by viewer: Int, players: Int) -> (Int) -> Int {
        let v = Seats.normalized(viewer, players: players)
        guard result.declarers != nil else { return { ($0 + v) % 2 } }
        let sameSide = result.isDeclarer(v) == result.isDeclarer(0)
        return { sameSide ? $0 : 1 - $0 }
    }

    /// The same result from `viewer`'s point of view (seats and teams rotated) at a table of `players`.
    public func rotated(by viewer: Int, players: Int) -> RoundResult {
        let n = max(players, 1)
        let v = Seats.normalized(viewer, players: n)
        guard v != 0 else { return self }
        func seat(_ s: Int) -> Int { Seats.normalized(s - v, players: n) }
        let team = RoundResult.teamRotation(of: self, by: v, players: n)
        return RoundResult(dealer: seat(dealer), declarerTeam: team(declarerTeam), trump: trump,
                           trickPoints: trickPoints, kittyPoints: kittyPoints, kittyMultiplier: kittyMultiplier,
                           defenderPoints: defenderPoints, outcome: outcome, kitty: kitty,
                           lastTrickWinner: seat(lastTrickWinner), declarers: declarers?.map(seat),
                           friendCalls: friendCalls?.map { $0.rotated(by: v, players: n) })
    }
}

extension RoundSummary {
    /// The same summary from `viewer`'s point of view (seats and teams rotated, explanation rewritten),
    /// at a table of `players`.
    public func rotated(by viewer: Int, target: Rank, players: Int = 4) -> RoundSummary {
        let n = TableSize(players: players).players
        let v = Seats.normalized(viewer, players: n)
        guard v != 0 else { return self }
        func seat(_ s: Int) -> Int { Seats.normalized(s - v, players: n) }
        let team = RoundResult.teamRotation(of: result, by: v, players: n)
        let rotatedResult = result.rotated(by: v, players: n)
        let next = seat(nextDealer)

        if TableSize(players: n).findsFriends {
            func rotateSeats(_ values: [Rank]) -> [Rank] {
                guard values.count == n else { return values }
                return (0..<n).map { values[($0 + v) % n] }
            }
            var summary = RoundSummary(
                result: rotatedResult, advancingTeam: advancingTeam.map(team), levelsGained: levelsGained,
                levelsBefore: rotateSeats(levelsBefore), levelsAfter: rotateSeats(levelsAfter), nextDealer: next,
                gameWinner: gameWinner.map(team), explanation: "")
            summary.explanation = GameState.explainFindingFriends(summary, target: target, players: n)
            return summary
        }

        func rotateTeams(_ values: [Rank]) -> [Rank] {
            guard values.count == 2 else { return values }
            var out = values
            out[team(0)] = values[0]
            out[team(1)] = values[1]
            return out
        }
        let after = rotateTeams(levelsAfter)
        let benefiting = rotatedResult.outcome.declarersHold ? rotatedResult.declarerTeam : 1 - rotatedResult.declarerTeam
        let explanation = GameState.explain(
            result: rotatedResult, team: benefiting, nominal: rotatedResult.outcome.levels, gained: levelsGained,
            newLevel: after[benefiting], gameWinner: gameWinner.map(team), target: target, nextDealer: next,
            nextLevel: after[Seats.team(of: next)], players: n)
        return RoundSummary(result: rotatedResult, advancingTeam: advancingTeam.map(team), levelsGained: levelsGained,
                            levelsBefore: rotateTeams(levelsBefore), levelsAfter: after, nextDealer: next,
                            gameWinner: gameWinner.map(team), explanation: explanation)
    }
}
