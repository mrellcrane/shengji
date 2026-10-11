import Foundation

/// A bid for trump made by revealing cards during the deal (亮主).
public struct Declaration: Hashable, Codable, Sendable, CustomStringConvertible {
    public var player: Int
    /// The revealed cards: trump-rank cards of one suit, or identical jokers (two or more).
    public var cards: [Card]
    /// Trump suit chosen; nil = no trump suit (jokers).
    public var suit: Suit?
    /// 1 = single rank card, 2 = pair of rank cards, 3 = pair of small jokers, 4 = pair of big jokers.
    /// With three or more decks more cards beat fewer: 5 = three rank cards, 6 = three small jokers,
    /// 7 = three big jokers, then 8 to 10 for four of each (see `strength(count:kind:)`).
    public var strength: Int

    public init(player: Int, cards: [Card], suit: Suit?, strength: Int) {
        self.player = player
        self.cards = cards
        self.suit = suit
        self.strength = strength
    }

    /// What a declaration shows: rank cards of one suit, small jokers or big jokers.
    public enum Kind: Int, Hashable, Sendable {
        case rankCards = 0, smallJokers, bigJokers
    }

    /// Strength of showing `count` identical cards of `kind` (jokers need at least two):
    /// one rank card 1; two: rank 2, small jokers 3, big jokers 4; three: 5, 6, 7; four: 8, 9, 10.
    public static func strength(count: Int, kind: Kind) -> Int {
        if count <= 1 { return 1 }
        return 3 * count - 4 + kind.rawValue
    }

    /// Cards shown for a strength (1 → 1, 2...4 → 2, 5...7 → 3, 8...10 → 4).
    public static func cardCount(forStrength strength: Int) -> Int {
        strength <= 1 ? 1 : (strength + 4) / 3
    }

    /// The kind of cards shown for a strength.
    public static func kind(forStrength strength: Int) -> Kind {
        strength <= 1 ? .rankCards : Kind(rawValue: (strength + 4) % 3) ?? .rankCards
    }

    /// Cards shown.
    public var cardCount: Int { Declaration.cardCount(forStrength: strength) }
    public var kind: Kind { Declaration.kind(forStrength: strength) }

    /// e.g. "East declares ♥ (one 2♥)", "You declare no trump (pair of big jokers)"
    public var description: String {
        let who = player == Seats.human ? "You declare" : "\(Seats.name(player)) declares"
        return "\(who) \(suit.map { $0.symbol } ?? "no trump") (\(detail))"
    }

    /// The cards shown, e.g. "one 2♥", "pair of 2♥", "three small jokers".
    public var detail: String {
        let shown = cards.first?.description
        switch strength {
        case 1: return shown.map { "one \($0)" } ?? "one trump-rank card"
        case 2: return shown.map { "pair of \($0)" } ?? "pair of trump-rank cards"
        case 3: return "pair of small jokers"
        case 4: return "pair of big jokers"
        case 5...:
            let count = FollowViolation.count(cardCount)
            switch kind {
            case .rankCards: return shown.map { "\(count) \($0)" } ?? "\(count) trump-rank cards"
            case .smallJokers: return "\(count) small jokers"
            case .bigJokers: return "\(count) big jokers"
            }
        default: return cards.shortText
        }
    }
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

    public var leader: Int { plays.first?.player ?? winner }
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
    public var explanation: String {
        switch self {
        case .wrongPhase:
            return "You can't do that at this point in the round."
        case .notYourTurn:
            return "Wait for your turn."
        case let .illegalLead(violation):
            return violation.explanation
        case let .illegalFollow(violation):
            return violation.explanation
        case .invalidDeclaration:
            return "You can't declare that right now. A declaration must beat the current one, "
                + "and if the current one is yours you can only strengthen it with more of the same card."
        case let .invalidBury(reason):
            return reason
        }
    }
}

/// The complete state of one deal (one "round"), from dealing to scoring.
/// Value type: every mutation goes through the mutating methods below, which enforce the rules.
public struct Round: Codable, Sendable {
    /// Kitty and hand sizes of the classic 4-player, 2-deck game (`kittySize` and `handSize` on a
    /// round give its own table's).
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
    /// Players and decks; absent in rounds saved before bigger tables existed (4 players, 2 decks).
    private var tableSize: TableSize?

