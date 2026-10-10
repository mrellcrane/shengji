import Foundation

// API CONTRACT (stub). Filled in by the engine work.

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

    public init(settings: GameSettings = GameSettings()) { fatalError("TODO") }

    /// Trump rank of the next round: the dealer team's level (startRank in the first round).
    public var nextTrumpRank: Rank { fatalError("TODO") }

    public func makeRound<G: RandomNumberGenerator>(rng: inout G) -> Round { fatalError("TODO") }

    /// Applies a finished round. Next dealer: if declarers hold → dealer's partner;
    /// otherwise → the player after the dealer (a defender). Winner: declarers holding while at targetRank.
    @discardableResult
    public mutating func record(_ result: RoundResult) -> RoundSummary { fatalError("TODO") }
}
