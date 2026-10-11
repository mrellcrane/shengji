import Foundation

/// Seats: 0 = South (the human), 1 = East, 2 = North (human's partner), 3 = West.
/// Play goes 0 → 1 → 2 → 3 → 0 (counter-clockwise, as in China). Partners sit opposite.
/// Bigger tables (6 or 8 players) go on round the same way: teams alternate, so the human's team is
/// every even seat (team = seat % 2) and the seat opposite the human is a partner with 8 players and
/// an opponent with 6. Functions without `players` are for the classic 4-player table.
public enum Seats {
    public static let human = 0
    public static let all = [0, 1, 2, 3]
    public static func all(players: Int) -> [Int] { Array(0..<max(players, 1)) }
    public static func team(of player: Int) -> Int { player % 2 }
    public static func partner(of player: Int) -> Int { (player + 2) % 4 }
    public static func next(after player: Int) -> Int { (player + 1) % 4 }
    public static func next(after player: Int, players: Int) -> Int { normalized(player + 1, players: players) }
    /// `player` as a seat in 0..<players.
    public static func normalized(_ player: Int, players: Int) -> Int {
        let n = max(players, 1)
        return ((player % n) + n) % n
    }
    /// The other seats of `player`'s team, in play order after `player`.
    public static func teammates(of player: Int, players: Int) -> [Int] {
        stride(from: 2, to: players, by: 2).map { normalized(player + $0, players: players) }
    }
    /// The seats of the other team, in play order after `player`.
    public static func opponents(of player: Int, players: Int) -> [Int] {
        stride(from: 1, to: players, by: 2).map { normalized(player + $0, players: players) }
    }
    /// Display names from the human's point of view.
    public static func name(_ player: Int) -> String {
        switch player {
        case 0: return "You"
        case 1: return "East"
        case 2: return "Partner"
        default: return "West"
        }
    }
    /// Display names from the human's point of view at a table of `players`: the classic names with 4,
    /// compass points round the table with 6 or 8 (you are South).
    public static func name(_ player: Int, players: Int) -> String {
        if players <= 4 { return name(normalized(player, players: 4)) }
        let seat = normalized(player, players: players)
        if seat == human { return "You" }
        return compassName(seat, players: players)
    }
    /// Compass point of a seat when seat 0 is South: South, East, North, West with 4; South, Southeast,
    /// Northeast, North, Northwest, Southwest with 6; the eight points with 8.
    public static func compassName(_ player: Int, players: Int) -> String {
        let seat = normalized(player, players: players)
        switch players {
        case 6: return ["South", "Southeast", "Northeast", "North", "Northwest", "Southwest"][seat]
        case 8: return ["South", "Southeast", "East", "Northeast", "North", "Northwest", "West", "Southwest"][seat]
        default: return ["South", "East", "North", "West"][normalized(seat, players: 4)]
        }
    }
    /// Short labels for crowded tables: "You", "SE", "NE", ... (the classic names with 4 players).
    public static func shortName(_ player: Int, players: Int) -> String {
        if players <= 4 { return name(normalized(player, players: 4)) }
        let seat = normalized(player, players: players)
        if seat == human { return "You" }
        switch players {
        case 6: return ["S", "SE", "NE", "N", "NW", "SW"][seat]
        default: return ["S", "SE", "E", "NE", "N", "NW", "W", "SW"][normalized(seat, players: 8)]
        }
    }
}

/// One player's contribution to a trick.
public struct Play: Hashable, Codable, Sendable {
    public var player: Int
    public var cards: [Card]
    public init(player: Int, cards: [Card]) {
        self.player = player
        self.cards = cards
    }
}

/// Why a lead is illegal.
public enum LeadViolation: Equatable, Sendable {
    case empty
    case cardsNotInHand
    /// Cards come from more than one suit group (e.g. a spade and a trump).
    case mixedSuits