    /// Players and decks at this table.
    public var table: TableSize { tableSize ?? .four }
    /// Number of seats (4, 6 or 8).
    public var players: Int { table.players }
    /// Cards the dealer picks up and buries: 8 with 4 or 8 players, 6 with 6.
    public var kittySize: Int { table.kittySize }
    /// Cards dealt to each player: 25 with 4 players, 26 with 6 or 8.
    public var handSize: Int { table.handSize }

    /// `deck` must be every card of the table's decks in dealing order (108 for 4 players): all but
    /// the kitty are dealt one at a time starting with `dealer ?? 0`, the last `kittySize` are the kitty.
    public init(trumpRank: Rank, dealer: Int?, deck: [Card], table: TableSize = .four) {
        precondition(deck.count == table.cardCount,
                     "A Shengji deal for \(table) needs all \(table.cardCount) cards (\(table.decks) decks with jokers).")
        let seat = dealer.map { Seats.normalized($0, players: table.players) }
        let dealtCount = deck.count - table.kittySize
        self.tableSize = table == .four ? nil : table
        self.trumpRank = trumpRank
        self.dealer = seat
        self.phase = .dealing
        self.hands = Array(repeating: [], count: table.players)
        self.undealt = Array(deck.prefix(dealtCount))
        self.kitty = Array(deck.suffix(table.kittySize))
        self.declaration = nil
        self.declarationHistory = []
        self.trump = Trump(rank: trumpRank, suit: nil)
        self.nextToReceive = seat ?? 0
        self.currentTrick = []
        self.tricks = []
        self.leader = seat ?? 0
        self.defenderTrickPoints = 0
        self.trumpFromKitty = nil
        self.result = nil
    }

    public init<G: RandomNumberGenerator>(trumpRank: Rank, dealer: Int?, rng: inout G, table: TableSize = .four) {
        self.init(trumpRank: trumpRank, dealer: dealer, deck: Deck.shuffled(decks: table.decks, using: &rng), table: table)
    }

    // MARK: Dealing & declaring

    public var isDealingComplete: Bool { undealt.isEmpty }

    /// Deals one card to `nextToReceive`. Returns nil when every card but the kitty is dealt.
    @discardableResult
    public mutating func dealNext() -> (player: Int, card: Card)? {
        guard phase == .dealing, !undealt.isEmpty else { return nil }
        let card = undealt.removeFirst()
        let player = nextToReceive
        hands[player].append(card)
        nextToReceive = Seats.next(after: player, players: players)
        return (player, card)
    }

    public mutating func dealAll() {
        while dealNext() != nil {}
    }

    /// Declarations `player` could make right now with the cards in hand. A new declaration must
    /// be strictly stronger than the current one; a player who holds the current declaration may
    /// only strengthen it with more of the same card (single → pair, and with three or more decks
    /// pair → triple). Partners may override each other.
    public func availableDeclarations(for player: Int) -> [Declaration] {
        guard phase == .dealing, hands.indices.contains(player) else { return [] }
        let hand = hands[player].sorted { $0.id < $1.id }
        var options: [Declaration] = []
        for suit in Suit.allCases {
            let rankCards = hand.filter { $0.face == .regular(suit, trumpRank) }
            guard !rankCards.isEmpty else { continue }
            for count in 1...rankCards.count {
                options.append(Declaration(player: player, cards: Array(rankCards.prefix(count)), suit: suit,
                                           strength: Declaration.strength(count: count, kind: .rankCards)))
            }
        }
        for (face, kind) in [(Face.smallJoker, Declaration.Kind.smallJokers), (.bigJoker, .bigJokers)] {
            let jokers = hand.filter { $0.face == face }
            guard jokers.count >= 2 else { continue }
            for count in 2...jokers.count {
                options.append(Declaration(player: player, cards: Array(jokers.prefix(count)), suit: nil,
                                           strength: Declaration.strength(count: count, kind: kind)))
            }
        }

        options.sort { a, b in
            a.strength != b.strength ? a.strength < b.strength : (a.suit?.rawValue ?? 9) < (b.suit?.rawValue ?? 9)
        }
        guard let current = declaration else { return options }
        if current.player == player {
            // Holding the current declaration: only more of the same card (a single becomes a pair).
            return options.filter { option in
                option.kind == current.kind && option.suit == current.suit && option.cardCount > current.cardCount
            }
        }
        return options.filter { $0.strength > current.strength }
    }

