import Foundation

// API CONTRACT (stub). Filled in by the bot work.

/// A bot's chosen action plus learner-facing explanations. The human's hint button walks a
/// three-step ladder built from these fields (least help first): `nudge` → `principle` → `cards` + `reason`.
public struct BotDecision: Hashable, Sendable {
    public var cards: [Card]
    /// One sentence in plain English naming the play and why, e.g.
    /// "Partner is winning this trick with the top spade, so give them your K♠ (10 points)."
    public var reason: String
    /// Short tag for the strategy concept, e.g. "Feed points", "Sure winner", "Ruff", "Duck low".
    public var concept: String
    /// Hint step 1: what to notice, WITHOUT revealing the play, e.g. "Look at who is winning this trick."
    public var nudge: String
    /// Hint step 2: the general principle that applies, without naming cards, e.g.
    /// "When your partner is sure to win a trick, give them your point cards."
    public var principle: String

    public init(cards: [Card], reason: String, concept: String, nudge: String = "", principle: String = "") {
        self.cards = cards
        self.reason = reason
        self.concept = concept
        self.nudge = nudge
        self.principle = principle
    }
}

/// What a bot (or the hint system, from the human's seat) knows: its own hand, every card
/// played so far, the kitty if it was the dealer, and which players have shown out of which suits.
/// Bots never look at other players' hands.
public struct BotKnowledge: Sendable {
    public let seat: Int
    public let trump: Trump
    /// Cards whose location is unknown to this seat (not in its hand, not played, not buried by it).
    public let unseen: [Card]
    /// voids[player] = groups that player is known to be out of.
    public let voids: [Set<SuitGroup>]

    public init(round: Round, seat: Int) { fatalError("TODO") }
}

public enum BotLevel: String, Codable, CaseIterable, Sendable {
    /// Plays legal cards with simple habits (follows low, wins with high cards when obvious).
    case beginner
    /// Counts cards, feeds partner points, ruffs, throws sure winners. Default.
    case standard
}

public struct Bot: Sendable {
    public var seat: Int
    public var level: BotLevel

    public init(seat: Int, level: BotLevel = .standard) {
        self.seat = seat
        self.level = level
    }

    /// Called during dealing (after each card this seat receives, and once when dealing completes).
    /// Returns a declaration from `round.availableDeclarations(for: seat)` or nil. Never overrides its partner.
    public func declaration(in round: Round) -> Declaration? { fatalError("TODO") }

    /// Dealer only, phase `.burying`: exactly 8 cards from the hand to bury.
    public func cardsToBury(in round: Round) -> BotDecision { fatalError("TODO") }

    /// Phase `.playing`, `round.turn == seat`: a legal lead or follow. Leads that are throws are
    /// only made when guaranteed to succeed against the unseen cards.
    public func decide(in round: Round) -> BotDecision { fatalError("TODO") }
}
