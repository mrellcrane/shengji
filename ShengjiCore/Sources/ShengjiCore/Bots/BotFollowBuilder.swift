import Foundation

/// Counts how often a bot had to fall back to the plain legal-play construction because its
/// cost-based choice failed the rules check. Tests assert this never happens.
final class BotDiagnostics: @unchecked Sendable {
    static let shared = BotDiagnostics()
    private let lock = NSLock()
    private var fallbacks = 0

    var fallbackCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fallbacks
    }

    func noteFallback() {
        lock.lock()
        fallbacks += 1
        lock.unlock()
    }
}

/// What a play is trying to do, which decides how much each card costs to give up.
enum CostMode {
    /// Losing the trick to an opponent: keep points, pairs and high cards.
    case dump
    /// Partner is winning for now but could be beaten: points are only half lost.
    case guarded
    /// Partner wins: point cards are welcome (without breaking pairs).
    case feed
    /// This seat wins: points come back to the team.
    case win
    /// Plain card value, ignoring points (used to compare plays).
    case keep
    /// Beginner habits: plain cards by rank, trumps last.
    case lowest
    /// Beginner habits: trumps first, then the highest plain cards.
    case highest
}

/// Card costs for one `CostMode` (lower = happier to play it).
struct CostModel {
    let table: BotTable
    let mode: CostMode

    /// Cost of playing `card` on its own.
    func loose(_ card: Card) -> Int {
        let value = table.value(card)
        let penalty = table.pairPenalty(card)
        switch mode {
        case .dump: return value + penalty + 4 * card.points
        case .guarded: return value + penalty + 2 * card.points
        case .feed:
            // Points are welcome, but not at the price of breaking a pair.
            return penalty > 0 ? value + penalty : value - 4 * card.points
        case .win: return value + penalty - 3 * card.points
        case .keep: return value + penalty
        case .lowest: return rawRank(card)
        case .highest: return -rawRank(card)
        }
    }

    /// Cost of playing both cards of a pair (or every card of a tractor) together.
    func pair(_ cards: [Card]) -> Int {
        var total = 0
        for card in cards { total += unit(card) }
        return total
    }

    /// Cost of a whole play: cards played with their twin count as a pair, the rest on their own.
    func cost(of play: [Card]) -> Int {
        var counts: [Face: Int] = [:]
        for card in play { counts[card.face, default: 0] += 1 }
        var total = 0
        for card in play {
            total += (counts[card.face] ?? 0) >= 2 ? unit(card) : loose(card)
        }
        return total
    }

    private func unit(_ card: Card) -> Int {
        let value = table.value(card)
        let linked = table.tractorFaces.contains(card.face) ? 10 : 0
        switch mode {
        case .dump: return value + linked + 4 * card.points
        case .guarded: return value + linked + 2 * card.points
        case .feed: return value + linked - 4 * card.points
        case .win: return value + linked - 3 * card.points
        case .keep: return value + linked
        case .lowest: return rawRank(card)
        case .highest: return -rawRank(card)
        }
    }

    private func rawRank(_ card: Card) -> Int {
        (table.trump.isTrump(card) ? 100 : 0) + table.trump.strength(card)
    }
}

/// A card with its cost, for deterministic sorting.
struct ScoredCard {
    let card: Card
    let cost: Int
    let key: Int

    func precedes(_ other: ScoredCard) -> Bool {
        if cost != other.cost { return cost < other.cost }
        if key != other.key { return key < other.key }
        return card.id < other.card.id
    }
}

enum BotPick {
    /// The `count` cheapest cards (ties: display order, then id).
    static func cheapest(_ cards: [Card], _ count: Int, _ costs: CostModel) -> [Card] {
        guard count > 0 else { return [] }
        var scored: [ScoredCard] = []
        scored.reserveCapacity(cards.count)
        for card in cards {
            scored.append(ScoredCard(card: card, cost: costs.loose(card), key: costs.table.order.key(card)))
        }
        scored.sort { $0.precedes($1) }
        return scored.prefix(count).map { $0.card }
    }