    /// Throws `.invalidDeclaration` unless `d` is in `availableDeclarations(for: d.player)`
    /// (compared by player, suit and strength; cards must be in hand).
    public mutating func declare(_ d: Declaration) throws {
        guard phase == .dealing, hands.indices.contains(d.player) else { throw RoundError.invalidDeclaration }
        let allowed = availableDeclarations(for: d.player).contains { $0.suit == d.suit && $0.strength == d.strength }
        guard allowed,
              Round.cardsMatchDeclaration(d.cards, suit: d.suit, strength: d.strength, rank: trumpRank),
              hands[d.player].containsAll(d.cards) else {
            throw RoundError.invalidDeclaration
        }
        declaration = d
        declarationHistory.append(d)
        trump.suit = d.suit
    }

    /// Closes the declaration window (requires dealing complete). Fixes trump suit (from the
    /// declaration, else from the kitty: DESIGN.md §Declaring), fixes the dealer (first round:
    /// the winning declarer, else seat 0), gives the kitty to the dealer, and moves to `.burying`.
    /// Does nothing if dealing is still in progress or the window is already closed.
    public mutating func finishDealing() {
        guard phase == .dealing, isDealingComplete else { return }
        if let current = declaration {
            trump.suit = current.suit
            trumpFromKitty = nil
        } else {
            let flip = Round.kittyFlip(kitty, rank: trumpRank)
            trump.suit = flip.suit
            trumpFromKitty = flip.card
        }
        let seat = dealer ?? declaration?.player ?? 0
        dealer = seat
        leader = seat
        hands[seat].append(contentsOf: kitty)
        phase = .burying
    }

    // MARK: Burying

    /// Dealer buries exactly `kittySize` cards (8 from 33 with 4 players) → `.playing`, dealer leads.
    public mutating func bury(_ cards: [Card]) throws {
        guard phase == .burying, let seat = dealer else { throw RoundError.wrongPhase }
        guard cards.count == kittySize else {
            throw RoundError.invalidBury("Choose exactly \(kittySize) cards to bury (you chose \(cards.count)).")
        }
        guard Set(cards.map(\.id)).count == cards.count else {
            throw RoundError.invalidBury("Each card can only be buried once.")
        }
        guard hands[seat].containsAll(cards) else {
            throw RoundError.invalidBury("You can only bury cards from your own hand.")
        }
        hands[seat].remove(cards: cards)
        kitty = cards
        phase = .playing
        leader = seat
    }

    // MARK: Playing

    /// Whose turn it is to play (nil outside `.playing`).
    public var turn: Int? {
        guard phase == .playing else { return nil }
        return (leader + currentTrick.count) % players
    }

    /// Team of the dealer (nil before the dealer is known).
    public var declarerTeam: Int? { dealer.map { Seats.team(of: $0) } }

    public func isDefender(_ player: Int) -> Bool {
        guard let team = declarerTeam else { return false }
        return Seats.team(of: player) != team
    }

    /// Cards of the lead of the current trick (empty if none yet).
    public var currentLead: [Card] { currentTrick.first?.cards ?? [] }

    /// Validation without side effects. For leads, does NOT run the throw check.
    public func legalityError(for cards: [Card], by player: Int) -> RoundError? {
        guard phase == .playing else { return .wrongPhase }
        guard turn == player, hands.indices.contains(player) else { return .notYourTurn }
        let hand = hands[player]
        if currentTrick.isEmpty {
            if let violation = Rules.validateLead(cards, hand: hand, trump: trump) { return .illegalLead(violation) }
        } else if let violation = Rules.validateFollow(cards, hand: hand, lead: currentLead, trump: trump) {
            return .illegalFollow(violation)
        }
        return nil
    }