    /// One or two plain-English sentences for the coach.
    public var explanation: String {
        switch self {
        case .empty:
            return "Choose at least one card to lead."
        case .cardsNotInHand:
            return "You can only play cards that are in your hand."
        case .mixedSuits:
            return "A lead must be all one suit, or all trumps. "
                + "Jokers and trump-rank cards count as trumps, not as their printed suit."
        }
    }
}

/// Why a follow is illegal. The explanation is shown to learners, so it must teach the rule.
public enum FollowViolation: Equatable, Sendable {
    case wrongCount(expected: Int)
    case cardsNotInHand
    /// The player still holds cards of the led group that they didn't play.
    case mustFollowSuit(SuitGroup)
    /// The player holds a tractor of the needed length in the led group but didn't play one.
    case mustPlayTractor(length: Int)
    /// The player had to play at least `required` pairs from the led group.
    case mustPlayPairs(required: Int)
    /// Three or more decks: the player holds a tractor of sets of `width` identical cards (a tractor of
    /// triples) of the needed length in the led group but didn't play one.
    case mustPlaySetTractor(width: Int, length: Int)
    /// Three or more decks: the player had to play at least `required` sets of `width` identical cards
    /// (triples, four of a kind) from the led group.
    case mustPlaySets(width: Int, required: Int)

    public var explanation: String {
        switch self {
        case let .wrongCount(expected):
            let cards = expected == 1 ? "1 card" : "\(expected) cards"
            return "Play exactly \(cards), the same number as the lead."
        case .cardsNotInHand:
            return "You can only play cards that are in your hand."
        case let .mustFollowSuit(group):
            let name = group.name
            let capitalized = name.prefix(1).uppercased() + name.dropFirst()
            // Learners often take a trump-rank card (2♠ when 2s are trump) for a card of its printed
            // suit, so say where those cards belong.
            let reminder: String
            switch group {
            case .trump:
                reminder = "Jokers and trump-rank cards of every suit are trumps too."
            case let .plain(suit):
                reminder = "A \(suit.singularName) of the trump rank counts as a trump, not a \(suit.singularName)."
            }
            return "\(capitalized) were led and you still have \(name), so you must play \(name). \(reminder) "
                + "If you have too few \(name), play them all and fill up with other cards."
        case let .mustPlayTractor(length):
            let tractor = length > 2 ? "a tractor of \(length) pairs" : "a tractor"
            return "A tractor was led and you hold \(tractor) in that suit, so you must play it."
        case let .mustPlayPairs(required):
            if required <= 1 {
                return "The lead contains a pair and you have a pair in that suit, so you must play a pair "
                    + "(two identical cards)."
            }
            return "The lead contains pairs and you have pairs in that suit, so you must play at least \(required) pairs."
        case let .mustPlaySetTractor(width, length):
            let name = ComboShape.setTractor(width: width, length: length).name
            return "A \(name) was led and you hold one in that suit, so you must play it."
        case let .mustPlaySets(width, required):
            if required <= 1 {
                let one = width == 3 ? "a triple (three identical cards)" : "\(FollowViolation.count(width)) identical cards"
                return "The lead calls for \(one), and you hold that in the suit led, so you must play it."
            }
            let many = width == 3 ? "triples" : "sets of \(FollowViolation.count(width)) identical cards"
            return "The lead calls for \(required) \(many), and you hold that many in the suit led, so you must play them."
        }
    }

    /// "three", "four", or the digits.
    static func count(_ n: Int) -> String {
        switch n {
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        default: return String(n)
        }
    }
}

/// What a follower is obliged to include when they have enough cards of the led group.
public struct FollowRequirement: Equatable, Sendable {
    /// Tractor lengths (in pairs) that must appear, disjoint, in the play.
    public var tractorLengths: [Int]
    /// Minimum number of pairs (counting the pairs inside required tractors) the play must contain.
    public var totalPairs: Int
    /// Every combination the play must contain, disjoint: the tractors, then the sets (each pair
    /// once). With two decks these are the `tractorLengths` tractors and the pairs outside them; with
    /// more decks they can include triples, four of a kind and tractors of them.
    public var units: [ComboShape]

