import Foundation

/// The display order of `Trump.sortKey`, with the plain-suit order worked out once.
/// (`Trump.sortKey` recomputes it for every card, which dominated the bots' running time.)
struct CardOrder {
    let trump: Trump
    /// Group index per suit raw value (the trump suit maps to the trump group, 4).
    private let suitIndex: [Int]

    init(_ trump: Trump) {
        self.trump = trump
        var index = [4, 4, 4, 4]
        for (position, suit) in trump.plainSuitOrder.enumerated() { index[suit.rawValue] = position }
        self.suitIndex = index
    }

    /// Same value as `trump.sortKey(card)`.
    func key(_ card: Card) -> Int {
        let groupIndex: Int
        if trump.isTrump(card) {
            groupIndex = 4
        } else if let suit = card.suit {
            groupIndex = suitIndex[suit.rawValue]
        } else {
            groupIndex = 4
        }
        let tiebreak = card.suit.map { 3 - $0.rawValue } ?? 0
        return groupIndex * 1000 + trump.strength(card) * 10 + tiebreak
    }

    /// Same order as `trump.sorted(cards)`.
    func sorted(_ cards: [Card]) -> [Card] {
        var keyed: [(card: Card, key: Int)] = []
        keyed.reserveCapacity(cards.count)
        for card in cards { keyed.append((card, key(card))) }
        keyed.sort { a, b in a.key != b.key ? a.key < b.key : a.card.id < b.card.id }
        return keyed.map { $0.card }
    }
}

/// One seat's view of the table, plus the card values the strategies share.
/// Built only from a `SeatView`, so only from what the seat may know (`BotKnowledge`): its own hand,
/// the cards played, its own buried kitty and the voids other players have shown. Seats are
/// viewer-relative: this seat is 0, its partner 2, the opponents 1 (next to play) and 3.
struct BotTable {
    let view: SeatView
    /// Always 0: the viewer.
    let seat: Int
    let partner: Int
    /// The seat the texts are written from: other players get the compass names of a table where
    /// seat 0 is South, as seen from this seat (`Bot.seat`; 0 for hints, so the viewer is South).
    let compassSeat: Int
    let trump: Trump
    /// Display order for this round's trump.
    let order: CardOrder
    /// Own hand, lowest first in display order (`Trump.sortKey`).
    let hand: [Card]
    let knowledge: BotKnowledge
    /// True if this seat's team is the declaring (dealer's) team.
    let isDeclarer: Bool
    let tuning: BotTuning
    /// Faces held twice.
    let pairFaces: Set<Face>
    /// Faces held twice next to another held pair of the same group (part of a tractor).
    let tractorFaces: Set<Face>
    private let handGroups: [SuitGroup: [Card]]
    private let unseenGroups: [SuitGroup: [Card]]
    /// Highest unseen strength per group, and highest unseen pair (both copies unseen).
    private let topUnseen: [SuitGroup: Int]
    private let topUnseenPair: [SuitGroup: Int]

    init(view: SeatView, compassSeat: Int = 0, tuning: BotTuning = BotTuning()) {
        self.tuning = tuning
        let trump = view.trump
        self.view = view
        self.seat = 0
        self.partner = Seats.partner(of: 0)
        self.compassSeat = ((compassSeat % 4) + 4) % 4
        self.trump = trump
        let order = CardOrder(trump)
        self.order = order
        self.hand = order.sorted(view.hand)
        let knowledge = BotKnowledge(view: view)
        self.knowledge = knowledge
        self.isDeclarer = view.declarerTeam == Seats.team(of: 0)

        var groups: [SuitGroup: [Card]] = [:]
        var counts: [Face: Int] = [:]
        for card in hand {
            groups[trump.group(card), default: []].append(card)
            counts[card.face, default: 0] += 1
        }
        self.handGroups = groups
        var pairs = Set<Face>()
        for (face, count) in counts where count >= 2 { pairs.insert(face) }
        self.pairFaces = pairs
        var linked = Set<Face>()
        for face in pairs {
            let group = trump.group(face)
            let strength = trump.strength(face)
            for other in pairs where other != face && trump.group(other) == group {
                if abs(trump.strength(other) - strength) == 1 { linked.insert(face) }
            }
        }
        self.tractorFaces = linked

        var unseenByGroup: [SuitGroup: [Card]] = [:]
        var tops: [SuitGroup: Int] = [:]
        var pairTops: [SuitGroup: Int] = [:]
        var faceSeen = [Bool](repeating: false, count: 54)
        for card in knowledge.unseen {
            let group = trump.group(card)
            let strength = trump.strength(card)
            unseenByGroup[group, default: []].append(card)
            tops[group] = max(tops[group] ?? -1, strength)
            let index = card.face.index
            if faceSeen.indices.contains(index) {
                if faceSeen[index] { pairTops[group] = max(pairTops[group] ?? -1, strength) }
                faceSeen[index] = true
            }
        }
        self.unseenGroups = unseenByGroup
        self.topUnseen = tops
        self.topUnseenPair = pairTops
    }