    /// Card groups (pairs, tractors) ordered cheapest first (ties: lowest first card).
    static func cheapestFirst(_ groups: [[Card]], _ costs: CostModel) -> [[Card]] {
        var scored: [(cards: [Card], cost: Int, key: Int)] = []
        for cards in groups {
            var key = 0
            if let first = cards.first {
                let orderKey: Int = costs.table.order.key(first)
                key = orderKey * 200 + first.id
            }
            scored.append((cards, costs.pair(cards), key))
        }
        scored.sort { a, b in a.cost != b.cost ? a.cost < b.cost : a.key < b.key }
        return scored.map { $0.cards }
    }
}

/// Builds legal follows: the cards owed by `Rules.followRequirement` first, then filler,
/// each chosen by a cost function.
struct FollowBuilder {
    let trump: Trump
    let lead: [Card]
    let count: Int
    let ledGroup: SuitGroup
    /// Own cards of the led group, and the rest (display order).
    let held: [Card]
    let others: [Card]
    let requirement: FollowRequirement
    /// The lead's components, largest first.
    let leadComponents: [Component]

    init(hand: [Card], lead: [Card], trump: Trump) {
        self.trump = trump
        self.lead = lead
        self.count = lead.count
        let group = Combos.group(of: lead, trump: trump) ?? lead.first.map { trump.group($0) } ?? .trump
        self.ledGroup = group
        let sortedHand = CardOrder(trump).sorted(hand)
        self.held = sortedHand.filter { trump.group($0) == group }
        self.others = sortedHand.filter { trump.group($0) != group }
        if held.count >= lead.count && lead.count >= 2 {
            self.requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
        } else {
            self.requirement = FollowRequirement(tractorLengths: [], totalPairs: 0)
        }
        if lead.count == 1, let card = lead.first {
            self.leadComponents = [Component(shape: .single, cards: lead, group: group, topStrength: trump.strength(card))]
        } else {
            self.leadComponents = Combos.decompose(lead, trump: trump)
        }
    }

    var hand: [Card] { held + others }

    /// Exactly one legal play exists (all remaining led-group cards, or the whole hand).
    var isForced: Bool { held.count == count || hand.count == count }

    func isLegal(_ play: [Card]) -> Bool {
        !play.isEmpty && Rules.validateFollow(play, hand: hand, lead: lead, trump: trump) == nil
    }

    /// The cheapest play under `costs` that meets the follow rules (empty only if the owed
    /// tractors could not be found, which the rules guarantee never happens).
    func build(_ costs: CostModel) -> [Card] {
        if held.count <= count {
            return held + BotPick.cheapest(others, count - held.count, costs)
        }
        if count == 1 { return BotPick.cheapest(held, 1, costs) }
        var pool = held
        var play: [Card] = []
        let lengths = requirement.tractorLengths.sorted(by: >)
        if !lengths.isEmpty {
            guard let tractors = cheapestTractors(in: pool, lengths: lengths, costs: costs) else { return [] }
            for tractor in tractors {
                play += tractor
                pool.remove(cards: tractor)
            }
        }
        var owed = requirement.totalPairs - lengths.reduce(0, +)
        if owed > 0 {
            let pairs = BotPick.cheapestFirst(Combos.pairs(in: pool, trump: trump), costs)
            for pair in pairs where owed > 0 {
                play += pair
                pool.remove(cards: pair)
                owed -= 1
            }
        }
        play += BotPick.cheapest(pool, count - play.count, costs)
        return play
    }

    /// Plays of the led group that copy a single-component lead (the only in-suit plays that can win).
    func inSuitShapes() -> [[Card]] {
        guard !held.isEmpty else { return [] }
        if held.count <= count { return held.count == count ? [held] : [] }
        guard leadComponents.count == 1, let shape = leadComponents.first?.shape else { return [] }
        var plays: [[Card]] = []
        for component in Combos.components(of: shape, in: held, trump: trump) {
            // Any single or pair of the led group answers a single or pair lead; check bigger shapes.
            if shape.cardCount <= 2 || isLegal(component.cards) { plays.append(component.cards) }
        }
        return plays
    }