    public init(tractorLengths: [Int], totalPairs: Int) {
        self.tractorLengths = tractorLengths
        self.totalPairs = totalPairs
        let loose = max(0, totalPairs - tractorLengths.reduce(0, +))
        self.units = tractorLengths.map { ComboShape.tractor($0) } + Array(repeating: .pair, count: loose)
    }

    public init(units: [ComboShape]) {
        self.units = units
        self.tractorLengths = units.filter { $0.width == 2 && $0.isTractor }.map(\.length)
        self.totalPairs = units.filter { $0.width == 2 }.reduce(0) { $0 + $1.length }
    }

    /// True when only pairs and tractors of pairs are owed (always the case with two decks).
    public var isClassic: Bool { units.allSatisfy { $0.width <= 2 } }
}

/// Result of checking a multi-component lead ("throw", 甩牌).
public enum ThrowCheck: Equatable, Sendable {
    case ok
    /// The throw fails: `blocker` holds a higher component of the same shape in that suit.
    /// The leader must instead play only `forced` (the lowest-ranked beatable component).
    case fails(forced: Component, blocker: Int)
}

public enum Rules {
    /// Lead legality: non-empty, from hand, one suit group. (Throw success is checked separately.)
    public static func validateLead(_ cards: [Card], hand: [Card], trump: Trump) -> LeadViolation? {
        if cards.isEmpty { return .empty }
        if !hand.containsAll(cards) { return .cardsNotInHand }
        if Combos.group(of: cards, trump: trump) == nil { return .mixedSuits }
        return nil
    }

    /// True when the lead has more than one component (a throw).
    public static func isThrow(_ cards: [Card], trump: Trump) -> Bool {
        Combos.decompose(cards, trump: trump).count > 1
    }

    /// Checks a throw against every other player's hand. For each component of the throw,
    /// another player beats it if they hold, in the same group, a component of the same shape
    /// with higher strength (single: any higher card; pair: a higher pair; tractor(n): a tractor
    /// of n pairs with a higher top). Returns `.ok` for non-throws.
    public static func checkThrow(_ cards: [Card], leader: Int, hands: [[Card]], trump: Trump) -> ThrowCheck {
        let seats = max(4, hands.count)
        let leaderSeat = ((leader % seats) + seats) % seats
        var opponents: [(seat: Int, cards: [Card])] = []
        for step in 1..<seats {
            let seat = (leaderSeat + step) % seats
            if hands.indices.contains(seat) { opponents.append((seat, hands[seat])) }
        }
        return throwCheck(cards, opponents: opponents, trump: trump)
    }

    /// Same as `checkThrow` but against an arbitrary pool of possibly-held cards treated as one hand
    /// (bots use the unseen cards). `.fails` carries blocker = -1.
    public static func checkThrow(_ cards: [Card], against pool: [Card], trump: Trump) -> ThrowCheck {
        throwCheck(cards, opponents: [(seat: -1, cards: pool)], trump: trump)
    }

    /// Structure the follower must match, given the lead and the follower's cards in the led group.
    /// Algorithm (DESIGN.md §Following): walk the lead's components largest first; a tractor(k)
    /// requires a k-tractor if the follower has a run ≥ k, otherwise as many pairs as they have (≤ k);
    /// a pair requires a pair if available.
    public static func followRequirement(lead: [Card], suitCards: [Card], trump: Trump) -> FollowRequirement {
        // A single card asks for no structure.
        if lead.count < 2 { return FollowRequirement(tractorLengths: [], totalPairs: 0) }
        let components = Combos.decompose(lead, trump: trump)
        if Combos.maxCopies(lead) <= 2 && Combos.maxCopies(suitCards) <= 2 {
            let walk = requirementWalk(components[...], remaining: suitCards, trump: trump)
            return FollowRequirement(tractorLengths: walk.tractors, totalPairs: walk.pairs)
        }
        // Three or more decks: the same walk over sets of any width.
        let walk = unitWalk(components[...], remaining: suitCards, trump: trump)
        return FollowRequirement(units: walk.tractors + walk.sets)
    }

