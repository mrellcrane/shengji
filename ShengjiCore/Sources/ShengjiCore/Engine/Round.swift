import Foundation

// API CONTRACT (stub). Filled in by the engine work.

/// A bid for trump made by revealing cards during the deal (亮主).
public struct Declaration: Hashable, Codable, Sendable, CustomStringConvertible {
    public var player: Int
    /// The revealed cards: one or two trump-rank cards of one suit, or two identical jokers.
    public var cards: [Card]
    /// Trump suit chosen; nil = no trump suit (joker pair).
    public var suit: Suit?
    /// 1 = single rank card, 2 = pair of rank cards, 3 = pair of small jokers, 4 = pair of big jokers.
    public var strength: Int

    public init(player: Int, cards: [Card], suit: Suit?, strength: Int) {
        self.player = player
        self.cards = cards
        self.suit = suit
        self.strength = strength
    }

    /// e.g. "East declares ♥ with 2♥", "You declare no trump with two big jokers"
    public var description: String { fatalError("TODO") }
}

public enum RoundPhase: String, Codable, Sendable {
    /// Cards are being dealt one at a time; players may declare trump.
    case dealing
    /// Dealer has picked up the kitty and must bury 8 cards.
    case burying
    case playing
    case finished
}

public struct TrickRecord: Hashable, Codable, Sendable {
    public var plays: [Play]
    /// Player who won the trick.
    public var winner: Int
    /// Point value of all cards in the trick.
    public var points: Int

    public init(plays: [Play], winner: Int, points: Int) {
        self.plays = plays
        self.winner = winner
        self.points = points
    }

    public var leader: Int { plays[0].player }
}

public struct RoundResult: Hashable, Codable, Sendable {
    public var dealer: Int
    public var declarerTeam: Int
    public var trump: Trump
    /// Points the defenders captured in tricks.
    public var trickPoints: Int
    /// Raw point value of the buried kitty.
    public var kittyPoints: Int
    /// 0 if the declarers won the last trick; otherwise 2/4/8/... (see Scoring.kittyMultiplier).
    public var kittyMultiplier: Int
    /// trickPoints + kittyPoints * kittyMultiplier.
    public var defenderPoints: Int
    public var outcome: LevelOutcome
    public var kitty: [Card]
    public var lastTrickWinner: Int

    public init(dealer: Int, declarerTeam: Int, trump: Trump, trickPoints: Int, kittyPoints: Int,
                kittyMultiplier: Int, defenderPoints: Int, outcome: LevelOutcome, kitty: [Card], lastTrickWinner: Int) {
        self.dealer = dealer
        self.declarerTeam = declarerTeam
        self.trump = trump
        self.trickPoints = trickPoints
        self.kittyPoints = kittyPoints
        self.kittyMultiplier = kittyMultiplier
        self.defenderPoints = defenderPoints
        self.outcome = outcome
        self.kitty = kitty
        self.lastTrickWinner = lastTrickWinner
    }
}

/// Outcome of a successful `play` call.
public enum PlayOutcome: Equatable, Sendable {
    case played
    /// The lead was a throw that failed; only `forced` was played. `blocker` could beat part of it.
    case throwFailed(forced: [Card], blocker: Int)
}

public enum RoundError: Error, Equatable, Sendable {
    case wrongPhase
    case notYourTurn
    case illegalLead(LeadViolation)
    case illegalFollow(FollowViolation)
    case invalidDeclaration
    case invalidBury(String)

    /// Learner-facing explanation.
    public var explanation: String { fatalError("TODO") }
}

/// The complete state of one deal (one "round"), from dealing to scoring.
/// Value type: every mutation goes through the mutating methods below, which enforce the rules.
public struct Round: Codable, Sendable {
    public static let kittySize = 8
    public static let handSize = 25

