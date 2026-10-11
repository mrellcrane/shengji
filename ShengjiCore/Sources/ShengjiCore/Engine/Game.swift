import Foundation

public struct GameSettings: Hashable, Codable, Sendable {
    /// Both teams start here.
    public var startRank: Rank
    /// A team wins by holding the deal as declarers while at this level.
    /// Levels gained are capped here ("you must defend your last level").
    public var targetRank: Rank
    /// Players and decks: 4 with 2 decks (the classic game), up to 9 with 5. Odd tables play Finding Friends.
    public var table: TableSize

    public init(startRank: Rank = .two, targetRank: Rank = .ace, table: TableSize = .four) {
        self.startRank = startRank
        self.targetRank = targetRank
        self.table = table
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startRank = try container.decode(Rank.self, forKey: .startRank)
        targetRank = try container.decode(Rank.self, forKey: .targetRank)
        // Settings saved before bigger tables existed are for 4 players.
        table = try container.decodeIfPresent(TableSize.self, forKey: .table) ?? .four
    }
}

/// What changed after a round, for the results screen.
public struct RoundSummary: Hashable, Codable, Sendable {
    public var result: RoundResult
    /// Team whose level went up (nil if nobody advanced). With Finding Friends: 0 if seat 0's side went up.
    public var advancingTeam: Int?
    /// Levels gained (with Finding Friends, the most any one player gained: levels stop at the target).
    public var levelsGained: Int
    /// Levels per team, or with Finding Friends per seat.
    public var levelsBefore: [Rank]
    public var levelsAfter: [Rank]
    public var nextDealer: Int
    /// Set when this round ended the game: the winning team (with Finding Friends 0 if seat 0 was on the
    /// dealer's side, which won; the winners are `result.declarers`).
    public var gameWinner: Int?
    /// Two or three plain-English sentences explaining what happened and why.
    public var explanation: String

    public init(result: RoundResult, advancingTeam: Int?, levelsGained: Int, levelsBefore: [Rank],
                levelsAfter: [Rank], nextDealer: Int, gameWinner: Int?, explanation: String) {
        self.result = result
        self.advancingTeam = advancingTeam
        self.levelsGained = levelsGained
        self.levelsBefore = levelsBefore
        self.levelsAfter = levelsAfter
        self.nextDealer = nextDealer
        self.gameWinner = gameWinner
        self.explanation = explanation
    }
}

/// A whole game: a sequence of rounds while the teams climb levels from 2 to A. With Finding Friends
/// (an odd number of players) everyone climbs on their own.
public struct GameState: Codable, Sendable {
    public private(set) var settings: GameSettings
    /// Level per team (team 0 = you and your partners, the even seats; team 1 = the odd seats).
    /// With Finding Friends: one level per seat.
    public private(set) var levels: [Rank]
    /// Dealer of the next round; nil before the first round (decided by declaring).
    public private(set) var nextDealer: Int?
    /// Number of rounds completed.
    public private(set) var roundsPlayed: Int
    /// The team that won the game. With Finding Friends: 0 if seat 0 was on the winning side, else 1
    /// (the winners are the last round's `result.declarers`).
    public private(set) var winner: Int?
    public private(set) var history: [RoundSummary]

    public init(settings: GameSettings = GameSettings()) {
        self.settings = settings
        self.levels = Array(repeating: settings.startRank, count: GameState.levelCount(settings.table))
        self.nextDealer = nil
        self.roundsPlayed = 0
        self.winner = nil
        self.history = []
    }

    /// Levels kept: one per team, or one per seat with Finding Friends.
    static func levelCount(_ table: TableSize) -> Int { table.findsFriends ? table.players : 2 }

    /// True when everyone keeps their own level and the dealer calls friends (an odd number of players).
    public var findsFriends: Bool { settings.table.findsFriends }

    /// The level `seat` plays at: their team's, or with Finding Friends their own.
    public func level(of seat: Int) -> Rank {
        let index = findsFriends ? Seats.normalized(seat, players: players) : Seats.team(of: seat)
        return levels.indices.contains(index) ? levels[index] : settings.startRank
    }

    /// Trump rank of the next round: the dealer's level (startRank in the first round).
    public var nextTrumpRank: Rank {
        guard let dealer = nextDealer else { return settings.startRank }
        return level(of: dealer)
    }

    public func makeRound<G: RandomNumberGenerator>(rng: inout G) -> Round {
        Round(trumpRank: nextTrumpRank, dealer: nextDealer, rng: &rng, table: settings.table)
    }

    /// Players at the table.
    public var players: Int { settings.table.players }