    /// Full follow legality. Returns nil if legal.
    ///  1. exactly lead.count cards, all from hand;
    ///  2. must play min(n, held) cards of the led group;
    ///  3. if the player holds ≥ n of the led group, the play must satisfy `followRequirement`.
    public static func validateFollow(_ cards: [Card], hand: [Card], lead: [Card], trump: Trump) -> FollowViolation? {
        let n = lead.count
        if cards.count != n { return .wrongCount(expected: n) }
        if !hand.containsAll(cards) { return .cardsNotInHand }
        guard let firstLead = lead.first else { return nil }

        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(firstLead)
        let held = Combos.cards(hand, in: ledGroup, trump: trump)
        let playedInGroup = Combos.cards(cards, in: ledGroup, trump: trump)
        if playedInGroup.count < min(n, held.count) { return .mustFollowSuit(ledGroup) }
        // Short in the led group: everything they had is in the play, the rest can be anything.
        guard held.count >= n else { return nil }

        let requirement = followRequirement(lead: lead, suitCards: held, trump: trump)
        if !requirement.isClassic || Combos.maxCopies(held) > 2 {
            return unitViolation(cards, units: requirement.units, trump: trump)
        }
        let lengths = requirement.tractorLengths
        if !lengths.isEmpty && !containsDisjointTractors(cards, lengths: lengths, trump: trump) {
            var missing = lengths[0]
            for count in 1...lengths.count
            where !containsDisjointTractors(cards, lengths: Array(lengths.prefix(count)), trump: trump) {
                missing = lengths[count - 1]
                break
            }
            return .mustPlayTractor(length: missing)
        }
        if Combos.pairCount(in: cards) < requirement.totalPairs {
            return .mustPlayPairs(required: requirement.totalPairs)
        }
        return nil
    }

    /// Index into `plays` of the play currently winning the (possibly partial) trick. plays[0] is the lead.
    /// A later play beats the current winner only if it is entirely in the led group or entirely trump,
    /// matches the lead's structure (same component shapes), and its key component is stronger
    /// (trump beats non-trump). Ties go to the earlier play.
    public static func winningIndex(_ plays: [Play], trump: Trump) -> Int {
        guard let leadPlay = plays.first, let firstCard = leadPlay.cards.first else { return 0 }
        let lead = leadPlay.cards
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(firstCard)
        let format = LeadFormat(lead, trump: trump)
        var bestIndex = 0
        var bestIsTrump = ledGroup.isTrump
        var bestKey = structureKey(lead, format: format, trump: trump) ?? format.largest?.topStrength ?? 0

        for index in plays.indices.dropFirst() {
            let cards = plays[index].cards
            guard let group = Combos.group(of: cards, trump: trump),
                  group == ledGroup || group.isTrump,
                  let key = structureKey(cards, format: format, trump: trump) else { continue }
            if group.isTrump && !bestIsTrump {
                bestIndex = index
                bestIsTrump = true
                bestKey = key
            } else if group.isTrump == bestIsTrump && key > bestKey {
                bestIndex = index
                bestKey = key
            }
        }
        return bestIndex
    }

    /// True if `cards` (played after `lead`) have the same component structure as the lead,
    /// all from one group. Used by `winningIndex` and the bots.
    public static func matchesStructure(_ cards: [Card], lead: [Card], trump: Trump) -> Bool {
        structureKey(cards, lead: lead, trump: trump) != nil
    }
}

// MARK: - Internal helpers

extension Rules {
    // MARK: Throws

