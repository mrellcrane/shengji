import Foundation

/// The basic building blocks of a play.
///  - single: one card
///  - pair: two identical cards (same face; e.g. two 7♠; but 2♠ + 2♣ is NOT a pair)
///  - tractor(n): n ≥ 2 pairs of consecutive strength in the same suit group (拖拉机)
public enum ComboShape: Hashable, Codable, Sendable, CustomStringConvertible {
    case single
    case pair
    case tractor(Int)

    public var cardCount: Int {
        switch self {
        case .single: return 1
        case .pair: return 2
        case let .tractor(n): return 2 * n
        }
    }

    public var pairCount: Int {
        switch self {
        case .single: return 0
        case .pair: return 1
        case let .tractor(n): return n
        }
    }

    public var isTractor: Bool {
        if case .tractor = self { return true }
        return false
    }

    public var name: String {
        switch self {
        case .single: return "single"
        case .pair: return "pair"
        case let .tractor(n): return n == 2 ? "tractor" : "tractor of \(n) pairs"
        }
    }

    public var description: String { name }
}

/// One component of a play: a single, a pair, or a tractor, all from one suit group.
public struct Component: Hashable, Codable, Sendable, CustomStringConvertible {
    public var shape: ComboShape
    /// Cards sorted from lowest to highest strength.
    public var cards: [Card]
    public var group: SuitGroup
    /// Strength (see `Trump.strength`) of the highest card.
    public var topStrength: Int

    public init(shape: ComboShape, cards: [Card], group: SuitGroup, topStrength: Int) {
        self.shape = shape
        self.cards = cards
        self.group = group
        self.topStrength = topStrength
    }

    public var description: String { "\(shape.name) \(cards.shortText)" }
}

public enum Combos {
    // MARK: Grouping helpers

    /// The single suit group shared by all cards, or nil if empty or mixed.
    public static func group(of cards: [Card], trump: Trump) -> SuitGroup? {
        guard let first = cards.first else { return nil }
        let g = trump.group(first)
        return cards.allSatisfy({ trump.group($0) == g }) ? g : nil
    }

    /// Cards of `hand` in the given group.
    public static func cards(_ hand: [Card], in group: SuitGroup, trump: Trump) -> [Card] {
        hand.filter { trump.group($0) == group }
    }

    /// Cards bucketed by face, in a deterministic order.
    static func byFace(_ cards: [Card]) -> [Face: [Card]] {
        var d: [Face: [Card]] = [:]
        for c in cards.sorted(by: { $0.id < $1.id }) { d[c.face, default: []].append(c) }
        return d
    }

    // MARK: Pairs

    public static func isPair(_ cards: [Card]) -> Bool {
        cards.count == 2 && cards[0].face == cards[1].face && cards[0].id != cards[1].id
    }

    /// Every pair in `cards` (each face appearing twice), sorted by group then strength ascending.
    public static func pairs(in cards: [Card], trump: Trump) -> [[Card]] {
        byFace(cards).values
            .filter { $0.count >= 2 }
            .map { Array($0.prefix(2)) }
            .sorted { trump.sortKey($0[0]) < trump.sortKey($1[0]) }
    }

    /// Number of distinct pairs available in `cards`.
    public static func pairCount(in cards: [Card]) -> Int {
        byFace(cards).values.filter { $0.count >= 2 }.count
    }

    // MARK: Tractors

    /// Pair faces of one group bucketed by strength level.
    static func pairLevels(_ cards: [Card], group: SuitGroup, trump: Trump) -> [Int: [Face]] {
        var levels: [Int: [Face]] = [:]
        for (face, cs) in byFace(cards) where cs.count >= 2 && trump.group(face) == group {
            levels[trump.strength(face), default: []].append(face)
        }
        for k in levels.keys {
            levels[k]!.sort { ($0.suit?.rawValue ?? 9) < ($1.suit?.rawValue ?? 9) }
        }
        return levels
    }

    static func groups(in cards: [Card], trump: Trump) -> [SuitGroup] {
        var seen: [SuitGroup] = []
        for c in trump.sorted(cards) {
            let g = trump.group(c)
            if !seen.contains(g) { seen.append(g) }
        }
        return seen
    }