    /// The table of `seat` in an offline round: `round.seatView(for: seat)`, texts written from `seat`.
    init(round: Round, seat: Int, tuning: BotTuning = BotTuning()) {
        self.init(view: round.seatView(for: seat), compassSeat: seat, tuning: tuning)
    }
}

extension BotTable {
    var isLeading: Bool { view.currentTrick.isEmpty }

    /// How the texts name `player` (viewer-relative): "you", "your partner", or a compass name.
    func name(_ player: Int) -> String {
        BotText.name(absolute(player), from: compassSeat)
    }

    /// "your", "your partner's", "East's".
    func possessive(_ player: Int) -> String {
        BotText.possessive(absolute(player), from: compassSeat)
    }

    /// The compass seat of viewer-relative `player`.
    private func absolute(_ player: Int) -> Int { (((player % 4) + 4) % 4 + compassSeat) % 4 }

    /// The two opponents, the one after this seat first.
    var opponents: [Int] { [(seat + 1) % 4, (seat + 3) % 4] }

    func isOpponent(_ player: Int) -> Bool { Seats.team(of: player) != Seats.team(of: seat) }

    /// Own cards of a group, lowest first.
    func cards(in group: SuitGroup) -> [Card] { handGroups[group] ?? [] }

    func unseen(in group: SuitGroup) -> [Card] { unseenGroups[group] ?? [] }

    var trumps: [Card] { cards(in: .trump) }

    /// Late in the round: few cards left in hand.
    var isLate: Bool { hand.count <= 8 }

    /// Own cards of a group as one card per face (`singles`, lowest copy) and the faces held
    /// twice (`pairs`), lowest first. Same cards as `Combos.components(of: .single/.pair, ...)`.
    func pieces(in group: SuitGroup) -> (singles: [Card], pairs: [[Card]]) {
        var singles: [Card] = []
        var pairs: [[Card]] = []
        var previous: Card?
        for card in cards(in: group) {
            if let last = previous, last.face == card.face {
                pairs.append([last, card])
            } else {
                singles.append(card)
            }
            previous = card
        }
        return (singles, pairs)
    }

    /// Same answer as `Rules.canBeat(component, with: knowledge.unseen, trump:)`: some unseen
    /// component of that shape and group is stronger. Singles and pairs use precomputed tops.
    func unseenCanBeat(_ shape: ComboShape, group: SuitGroup, strength: Int) -> Bool {
        switch shape {
        case .single:
            return (topUnseen[group] ?? -1) > strength
        case .pair:
            return (topUnseenPair[group] ?? -1) > strength
        case .tractor:
            let probe = Component(shape: shape, cards: [], group: group, topStrength: strength)
            return Rules.canBeat(probe, with: unseen(in: group), trump: trump)
        }
    }

    func unseenCanBeat(_ component: Component) -> Bool {
        unseenCanBeat(component.shape, group: component.group, strength: component.topStrength)
    }

    /// No unseen card of the same group is stronger (a tie still holds: the earlier play wins).
    func isTopUnseen(_ card: Card) -> Bool {
        trump.strength(card) >= (topUnseen[trump.group(card)] ?? -1)
    }

    /// `player` has shown out of the plain group and may still hold trumps to ruff it with.
    func mayRuff(_ player: Int, _ group: SuitGroup) -> Bool {
        guard !group.isTrump else { return false }
        return knowledge.isVoid(player, in: group) && !knowledge.isVoid(player, in: .trump)
    }

    /// So few cards of a plain group are left outside this hand that `players` other players are
    /// unlikely to all be able to follow `count` cards of it.
    func isRunningOut(_ group: SuitGroup, count: Int, players: Int) -> Bool {
        guard !group.isTrump, players > 0 else { return false }
        return unseen(in: group).count < max(1, count * players)
    }

    /// How useful a card is to keep (higher = more useful later), ignoring its points.
    /// Units: 4 per point, so a 10-point card's points weigh 40. Trumps rise steeply: a low trump
    /// is worth about 8 points, a trump-rank card about 24, a small joker about 31.
    func value(_ card: Card) -> Int {
        let strength = trump.strength(card)
        guard trump.isTrump(card) else { return 2 * strength + (isTopUnseen(card) ? 16 : 0) }
        switch strength {
        case Trump.bigJokerStrength: return 140
        case Trump.smallJokerStrength: return 125
        case Trump.trumpSuitRankStrength: return 108
        case Trump.offSuitRankStrength: return 96
        default: return 32 + strength * strength / 4 + 2 * strength
        }
    }

    /// Extra cost of playing one card of a held pair on its own (breaking the pair).
    func pairPenalty(_ card: Card) -> Int {
        guard pairFaces.contains(card.face) else { return 0 }
        return 16 + trump.strength(card) + (tractorFaces.contains(card.face) ? 10 : 0)
    }
}