    static func throwCheck(_ cards: [Card], opponents: [(seat: Int, cards: [Card])], trump: Trump) -> ThrowCheck {
        let components = Combos.decompose(cards, trump: trump)
        guard components.count > 1 else { return .ok }

        var forced: Component?
        for component in components
        where opponents.contains(where: { canBeat(component, with: $0.cards, trump: trump) }) {
            if let current = forced {
                if ranksLower(component, than: current, trump: trump) { forced = component }
            } else {
                forced = component
            }
        }
        guard let lowest = forced else { return .ok }
        let blocker = opponents.first(where: { canBeat(lowest, with: $0.cards, trump: trump) })?.seat ?? -1
        return .fails(forced: lowest, blocker: blocker)
    }

    /// True if `cards` hold a component of the same shape and group as `component` with a higher top.
    static func canBeat(_ component: Component, with cards: [Card], trump: Trump) -> Bool {
        let own = Combos.cards(cards, in: component.group, trump: trump)
        switch component.shape {
        case .single:
            return own.contains { trump.strength($0) > component.topStrength }
        case .pair:
            return Combos.pairs(in: own, trump: trump).contains { pair in
                pair.first.map { trump.strength($0) > component.topStrength } ?? false
            }
        case let .tractor(length):
            return Combos.tractors(in: own, length: length, trump: trump).contains { tractor in
                topStrength(of: tractor, trump: trump) > component.topStrength
            }
        case .set, .setTractor:
            return Combos.units(of: component.shape, in: own, trump: trump).contains { unit in
                topStrength(of: unit, trump: trump) > component.topStrength
            }
        }
    }

    /// Order used to pick the forced component of a failed throw: smaller shape first, then lower strength.
    static func ranksLower(_ a: Component, than b: Component, trump: Trump) -> Bool {
        if a.shape.cardCount != b.shape.cardCount { return a.shape.cardCount < b.shape.cardCount }
        if a.topStrength != b.topStrength { return a.topStrength < b.topStrength }
        let keyA = a.cards.first.map { trump.sortKey($0) } ?? 0
        let keyB = b.cards.first.map { trump.sortKey($0) } ?? 0
        return keyA < keyB
    }

    static func topStrength(of cards: [Card], trump: Trump) -> Int {
        cards.map { trump.strength($0) }.max() ?? -1
    }

    // MARK: Following

    /// The greedy walk of DESIGN.md §Following. When a tractor must be removed and several can be,
    /// or pairs must be given up for a tractor the follower can't match, the choice that keeps the
    /// most tractors for the remaining components is used.
    static func requirementWalk(_ components: ArraySlice<Component>, remaining: [Card],
                                trump: Trump) -> (tractors: [Int], pairs: Int) {
        guard let component = components.first else { return ([], 0) }
        let rest = components.dropFirst()
        switch component.shape {
        case .single, .set, .setTractor:
            // Sets of three or more never reach this two-deck walk (see `unitWalk`).
            return requirementWalk(rest, remaining: remaining, trump: trump)

        case .pair:
            guard let pair = Combos.pairs(in: remaining, trump: trump).first else {
                return requirementWalk(rest, remaining: remaining, trump: trump)
            }
            var left = remaining
            left.remove(cards: pair)
            let sub = requirementWalk(rest, remaining: left, trump: trump)
            return (sub.tractors, sub.pairs + 1)

        case let .tractor(length):
            if Combos.longestRun(in: remaining, trump: trump) >= length {
                let reachable = rest.filter { $0.shape.isTractor }.count
                var best: (tractors: [Int], pairs: Int)?
                for tractor in Combos.tractors(in: remaining, length: length, trump: trump) {
                    var left = remaining
                    left.remove(cards: tractor)
                    let sub = requirementWalk(rest, remaining: left, trump: trump)
                    if let current = best {
                        if isMoreStructure(sub.tractors, than: current.tractors) { best = sub }
                    } else {
                        best = sub
                    }
                    if sub.tractors.count == reachable { break }
                }
                let chosen = best ?? ([], 0)
                return ([length] + chosen.tractors, chosen.pairs + length)
            }
            // No run long enough: as many pairs as they have, up to `length`.
            let pairs = Combos.pairs(in: remaining, trump: trump)
            let count = min(pairs.count, length)
            let reachable = rest.filter { $0.shape.isTractor }.count
            // Pairs that sit next to no other pair can never be part of a tractor, so giving them up
            // first costs nothing. Only if more pairs are owed does the choice matter.
            let loose = pairs.filter { !isNextToAnotherPair($0, pairs: pairs, trump: trump) }
            let linked = pairs.filter { isNextToAnotherPair($0, pairs: pairs, trump: trump) }
            var base = remaining
            for pair in loose.prefix(count) { base.remove(cards: pair) }
            let stillOwed = count - min(count, loose.count)
            if stillOwed == 0 || reachable == 0 {
                for pair in linked.prefix(stillOwed) { base.remove(cards: pair) }
                let sub = requirementWalk(rest, remaining: base, trump: trump)
                return (sub.tractors, sub.pairs + count)
            }
            // Try every choice of linked pairs and keep the one that leaves the most structure.
            var best: (tractors: [Int], pairs: Int)?
            forEachCombination(of: linked[...], size: stillOwed, chosen: []) { chosen in
                var left = base
                for pair in chosen { left.remove(cards: pair) }
                let sub = requirementWalk(rest, remaining: left, trump: trump)
                if let current = best {
                    if isMoreStructure(sub.tractors, than: current.tractors) { best = sub }
                } else {
                    best = sub
                }
                return sub.tractors.count == reachable
            }
            let chosen = best ?? ([], 0)
            return (chosen.tractors, chosen.pairs + count)
        }
    }