    /// Every tractor of exactly `length` pairs that can be formed from `cards`
    /// (sub-runs of longer runs are included). Each result is 2*length cards, low to high.
    public static func tractors(in cards: [Card], length: Int, trump: Trump) -> [[Card]] {
        guard length >= 2 else { return [] }
        let faceCards = byFace(cards)
        var results: [[Card]] = []
        for g in groups(in: cards, trump: trump) {
            let levels = pairLevels(cards, group: g, trump: trump)
            for start in levels.keys.sorted() {
                let run = (start..<(start + length))
                guard run.allSatisfy({ levels[$0] != nil }) else { continue }
                // Cartesian product over face choices at each level.
                var partials: [[Card]] = [[]]
                for level in run {
                    var next: [[Card]] = []
                    for p in partials {
                        for f in levels[level]! { next.append(p + Array(faceCards[f]!.prefix(2))) }
                    }
                    partials = next
                }
                results.append(contentsOf: partials)
            }
        }
        return results
    }

    /// Length (in pairs) of the longest run in `cards`: 0 = no pairs, 1 = pairs but no tractor.
    public static func longestRun(in cards: [Card], trump: Trump) -> Int {
        var best = 0
        for g in groups(in: cards, trump: trump) {
            let keys = Set(pairLevels(cards, group: g, trump: trump).keys)
            for k in keys where !keys.contains(k - 1) {
                var n = 0
                while keys.contains(k + n) { n += 1 }
                best = max(best, n)
            }
        }
        return best
    }

    // MARK: Decomposition

    /// Splits cards into components: tractors first (longest runs greedily), then pairs, then singles.
    /// Sorted largest first (by card count), then by strength descending.
    /// This is the canonical "format" of a lead.
    public static func decompose(_ cards: [Card], trump: Trump) -> [Component] {
        var remaining = byFace(cards)
        var comps: [Component] = []

        func take(_ face: Face, _ n: Int) -> [Card] {
            let taken = Array(remaining[face]!.prefix(n))
            remaining[face]!.removeFirst(n)
            if remaining[face]!.isEmpty { remaining[face] = nil }
            return taken
        }

        for g in groups(in: cards, trump: trump) {
            // Tractors: repeatedly take the longest run available.
            while true {
                let flat = remaining.values.flatMap { $0 }
                let levels = pairLevels(flat, group: g, trump: trump)
                let keys = Set(levels.keys)
                var bestStart: Int?
                var bestLen = 1
                for k in keys.sorted(by: >) where !keys.contains(k - 1) {
                    var n = 0
                    while keys.contains(k + n) { n += 1 }
                    if n > bestLen { bestLen = n; bestStart = k }
                }
                guard let start = bestStart else { break }
                var tc: [Card] = []
                for level in start..<(start + bestLen) { tc += take(levels[level]![0], 2) }
                comps.append(Component(shape: .tractor(bestLen), cards: tc, group: g,
                                       topStrength: start + bestLen - 1))
            }
            // Pairs.
            for (face, cs) in remaining where cs.count >= 2 && trump.group(face) == g {
                let pc = take(face, 2)
                comps.append(Component(shape: .pair, cards: pc, group: g, topStrength: trump.strength(face)))
            }
        }
        // Singles.
        for (_, cs) in remaining {
            for c in cs {
                comps.append(Component(shape: .single, cards: [c], group: trump.group(c),
                                       topStrength: trump.strength(c)))
            }
        }
        return comps.sorted {
            if $0.shape.cardCount != $1.shape.cardCount { return $0.shape.cardCount > $1.shape.cardCount }
            if $0.topStrength != $1.topStrength { return $0.topStrength > $1.topStrength }
            return trump.sortKey($0.cards[0]) > trump.sortKey($1.cards[0])
        }
    }

    /// The shape if `cards` form exactly one component (single, pair or tractor), else nil.
    public static func shape(of cards: [Card], trump: Trump) -> ComboShape? {
        guard group(of: cards, trump: trump) != nil else { return nil }
        let comps = decompose(cards, trump: trump)
        return comps.count == 1 ? comps[0].shape : nil
    }

    /// All possible components of `shape` within `cards` (singles: one per distinct face).
    public static func components(of shape: ComboShape, in cards: [Card], trump: Trump) -> [Component] {
        switch shape {
        case .single:
            return byFace(cards).values.map { cs in
                Component(shape: .single, cards: [cs[0]], group: trump.group(cs[0]), topStrength: trump.strength(cs[0]))
            }.sorted { trump.sortKey($0.cards[0]) < trump.sortKey($1.cards[0]) }
        case .pair:
            return pairs(in: cards, trump: trump).map {
                Component(shape: .pair, cards: $0, group: trump.group($0[0]), topStrength: trump.strength($0[0]))
            }
        case let .tractor(n):
            return tractors(in: cards, length: n, trump: trump).map { tc in
                Component(shape: .tractor(n), cards: tc, group: trump.group(tc[0]),
                          topStrength: tc.map { trump.strength($0) }.max()!)
            }
        }
    }
}