    /// Applies a finished round. Next dealer: if declarers hold → the dealer's next teammate (two seats
    /// on: the partner with 4 players); otherwise → the player after the dealer (a defender).
    /// Winner: declarers holding while at targetRank.
    @discardableResult
    public mutating func record(_ result: RoundResult) -> RoundSummary {
        if findsFriends { return recordFindingFriends(result) }
        if levels.count < 2 {
            // Only reachable with damaged saved data: restore a level for each team.
            levels += Array(repeating: settings.startRank, count: 2 - levels.count)
        }
        let players = self.players
        let dealer = Seats.normalized(result.dealer, players: players)
        let declarers = Seats.team(of: dealer)
        let defenders = 1 - declarers
        let outcome = result.outcome
        let before = levels
        let target = settings.targetRank

        let benefiting = outcome.declarersHold ? declarers : defenders
        let gameWinner: Int? = outcome.declarersHold && before[declarers] >= target ? declarers : nil
        let newLevel = before[benefiting].advanced(by: outcome.levels, cap: target)
        let gained = newLevel.rawValue - before[benefiting].rawValue
        levels[benefiting] = newLevel
        let next = Seats.normalized(dealer + (outcome.declarersHold ? 2 : 1), players: players)

        nextDealer = next
        roundsPlayed += 1
        if winner == nil { winner = gameWinner }

        let explanation = GameState.explain(
            result: result, team: benefiting, nominal: outcome.levels, gained: gained, newLevel: newLevel,
            gameWinner: gameWinner, target: target, nextDealer: next, nextLevel: levels[Seats.team(of: next)],
            players: players)
        let summary = RoundSummary(
            result: result, advancingTeam: gained > 0 ? benefiting : nil, levelsGained: gained,
            levelsBefore: before, levelsAfter: levels, nextDealer: next, gameWinner: gameWinner,
            explanation: explanation)
        history.append(summary)
        return summary
    }

    /// Finding Friends: everyone on the side that wins the round goes up on their own (levels stop at the
    /// target). Next dealer: if the dealer's side holds, its next player after the dealer (the dealer again
    /// if they played alone); otherwise the first defender after the dealer. The game is won when the
    /// dealer's side holds while the dealer is at the target level.
    private mutating func recordFindingFriends(_ result: RoundResult) -> RoundSummary {
        let n = players
        if levels.count < n {
            // Only reachable with damaged saved data: restore a level for each seat.
            levels += Array(repeating: settings.startRank, count: n - levels.count)
        }
        let dealer = Seats.normalized(result.dealer, players: n)
        let declarers = Set((result.declarers ?? []).map { Seats.normalized($0, players: n) }).union([dealer])
        let outcome = result.outcome
        let before = levels
        let target = settings.targetRank
        let holds = outcome.declarersHold
        let side = { (seat: Int) -> Int in declarers.contains(seat) == declarers.contains(0) ? 0 : 1 }

        var gained = 0
        for seat in 0..<n where declarers.contains(seat) == holds {
            let newLevel = before[seat].advanced(by: outcome.levels, cap: target)
            gained = max(gained, newLevel.rawValue - before[seat].rawValue)
            levels[seat] = newLevel
        }
        let gameWinner: Int? = holds && before[dealer] >= target ? side(dealer) : nil
        let after = (1..<n).map { Seats.normalized(dealer + $0, players: n) }
        let next = holds
            ? after.first { declarers.contains($0) } ?? dealer
            : after.first { !declarers.contains($0) } ?? Seats.next(after: dealer, players: n)

        nextDealer = next
        roundsPlayed += 1
        if winner == nil { winner = gameWinner }

        let advancing: Int? = gained > 0 ? (holds ? side(dealer) : 1 - side(dealer)) : nil
        let summary = RoundSummary(
            result: result, advancingTeam: advancing, levelsGained: gained, levelsBefore: before,
            levelsAfter: levels, nextDealer: next, gameWinner: gameWinner, explanation: "")
        var explained = summary
        explained.explanation = GameState.explainFindingFriends(summary, target: target, players: n)
        history.append(explained)
        return explained
    }

    // MARK: Explanation text