    /// Trump rank for this round (the dealer team's level).
    public private(set) var trumpRank: Rank
    /// Dealer (庄家). Nil only during the first round's deal, before anyone has declared.
    public private(set) var dealer: Int?
    public private(set) var phase: RoundPhase
    /// Four hands, indexed by seat. Not kept sorted; use `trump.sorted` for display.
    public private(set) var hands: [[Card]]
    /// Cards still to be dealt (dealing phase).
    public private(set) var undealt: [Card]
    /// During dealing/burying: the original 8 kitty cards (face down).
    /// After burying: the 8 cards the dealer buried.
    public private(set) var kitty: [Card]
    /// Current winning declaration, if any.
    public private(set) var declaration: Declaration?
    /// Every declaration in order (for the UI log and bots).
    public private(set) var declarationHistory: [Declaration]
    /// Trump context. During dealing `suit` reflects the current declaration (nil if none yet).
    public private(set) var trump: Trump
    /// Seat that receives the next dealt card.
    public private(set) var nextToReceive: Int
    /// Plays so far in the trick in progress (empty between tricks).
    public private(set) var currentTrick: [Play]
    public private(set) var tricks: [TrickRecord]
    /// Seat that leads the current trick.
    public private(set) var leader: Int
    /// Points captured by the defenders in tricks so far.
    public private(set) var defenderTrickPoints: Int
    /// If nobody declared, the kitty card that fixed the trump suit (see DESIGN.md §Declaring).
    public private(set) var trumpFromKitty: Card?
    /// Set when phase == .finished.
    public private(set) var result: RoundResult?

    /// `deck` must be all 108 cards in dealing order: the first 100 are dealt one at a time
    /// starting with `dealer ?? 0`, the last 8 are the kitty.
    public init(trumpRank: Rank, dealer: Int?, deck: [Card]) { fatalError("TODO") }

    public init<G: RandomNumberGenerator>(trumpRank: Rank, dealer: Int?, rng: inout G) {
        self.init(trumpRank: trumpRank, dealer: dealer, deck: Deck.shuffled(using: &rng))
    }

    // MARK: Dealing & declaring

    public var isDealingComplete: Bool { fatalError("TODO") }

    /// Deals one card to `nextToReceive`. Returns nil when all 100 cards are dealt.
    @discardableResult
    public mutating func dealNext() -> (player: Int, card: Card)? { fatalError("TODO") }

    public mutating func dealAll() { fatalError("TODO") }

    /// Declarations `player` could make right now with the cards in hand. A new declaration must
    /// be strictly stronger than the current one; a player who holds the current declaration may
    /// only strengthen it in the same suit (single → pair). Partners may override each other.
    public func availableDeclarations(for player: Int) -> [Declaration] { fatalError("TODO") }

    /// Throws `.invalidDeclaration` unless `d` is in `availableDeclarations(for: d.player)`
    /// (compared by player, suit and strength; cards must be in hand).
    public mutating func declare(_ d: Declaration) throws { fatalError("TODO") }

    /// Closes the declaration window (requires dealing complete). Fixes trump suit (from the
    /// declaration, else from the kitty — DESIGN.md §Declaring), fixes the dealer (first round:
    /// the winning declarer, else seat 0), gives the kitty to the dealer, and moves to `.burying`.
    public mutating func finishDealing() { fatalError("TODO") }

    // MARK: Burying

    /// Dealer buries exactly 8 cards from their (33-card) hand → `.playing`, dealer leads.
    public mutating func bury(_ cards: [Card]) throws { fatalError("TODO") }

    // MARK: Playing

    /// Whose turn it is to play (nil outside `.playing`).
    public var turn: Int? { fatalError("TODO") }

    /// Team of the dealer (nil before the dealer is known).
    public var declarerTeam: Int? { fatalError("TODO") }

    public func isDefender(_ player: Int) -> Bool { fatalError("TODO") }

    /// Cards of the lead of the current trick (empty if none yet).
    public var currentLead: [Card] { fatalError("TODO") }

    /// Validation without side effects. For leads, does NOT run the throw check.
    public func legalityError(for cards: [Card], by player: Int) -> RoundError? { fatalError("TODO") }

    /// Plays cards for the player whose turn it is. Leads that are throws are checked against
    /// the other hands; a failing throw plays only the forced component. When the 4th play lands
    /// the trick is scored and appended to `tricks`, `currentTrick` is emptied and the winner leads.
    /// After the last trick the round is scored (`result`, phase `.finished`).
    @discardableResult
    public mutating func play(_ cards: [Card], by player: Int) throws -> PlayOutcome { fatalError("TODO") }

    /// All cards played so far (completed tricks plus the trick in progress).
    public var playedCards: [Card] { fatalError("TODO") }

    public var lastTrick: TrickRecord? { tricks.last }
}
