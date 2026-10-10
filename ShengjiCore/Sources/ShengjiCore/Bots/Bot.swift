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

    /// Knowledge of `seat` in an offline round; seats are absolute (`voids[2]` is North's).
    public init(round: Round, seat: Int) {
        let me = ((seat % 4) + 4) % 4
        // Once the dealer has buried, the kitty holds exactly the cards they chose.
        let phase: RoundPhase = round.phase
        let buried: Bool = phase == RoundPhase.playing || phase == RoundPhase.finished
        self.init(seat: me, trump: round.trump, hand: round.hands.indices.contains(me) ? round.hands[me] : [],
                  tricks: round.tricks, currentTrick: round.currentTrick,
                  buriedKitty: buried && round.dealer == me ? round.kitty : [])
    }

    /// Knowledge of the viewer of `view`; seats are viewer-relative (the viewer is seat 0, `voids[2]`
    /// is the partner's). Unseen = the full deck minus the viewer's hand, every played card and the
    /// kitty the viewer buried (a kitty shown to everyone once the round is finished does not count).
    public init(view: SeatView) {
        let buried = view.phase == .playing || view.phase == .finished
        self.init(seat: 0, trump: view.trump, hand: view.hand, tricks: view.tricks, currentTrick: view.currentTrick,
                  buriedKitty: buried && view.dealer == 0 ? view.kitty ?? [] : [])
    }

    private init(seat: Int, trump: Trump, hand: [Card], tricks: [TrickRecord], currentTrick: [Play],
                 buriedKitty: [Card]) {
        self.seat = seat
        self.trump = trump
        var known = [Bool](repeating: false, count: 108)
        func mark(_ cards: [Card]) {
            for card in cards where known.indices.contains(card.id) { known[card.id] = true }
        }
        mark(hand)
        for trick in tricks {
            for play in trick.plays { mark(play.cards) }
        }
        for play in currentTrick { mark(play.cards) }
        mark(buriedKitty)
        var unseen: [Card] = []
        unseen.reserveCapacity(108)
        for card in BotKnowledge.fullDeck where !known[card.id] { unseen.append(card) }
        self.unseen = unseen

        var shown = [Set<SuitGroup>](repeating: [], count: 4)
        for trick in tricks {
            BotKnowledge.noteVoids(trick.plays, trump: trump, into: &shown)
        }
        BotKnowledge.noteVoids(currentTrick, trump: trump, into: &shown)
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

/// A bot player, and the hint system (a bot in the learner's seat).
///
/// Every decision is made from a `SeatView` alone, the same visible-state model the online server
/// sends, so a hint never depends on hidden cards. The view is viewer-relative (the viewer is seat 0,
/// the partner seat 2). `seat` only decides how the texts name the other players: compass names of
/// a table where seat 0 is South, seen from `seat`. Hints use `Bot(seat: 0)`, so the viewer is South,
/// the opponent on the right East and the one on the left West, as the coach context names them.
///
/// The `Round` methods build `round.seatView(for: seat)` and decide from it.
///
/// The online server plays bots with a TypeScript port of these choices (server/src/bots), held to
/// them by the `bots.json` vectors: after changing a choice, regenerate the vectors (ShengjiVectors)
/// and bring the port in line (server/test/bots.parity.test.ts).
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

    // MARK: Offline (Round)

    /// Called during dealing (after each card this seat receives, and once when dealing completes).
    /// Returns a declaration from `round.availableDeclarations(for: seat)` or nil. Never overrides its partner.
    public func declaration(in round: Round) -> Declaration? {
        let me = normalizedSeat
        let available = round.availableDeclarations(for: me).map { $0.withPlayer(0) }
        let choice = declaration(view: round.seatView(for: me), available: available)
        return choice?.withPlayer(me)
    }

    /// Dealer only, phase `.burying`: exactly 8 cards from the hand to bury.
    public func cardsToBury(in round: Round) -> BotDecision {
        cardsToBury(view: round.seatView(for: normalizedSeat)) ?? BotText.notBurying()
    }

    /// Phase `.playing`, `round.turn == seat`: a legal lead or follow. Leads that are throws are
    /// only made when guaranteed to succeed against the unseen cards.
    public func decide(in round: Round) -> BotDecision {
        let view = round.seatView(for: normalizedSeat)
        guard view.phase == .playing else { return BotText.waiting() }
        return decide(view: view) ?? BotText.waiting()
    }

    // MARK: From a seat view (offline and online)

    /// What the viewer (seat 0) should do now: the 8 cards to bury when they are the dealer in phase
    /// `.burying` (as `cardsToBury(view:)`), or a legal lead or follow in phase `.playing` on their turn
    /// (throws only when guaranteed against the unseen cards). Nil when the viewer has nothing to do.
    public func decide(view: SeatView) -> BotDecision? {
        if view.phase == .burying { return cardsToBury(view: view) }
        guard view.phase == .playing, view.turn == 0, !view.hand.isEmpty else { return nil }
        let table = BotTable(view: view, compassSeat: normalizedSeat, tuning: tuning)
        switch level {
        case .beginner:
            return BeginnerPlay.decide(table)
        case .standard:
            if table.isLeading { return StandardLead(table: table).decide() }
            return StandardFollow(table: table).decide()
        }
    }

    /// Phase `.burying` with the viewer as dealer (the hand includes the kitty): exactly 8 cards
    /// from the hand to bury. Nil otherwise.
    public func cardsToBury(view: SeatView) -> BotDecision? {
        BotBurying.decide(for: self, view: view)
    }

    /// Declaring, offline while dealing (`available` = what the engine allows the viewer, from
    /// `Round.availableDeclarations`) or online while bidding (`view.bidding.available`). Returns one
    /// of `available` (with player 0) or nil to pass. Never overrides the partner.
    public func declaration(view: SeatView, available: [Declaration]) -> Declaration? {
        BotDeclaring.choose(for: self, view: view, available: available).declaration
    }

    /// Online bidding hint, when it is the viewer's turn to bid (`view.bidding.turn == 0`): declare
    /// (the declaration's cards) or pass (no cards), with the same texts as the other decisions.
    /// Nil when the viewer is not bidding now. The declaration to send is
    /// `declaration(view: view, available: view.bidding.available)`.
    public func bid(view: SeatView) -> BotDecision? {
        guard view.phase == .bidding, let bidding = view.bidding, bidding.turn == 0 else { return nil }
        let choice = BotDeclaring.choose(for: self, view: view, available: bidding.available)
        return BotDeclaring.explain(choice, view: view, available: bidding.available, compassSeat: normalizedSeat)
    }
}

extension Declaration {
    /// The same declaration made by `player`.
    func withPlayer(_ player: Int) -> Declaration {
        Declaration(player: player, cards: cards, suit: suit, strength: strength)
    }
}
