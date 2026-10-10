import Foundation

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

    public init(round: Round, seat: Int) {
        let me = ((seat % 4) + 4) % 4
        self.seat = me
        self.trump = round.trump
        var known = [Bool](repeating: false, count: 108)
        func mark(_ cards: [Card]) {
            for card in cards where known.indices.contains(card.id) { known[card.id] = true }
        }
        if round.hands.indices.contains(me) { mark(round.hands[me]) }
        for trick in round.tricks {
            for play in trick.plays { mark(play.cards) }
        }
        for play in round.currentTrick { mark(play.cards) }
        // Once the dealer has buried, the kitty holds exactly the cards they chose.
        let buried = round.phase == .playing || round.phase == .finished
        if buried && round.dealer == me { mark(round.kitty) }
        var unseen: [Card] = []
        unseen.reserveCapacity(108)
        for card in BotKnowledge.fullDeck where !known[card.id] { unseen.append(card) }
        self.unseen = unseen

        var shown = [Set<SuitGroup>](repeating: [], count: 4)
        for trick in round.tricks {
            BotKnowledge.noteVoids(trick.plays, trump: round.trump, into: &shown)
        }
        BotKnowledge.noteVoids(round.currentTrick, trump: round.trump, into: &shown)
        self.voids = shown
    }

    static let fullDeck: [Card] = Deck.double()

    /// A player whose play held fewer cards of the led group than the lead is out of that group.
    static func noteVoids(_ plays: [Play], trump: Trump, into voids: inout [Set<SuitGroup>]) {
        guard let lead = plays.first?.cards, let first = lead.first else { return }
        let group = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        for play in plays.dropFirst() where voids.indices.contains(play.player) {
            var inGroup = 0
            for card in play.cards where trump.group(card) == group { inGroup += 1 }
            if inGroup < lead.count { voids[play.player].insert(group) }
        }
    }

    /// True if `player` has shown out of `group`.
    func isVoid(_ player: Int, in group: SuitGroup) -> Bool {
        voids.indices.contains(player) && voids[player].contains(group)
    }
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
    /// Strategy knobs (tests compare variants; the app always uses the defaults).
    var tuning = BotTuning()

    public init(seat: Int, level: BotLevel = .standard) {
        self.seat = seat
        self.level = level
    }

    /// Seat in 0...3.
    var normalizedSeat: Int { ((seat % 4) + 4) % 4 }

    /// Called during dealing (after each card this seat receives, and once when dealing completes).
    /// Returns a declaration from `round.availableDeclarations(for: seat)` or nil. Never overrides its partner.
    public func declaration(in round: Round) -> Declaration? {
        BotDeclaring.choose(for: self, in: round)
    }

    /// Dealer only, phase `.burying`: exactly 8 cards from the hand to bury.
    public func cardsToBury(in round: Round) -> BotDecision {
        BotBurying.decide(for: self, in: round)
    }

    /// Phase `.playing`, `round.turn == seat`: a legal lead or follow. Leads that are throws are
    /// only made when guaranteed to succeed against the unseen cards.
    public func decide(in round: Round) -> BotDecision {
        let me = normalizedSeat
        guard round.phase == .playing, round.turn == me, round.hands.indices.contains(me),
              !round.hands[me].isEmpty else {
            return BotText.waiting()
        }
        let table = BotTable(round: round, seat: me, tuning: tuning)
        switch level {
        case .beginner:
            return BeginnerPlay.decide(table)
        case .standard:
            if table.isLeading { return StandardLead(table: table).decide() }
            return StandardFollow(table: table).decide()
        }
    }
}