    /// Plays cards for the player whose turn it is. Leads that are throws are checked against
    /// the other hands; a failing throw plays only the forced component. When the last play lands
    /// the trick is scored and appended to `tricks`, `currentTrick` is emptied and the winner leads.
    /// After the last trick the round is scored (`result`, phase `.finished`).
    @discardableResult
    public mutating func play(_ cards: [Card], by player: Int) throws -> PlayOutcome {
        if let error = legalityError(for: cards, by: player) { throw error }

        var played = cards
        var outcome = PlayOutcome.played
        if currentTrick.isEmpty, Rules.isThrow(cards, trump: trump),
           case let .fails(forced, blocker) = Rules.checkThrow(cards, leader: player, hands: hands, trump: trump) {
            played = forced.cards
            outcome = .throwFailed(forced: forced.cards, blocker: blocker)
        }

        hands[player].remove(cards: played)
        currentTrick.append(Play(player: player, cards: played))
        if currentTrick.count == players { completeTrick() }
        return outcome
    }

    /// All cards played so far (completed tricks plus the trick in progress).
    public var playedCards: [Card] {
        tricks.flatMap { $0.plays.flatMap(\.cards) } + currentTrick.flatMap(\.cards)
    }

    public var lastTrick: TrickRecord? { tricks.last }

    // MARK: Private

    private mutating func completeTrick() {
        let winnerIndex = Rules.winningIndex(currentTrick, trump: trump)
        let winner = currentTrick[winnerIndex].player
        let points = currentTrick.reduce(0) { $0 + $1.cards.points }
        if isDefender(winner) { defenderTrickPoints += points }
        let lead = currentLead
        tricks.append(TrickRecord(plays: currentTrick, winner: winner, points: points))
        currentTrick = []
        leader = winner
        if hands.allSatisfy({ $0.isEmpty }) { finishRound(lastLead: lead, lastWinner: winner) }
    }

    private mutating func finishRound(lastLead: [Card], lastWinner: Int) {
        let kittyPoints = kitty.points
        let multiplier = isDefender(lastWinner) ? Scoring.kittyMultiplier(lastLead: lastLead, trump: trump) : 0
        let defenderPoints = defenderTrickPoints + kittyPoints * multiplier
        let seat = dealer ?? 0
        result = RoundResult(
            dealer: seat, declarerTeam: Seats.team(of: seat), trump: trump,
            trickPoints: defenderTrickPoints, kittyPoints: kittyPoints, kittyMultiplier: multiplier,
            defenderPoints: defenderPoints, outcome: Scoring.outcome(defenderPoints: defenderPoints, decks: table.decks),
            kitty: kitty, lastTrickWinner: lastWinner)
        phase = .finished
    }

    /// True if `cards` are exactly what a declaration of that suit and strength reveals.
    static func cardsMatchDeclaration(_ cards: [Card], suit: Suit?, strength: Int, rank: Rank) -> Bool {
        guard strength >= 1, cards.count == Declaration.cardCount(forStrength: strength),
              Set(cards.map(\.id)).count == cards.count else { return false }
        switch Declaration.kind(forStrength: strength) {
        case .rankCards:
            guard let suit = suit else { return false }
            return cards.allSatisfy { $0.face == .regular(suit, rank) }
        case .smallJokers:
            return suit == nil && cards.count >= 2 && cards.allSatisfy { $0.face == .smallJoker }
        case .bigJokers:
            return suit == nil && cards.count >= 2 && cards.allSatisfy { $0.face == .bigJoker }
        }
    }

    /// Nobody declared: flip the kitty card by card. The first trump-rank card fixes its suit, a joker
    /// seen first means no trump suit; failing both, the suit of the highest card (first if tied).
    static func kittyFlip(_ kitty: [Card], rank: Rank) -> (suit: Suit?, card: Card?) {
        for card in kitty {
            if card.isJoker { return (nil, card) }
            if card.rank == rank { return (card.suit, card) }
        }
        var best: (card: Card, rank: Rank)?
        for card in kitty {
            guard let cardRank = card.rank else { continue }
            if let current = best, cardRank <= current.rank { continue }
            best = (card, cardRank)
        }
        return (best?.card.suit, best?.card)
    }
}