    /// True if another pair in `pairs` is of the same group and one strength above or below `pair`,
    /// so the two could be part of a tractor.
    static func isNextToAnotherPair(_ pair: [Card], pairs: [[Card]], trump: Trump) -> Bool {
        guard let card = pair.first else { return false }
        let group = trump.group(card)
        let strength = trump.strength(card)
        return pairs.contains { other in
            guard let otherCard = other.first, trump.group(otherCard) == group else { return false }
            return abs(trump.strength(otherCard) - strength) == 1
        }
    }

    /// Calls `visit` with every way to pick `size` of `items` (in order). Returns true if a visit
    /// returned true, which stops the enumeration.
    @discardableResult
    static func forEachCombination<T>(of items: ArraySlice<T>, size: Int, chosen: [T],
                                      visit: ([T]) -> Bool) -> Bool {
        if chosen.count == size { return visit(chosen) }
        guard items.count >= size - chosen.count else { return false }
        var rest = items
        while let item = rest.first, rest.count >= size - chosen.count {
            rest = rest.dropFirst()
            if forEachCombination(of: rest, size: size, chosen: chosen + [item], visit: visit) { return true }
        }
        return false
    }

    static func isMoreStructure(_ a: [Int], than b: [Int]) -> Bool {
        if a.count != b.count { return a.count > b.count }
        let sumA = a.reduce(0, +), sumB = b.reduce(0, +)
        if sumA != sumB { return sumA > sumB }
        return a.lexicographicallyPrecedes(b) == false && a != b
    }

    /// True if `cards` contain disjoint tractors of all the given lengths.
    static func containsDisjointTractors(_ cards: [Card], lengths: [Int], trump: Trump) -> Bool {
        searchTractors(cards, lengths: lengths.sorted(by: >)[...], trump: trump, chosen: []) { _, _ in true }
    }