    /// All-trump plays copying the lead's structure, one per choice of the key component.
    /// Only when out of a led plain suit.
    func ruffs(_ costs: CostModel) -> [[Card]] {
        guard held.isEmpty, !ledGroup.isTrump else { return [] }
        let trumps = others.filter { trump.isTrump($0) }
        guard trumps.count >= count else { return [] }
        guard let key = leadComponents.first else { return [] }
        var plays: [[Card]] = []
        for option in Combos.components(of: key.shape, in: trumps, trump: trump) {
            if let play = completeRuff(start: option.cards, trumps: trumps, rest: leadComponents.dropFirst(),
                                       costs: costs) {
                plays.append(play)
            }
        }
        return plays
    }

    private func completeRuff(start: [Card], trumps: [Card], rest: ArraySlice<Component>,
                              costs: CostModel) -> [Card]? {
        var pool = trumps
        pool.remove(cards: start)
        var play = start
        for component in rest where component.shape != .single {
            let options = Combos.components(of: component.shape, in: pool, trump: trump).map { $0.cards }
            guard let pick = BotPick.cheapestFirst(options, costs).first else { return nil }
            play += pick
            pool.remove(cards: pick)
        }
        play += BotPick.cheapest(pool, count - play.count, costs)
        return play.count == count ? play : nil
    }

    /// A legal follow built straight from the rules with no cost function: the safety net if the
    /// cost-based construction ever fails validation.
    func fallback() -> [Card] {
        if held.count <= count { return held + Array(others.prefix(count - held.count)) }
        guard count > 1 else { return Array(held.prefix(1)) }
        var pool = held
        var play: [Card] = []
        var found: [[Card]] = []
        let lengths = requirement.tractorLengths.sorted(by: >)
        Rules.searchTractors(pool, lengths: lengths[...], trump: trump, chosen: []) { _, chosen in
            found = chosen
            return true
        }
        for tractor in found {
            play += tractor
            pool.remove(cards: tractor)
        }
        var pairs = lengths.reduce(0, +)
        for pair in Combos.pairs(in: pool, trump: trump) where pairs < requirement.totalPairs {
            play += pair
            pool.remove(cards: pair)
            pairs += 1
        }
        play += pool.prefix(max(0, count - play.count))
        return play
    }

    // MARK: Tractor choice

    private struct TractorPick {
        var cost: Int
        var tractors: [[Card]]
    }

    /// The cheapest set of disjoint tractors with the given lengths (bounded search).
    private func cheapestTractors(in cards: [Card], lengths: [Int], costs: CostModel) -> [[Card]]? {
        var best: TractorPick?
        var budget = 300
        searchTractors(cards, lengths[...], [], 0, costs, &best, &budget)
        if let best = best { return best.tractors }
        // Budget ran out before a full set was found: take the first set the rules engine finds.
        var first: [[Card]]?
        Rules.searchTractors(cards, lengths: lengths[...], trump: trump, chosen: []) { _, chosen in
            first = chosen
            return true
        }
        return first
    }

    private func searchTractors(_ cards: [Card], _ lengths: ArraySlice<Int>, _ chosen: [[Card]], _ cost: Int,
                                _ costs: CostModel, _ best: inout TractorPick?, _ budget: inout Int) {
        guard budget > 0 else { return }
        budget -= 1
        guard let length = lengths.first else {
            if let current = best, current.cost <= cost { return }
            best = TractorPick(cost: cost, tractors: chosen)
            return
        }
        for tractor in Combos.tractors(in: cards, length: length, trump: trump) {
            var left = cards
            left.remove(cards: tractor)
            searchTractors(left, lengths.dropFirst(), chosen + [tractor], cost + costs.pair(tractor),
                           costs, &best, &budget)
        }
    }
}