    /// The explanation of a Finding Friends round from seat 0's point of view (seat 0 is "you").
    static func explainFindingFriends(_ summary: RoundSummary, target: Rank, players: Int) -> String {
        let result = summary.result
        let n = players
        let threshold = Scoring.takeoverThreshold(decks: TableSize(players: n).decks)
        let declarers = result.declarers ?? [result.dealer]
        let points = result.defenderPoints
        let kittyBonus = result.kittyPoints * result.kittyMultiplier
        let scored = kittyBonus > 0
            ? "The defenders scored \(points) points (including \(kittyBonus) from the kitty)"
            : "The defenders scored \(points) points"
        /// "East, you and Northwest": seat 0 is "you" inside the list, "You" when it comes first.
        func names(_ seats: [Int]) -> String {
            let list = seats.enumerated().map { index, seat in
                seat == Seats.human && index > 0 ? "you" : Seats.name(seat, players: n)
            }
            switch list.count {
            case 0: return "Nobody"
            case 1: return list[0]
            default: return list.dropLast().joined(separator: ", ") + " and " + list[list.count - 1]
            }
        }
        var sentences: [String] = []
        if declarers.count == 1 {
            sentences.append("\(names(declarers)) played alone: no friend joined.")
        } else {
            sentences.append("\(names(declarers)) played together as the dealer's side.")
        }
        if result.outcome.declarersHold {
            sentences.append("\(scored), short of \(threshold), so the dealer's side keeps the deal.")
        } else {
            sentences.append("\(scored), reaching \(threshold), so they take over the deal.")
        }
        let fullSide = TableSize(players: n).teamSize
        let advancing = (0..<n).filter { (declarers.contains($0)) == result.outcome.declarersHold }
        if summary.gameWinner != nil {
            let ending = declarers.contains(0) ? "so you win the game!" : "so they win the game."
            sentences.append("\(Seats.name(result.dealer, players: n)) held the deal at level \(target.label), \(ending)")
            return sentences.joined(separator: " ")
        }
        let nominal = result.outcome.levels
        if nominal == 0 {
            sentences.append("Nobody goes up a level this time.")
        } else {
            let who = result.outcome.declarersHold
                ? (declarers.count == 1 ? Seats.name(result.dealer, players: n) : "The dealer's side")
                : "The defenders"
            let plural = who == "The defenders" || who == Seats.name(Seats.human, players: n)
            let verb = plural ? "go" : "goes"
            let bonus = result.outcome.declarersHold && declarers.count < fullSide
                ? " (1 of them for playing short-handed)" : ""
            let capped = advancing.contains { summary.levelsAfter[$0].rawValue - summary.levelsBefore[$0].rawValue < nominal }
            let capNote = capped ? ", but levels stop at \(target.label)" : ""
            sentences.append("\(who) \(verb) up \(Scoring.levelPhrase(nominal))\(bonus)\(capNote).")
        }
        if summary.levelsBefore.indices.contains(0), summary.levelsAfter.indices.contains(0),
           summary.levelsAfter[0] != summary.levelsBefore[0] {
            sentences.append("You are now at level \(summary.levelsAfter[0].label).")
        }
        let next = summary.nextDealer
        let nextLevel = summary.levelsAfter.indices.contains(next) ? summary.levelsAfter[next] : target
        let dealerVerb = next == Seats.human ? "deal" : "deals"
        sentences.append("\(Seats.name(next, players: n)) \(dealerVerb) next at level \(nextLevel.label).")
        return sentences.joined(separator: " ")
    }

    static func explain(result: RoundResult, team: Int, nominal: Int, gained: Int, newLevel: Rank,
                        gameWinner: Int?, target: Rank, nextDealer: Int, nextLevel: Rank, players: Int = 4) -> String {
        let threshold = Scoring.takeoverThreshold(decks: TableSize(players: players).decks)
        let points = result.defenderPoints
        let kittyBonus = result.kittyPoints * result.kittyMultiplier
        let scored = kittyBonus > 0
            ? "The defenders scored \(points) points (including \(kittyBonus) from the kitty)"
            : "The defenders scored \(points) points"
        var sentences: [String] = []
        if result.outcome.declarersHold {
            sentences.append("\(scored), short of \(threshold), so the declarers keep the deal.")
        } else {
            sentences.append("\(scored), reaching \(threshold), so they take over the deal.")
        }

        let subject = teamSubject(team, players: players)
        if let winner = gameWinner {
            let ending = winner == Seats.team(of: Seats.human) ? "so you win the game!" : "so they win the game."
            sentences.append("\(teamSubject(winner, players: players).name) held the deal at level \(target.label), \(ending)")
            return sentences.joined(separator: " ")
        }
        if nominal == 0 {
            sentences.append("Nobody goes up a level this time.")
        } else if gained == 0 {
            sentences.append("\(subject.name) \(subject.plural ? "stay" : "stays") at level \(newLevel.label), the top level.")
        } else {
            let verb = subject.plural ? "go" : "goes"
            let levelsText = Scoring.levelPhrase(gained)
            let capNote = gained < nominal ? " (levels stop at \(target.label))" : ""
            sentences.append("\(subject.name) \(verb) up \(levelsText), to \(newLevel.label)\(capNote).")
        }
        let dealerVerb = nextDealer == Seats.human ? "deal" : "deals"
        sentences.append("\(Seats.name(nextDealer, players: players)) \(dealerVerb) next at level \(nextLevel.label).")
        return sentences.joined(separator: " ")
    }

    static func teamSubject(_ team: Int, players: Int = 4) -> (name: String, plural: Bool) {
        if team == Seats.team(of: Seats.human) { return ("Your team", false) }
        return players > 4 ? ("The other team", false) : ("East and West", true)
    }
}