    /// Backtracking search over every way to take disjoint tractors of the given lengths
    /// (sorted longest first) out of `cards`. `visit` receives the leftover cards and the chosen
    /// tractors; returning true stops the search. Returns true if a visit stopped it.
    @discardableResult
    static func searchTractors(_ cards: [Card], lengths: ArraySlice<Int>, trump: Trump, chosen: [[Card]],
                               visit: ([Card], [[Card]]) -> Bool) -> Bool {
        guard let length = lengths.first else { return visit(cards, chosen) }
        let rest = lengths.dropFirst()
        // Tractors of equal length are picked in increasing order of their lowest card id,
        // so each set of tractors is tried once instead of once per ordering.
        var floor: Int?
        if let previous = chosen.last, previous.count == 2 * length {
            floor = previous.map(\.id).min()
        }
        for tractor in Combos.tractors(in: cards, length: length, trump: trump) {
            let lowestID = tractor.map(\.id).min() ?? 0
            if let floor = floor, lowestID <= floor { continue }
            var left = cards
            left.remove(cards: tractor)
            if searchTractors(left, lengths: rest, trump: trump, chosen: chosen + [tractor], visit: visit) {
                return true
            }
        }
        return false
    }

    // MARK: Winning

    /// The comparison key of `cards` played to `lead`, or nil if they don't match the lead's structure.
    /// The key is the top strength of the play's component matched to the lead's largest component,
    /// maximised over every valid matching. For an all-singles lead it is the play's highest card.
    static func structureKey(_ cards: [Card], lead: [Card], trump: Trump) -> Int? {
        structureKey(cards, format: LeadFormat(lead, trump: trump), trump: trump)
    }

    /// The shapes making up a lead, computed once per trick.
    struct LeadFormat {
        var cardCount: Int
        /// The lead's largest component (the key component).
        var largest: Component?
        /// Tractor lengths, longest first.
        var tractorLengths: [Int]
        /// Number of plain pair components.
        var pairs: Int
        /// Every component bigger than a single, widest first, then longest (three or more decks).
        var units: [ComboShape]
        /// True when the lead is only singles, pairs and tractors of pairs.
        var isClassic: Bool

        init(_ lead: [Card], trump: Trump) {
            cardCount = lead.count
            let components = Combos.decompose(lead, trump: trump)
            largest = components.first
            var lengths: [Int] = []
            var pairs = 0
            var units: [ComboShape] = []
            for component in components {
                switch component.shape {
                case let .tractor(length): lengths.append(length)
                case .pair: pairs += 1
                case .single, .set, .setTractor: break
                }
                if component.shape != .single { units.append(component.shape) }
            }
            tractorLengths = lengths.sorted(by: >)
            self.pairs = pairs
            self.units = Rules.sortedUnits(units)
            isClassic = components.allSatisfy { $0.shape.width <= 2 }
        }
    }

    static func structureKey(_ cards: [Card], format: LeadFormat, trump: Trump) -> Int? {
        guard !cards.isEmpty, cards.count == format.cardCount, let largest = format.largest,
              Combos.group(of: cards, trump: trump) != nil else { return nil }
        if !format.isClassic || Combos.maxCopies(cards) > 2 {
            return unitStructureKey(cards, format: format, keyShape: largest.shape, trump: trump)
        }
        let pairsNeeded = format.pairs

        switch largest.shape {
        case .single:
            return cards.map { trump.strength($0) }.max()
        case .pair:
            if cards.count == 2 {
                // Fast path for the common pair lead.
                return Combos.isPair(cards) ? trump.strength(cards[0]) : nil
            }
            let pairs = Combos.pairs(in: cards, trump: trump)
            guard pairs.count >= pairsNeeded else { return nil }
            return pairs.compactMap { $0.first.map { trump.strength($0) } }.max()
        case let .tractor(keyLength):
            var best: Int?
            searchTractors(cards, lengths: format.tractorLengths[...], trump: trump, chosen: []) { left, chosen in
                guard Combos.pairCount(in: left) >= pairsNeeded else { return false }
                let key = chosen
                    .filter { $0.count == 2 * keyLength }
                    .map { topStrength(of: $0, trump: trump) }
                    .max() ?? -1
                best = max(best ?? key, key)
                return key >= Trump.bigJokerStrength
            }
            return best
        case .set, .setTractor:
            return unitStructureKey(cards, format: format, keyShape: largest.shape, trump: trump)
        }
    }
}
