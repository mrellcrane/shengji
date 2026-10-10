import Foundation

// API CONTRACT (stub). Filled in by the bot work.

/// A bot's chosen action plus a short, learner-facing reason (used for hints and coaching).
public struct BotDecision: Hashable, Sendable {
    public var cards: [Card]
    /// One sentence in plain English, e.g. "Partner is winning this trick, so give them points (K♠)."
    public var reason: String
    /// Short tag for the strategy concept, e.g. "Feed points", "Sure winner", "Ruff", "Duck low".
    public var concept: String

    public init(cards: [Card], reason: String, concept: String) {
        self.cards = cards
        self.reason = reason
        self.concept = concept
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
