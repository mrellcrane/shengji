import Foundation

public struct GameSettings: Hashable, Codable, Sendable {
    /// Both teams start here.
    public var startRank: Rank
    /// A team wins by holding the deal as declarers while at this level.
    /// Levels gained are capped here ("you must defend your last level").
    public var targetRank: Rank

    public init(startRank: Rank = .two, targetRank: Rank = .ace) {
        self.startRank = startRank
        self.targetRank = targetRank
    }
}

/// What changed after a round, for the results screen.
public struct RoundSummary: Hashable, Codable, Sendable {
    public var result: RoundResult
    /// Team whose level went up (nil if nobody advanced).
    public var advancingTeam: Int?
    public var levelsGained: Int
    public var levelsBefore: [Rank]
    public var levelsAfter: [Rank]
    public var nextDealer: Int
    /// Set when this round ended the game.
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

/// A whole game: a sequence of rounds while the teams climb levels from 2 to A.
public struct GameState: Codable, Sendable {
    public private(set) var settings: GameSettings
    /// Level per team (team 0 = you + partner, team 1 = East + West).
    public private(set) var levels: [Rank]
    /// Dealer of the next round; nil before the first round (decided by declaring).
    public private(set) var nextDealer: Int?
    /// Number of rounds completed.
    public private(set) var roundsPlayed: Int
    public private(set) var winner: Int?
    public private(set) var history: [RoundSummary]

    public init(settings: GameSettings = GameSettings()) {
        self.settings = settings
        self.levels = [settings.startRank, settings.startRank]
        self.nextDealer = nil
        self.roundsPlayed = 0
        self.winner = nil
        self.history = []
    }

    /// Trump rank of the next round: the dealer team's level (startRank in the first round).
    public var nextTrumpRank: Rank {
        guard let dealer = nextDealer else { return settings.startRank }
        let team = Seats.team(of: dealer)
        return levels.indices.contains(team) ? levels[team] : settings.startRank
    }

    public func makeRound<G: RandomNumberGenerator>(rng: inout G) -> Round {
        Round(trumpRank: nextTrumpRank, dealer: nextDealer, rng: &rng)
    }

    /// Applies a finished round. Next dealer: if declarers hold → dealer's partner;
    /// otherwise → the player after the dealer (a defender). Winner: declarers holding while at targetRank.
    @discardableResult
    public mutating func record(_ result: RoundResult) -> RoundSummary {
        if levels.count < 2 {
            // Only reachable with damaged saved data: restore a level for each team.
            levels += Array(repeating: settings.startRank, count: 2 - levels.count)
        }
        let dealer = ((result.dealer % 4) + 4) % 4
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
        let next = outcome.declarersHold ? Seats.partner(of: dealer) : Seats.next(after: dealer)

        nextDealer = next
        roundsPlayed += 1
        if winner == nil { winner = gameWinner }

        let explanation = GameState.explain(
            result: result, team: benefiting, nominal: outcome.levels, gained: gained, newLevel: newLevel,
            gameWinner: gameWinner, target: target, nextDealer: next, nextLevel: levels[Seats.team(of: next)])
        let summary = RoundSummary(
            result: result, advancingTeam: gained > 0 ? benefiting : nil, levelsGained: gained,
            levelsBefore: before, levelsAfter: levels, nextDealer: next, gameWinner: gameWinner,
            explanation: explanation)
        history.append(summary)
        return summary
    }

    // MARK: Explanation text

    private static func explain(result: RoundResult, team: Int, nominal: Int, gained: Int, newLevel: Rank,
                                gameWinner: Int?, target: Rank, nextDealer: Int, nextLevel: Rank) -> String {
        let points = result.defenderPoints
        let kittyBonus = result.kittyPoints * result.kittyMultiplier
        let scored = kittyBonus > 0
            ? "The defenders scored \(points) points (including \(kittyBonus) from the kitty)"
            : "The defenders scored \(points) points"
        var sentences: [String] = []
        if result.outcome.declarersHold {
            sentences.append("\(scored), short of \(Scoring.takeoverThreshold), so the declarers keep the deal.")
        } else {
            sentences.append("\(scored), reaching \(Scoring.takeoverThreshold), so they take over the deal.")
        }

        let subject = teamSubject(team)
        if let winner = gameWinner {
            let ending = winner == Seats.team(of: Seats.human) ? "so you win the game!" : "so they win the game."
            sentences.append("\(teamSubject(winner).name) held the deal at level \(target.label), \(ending)")
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
        sentences.append("\(Seats.name(nextDealer)) \(dealerVerb) next at level \(nextLevel.label).")
        return sentences.joined(separator: " ")
    }

    private static func teamSubject(_ team: Int) -> (name: String, plural: Bool) {
        team == Seats.team(of: Seats.human) ? ("Your team", false) : ("East and West", true)
    }
}
