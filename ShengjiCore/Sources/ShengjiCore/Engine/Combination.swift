import Foundation

/// The basic building blocks of a play.
///  - single: one card
///  - pair: two identical cards (same face; e.g. two 7♠; but 2♠ + 2♣ is NOT a pair)
///  - tractor(n): n ≥ 2 pairs of consecutive strength in the same suit group (拖拉机)
/// With three or more decks a face can appear three or four times, which adds:
///  - set(n): n ≥ 3 identical cards (a triple, 刻子; four of a kind)
///  - setTractor: `length` ≥ 2 sets of `width` ≥ 3 identical cards at consecutive strengths in one
///    suit group (a tractor of triples, 推土机)
/// Every shape is `width` identical cards at each of `length` consecutive strengths; `make` builds
/// the case for a width and length.
public enum ComboShape: Hashable, Codable, Sendable, CustomStringConvertible {
    case single
    case pair
    case tractor(Int)
    case set(Int)
    case setTractor(width: Int, length: Int)

    /// The shape of `length` consecutive sets of `width` identical cards (width 1: a single).
    public static func make(width: Int, length: Int) -> ComboShape {
        let w = max(1, width), l = max(1, length)
        if w == 1 { return .single }
        if w == 2 { return l == 1 ? .pair : .tractor(l) }
        return l == 1 ? .set(w) : .setTractor(width: w, length: l)
    }

    /// Identical cards at each strength: 1 for a single, 2 for pairs and tractors, 3 for triples.
    public var width: Int {
        switch self {
        case .single: return 1
        case .pair, .tractor: return 2
        case let .set(n): return n
        case let .setTractor(width, _): return width
        }
    }

    /// Consecutive strengths: 1 for a single, pair or set, the number of steps for a tractor.
    public var length: Int {
        switch self {
        case .single, .pair, .set: return 1
        case let .tractor(n): return n
        case let .setTractor(_, length): return length
        }
    }

    public var cardCount: Int { width * length }

    /// Pairs the shape holds (a triple holds one, four of a kind two).
    public var pairCount: Int { length * (width / 2) }

    /// True for tractors of pairs, triples or more.
    public var isTractor: Bool { length >= 2 }

    /// True for shapes that only exist with three or more decks (sets and tractors of three or more
    /// identical cards).
    public var needsMoreDecks: Bool { width >= 3 }

    public var name: String {
        switch self {
        case .single: return "single"
        case .pair: return "pair"
        case let .tractor(n): return n == 2 ? "tractor" : "tractor of \(n) pairs"
        case let .set(n): return ComboShape.setName(n)
        case let .setTractor(width, length):
            let sets = ComboShape.setsName(width)
            return length == 2 ? "tractor of \(sets)" : "tractor of \(length) \(sets)"
        }
    }

    /// "triple", "four of a kind", "5 of a kind".
    static func setName(_ width: Int) -> String {
        switch width {
        case 3: return "triple"
        case 4: return "four of a kind"
        default: return "\(width) of a kind"
        }
    }

    /// "triples", "fours", "5s".
    static func setsName(_ width: Int) -> String {
        switch width {
        case 3: return "triples"
        case 4: return "fours"
        default: return "\(width)s"
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

    /// The most copies of any one face among `cards` (0 when empty). Two decks give at most 2; with
    /// three or more decks a face can appear three or four times (triples, four of a kind).
    public static func maxCopies(_ cards: [Card]) -> Int {
        var counts: [Int: Int] = [:]
        var best = 0
        for card in cards {
            let count = (counts[card.face.index] ?? 0) + 1
            counts[card.face.index] = count
            best = max(best, count)
        }
        return best
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

    // MARK: Sets of identical cards (any width)

    /// Every set of `width` identical cards in `cards`: the lowest-id `width` copies of each face held
    /// at least that often, sorted by group then strength ascending (width 2: `pairs(in:)`).
    public static func sets(in cards: [Card], width: Int, trump: Trump) -> [[Card]] {
        let w = max(1, width)
        return byFace(cards).values
            .filter { $0.count >= w }
            .map { Array($0.prefix(w)) }
            .sorted { trump.sortKey($0[0]) < trump.sortKey($1[0]) }
    }

    /// Like `sets(in:width:)` but a face held twice as often gives two sets (four 7♠ are two pairs),
    /// lowest ids first.
    static func allSets(in cards: [Card], width: Int, trump: Trump) -> [[Card]] {
        let w = max(1, width)
        var out: [[Card]] = []
        for copies in byFace(cards).values where copies.count >= w {
            var start = 0
            while start + w <= copies.count {
                out.append(Array(copies[start..<(start + w)]))
                start += w
            }
        }
        return out.sorted { a, b in
            let ka = trump.sortKey(a[0]), kb = trump.sortKey(b[0])
            return ka != kb ? ka < kb : a[0].id < b[0].id
        }
    }

    /// Faces of one group held at least `width` times, bucketed by strength level (width 2: `pairLevels`).
    static func setLevels(_ cards: [Card], width: Int, group: SuitGroup, trump: Trump) -> [Int: [Face]] {
        var levels: [Int: [Face]] = [:]
        for (face, cs) in byFace(cards) where cs.count >= width && trump.group(face) == group {
            levels[trump.strength(face), default: []].append(face)
        }
        for k in levels.keys {
            levels[k]!.sort { ($0.suit?.rawValue ?? 9) < ($1.suit?.rawValue ?? 9) }
        }
        return levels
    }

    /// Every tractor of exactly `length` consecutive sets of `width` identical cards (width 2:
    /// `tractors(in:length:)`). Each result is width × length cards, low to high.
    public static func setTractors(in cards: [Card], width: Int, length: Int, trump: Trump) -> [[Card]] {
        guard length >= 2, width >= 2 else { return [] }
        if width == 2 { return tractors(in: cards, length: length, trump: trump) }
        let faceCards = byFace(cards)
        var results: [[Card]] = []
        for g in groups(in: cards, trump: trump) {
            let levels = setLevels(cards, width: width, group: g, trump: trump)
            for start in levels.keys.sorted() {
                let run = (start..<(start + length))
                guard run.allSatisfy({ levels[$0] != nil }) else { continue }
                var partials: [[Card]] = [[]]
                for level in run {
                    var next: [[Card]] = []
                    for p in partials {
                        for f in levels[level]! { next.append(p + Array(faceCards[f]!.prefix(width))) }
                    }
                    partials = next
                }
                results.append(contentsOf: partials)
            }
        }
        return results
    }

    /// Length of the longest run of sets of `width` identical cards: 0 = none, 1 = sets but no tractor.
    public static func longestRun(in cards: [Card], width: Int, trump: Trump) -> Int {
        if width == 2 { return longestRun(in: cards, trump: trump) }
        var best = 0
        for g in groups(in: cards, trump: trump) {
            let keys = Set(setLevels(cards, width: width, group: g, trump: trump).keys)
            for k in keys where !keys.contains(k - 1) {
                var n = 0
                while keys.contains(k + n) { n += 1 }
                best = max(best, n)
            }
        }
        return best
    }

    /// Every way to take one combination of `shape` (width 2 or more) out of `cards`, as card lists:
    /// one per face (or per choice of faces along a tractor), using the lowest-id copies.
    public static func units(of shape: ComboShape, in cards: [Card], trump: Trump) -> [[Card]] {
        switch shape {
        case .single: return byFace(cards).values.map { [$0[0]] }.sorted { trump.sortKey($0[0]) < trump.sortKey($1[0]) }
        case .pair: return pairs(in: cards, trump: trump)
        case let .tractor(n): return tractors(in: cards, length: n, trump: trump)
        case let .set(n): return sets(in: cards, width: n, trump: trump)
        case let .setTractor(width, length): return setTractors(in: cards, width: width, length: length, trump: trump)
        }
    }

    // MARK: Decomposition

    /// Splits cards into components: tractors first (longest runs greedily), then pairs, then singles.
    /// Sorted largest first (by card count), then by strength descending.
    /// This is the canonical "format" of a lead.
    /// With three or more decks, where a face can appear three or four times, the widest sets are
    /// taken first: tractors of the widest sets, then those sets, then narrower ones (777 888 99 is a
    /// tractor of triples and a pair).
    public static func decompose(_ cards: [Card], trump: Trump) -> [Component] {
        if maxCopies(cards) > 2 { return decomposeSets(cards, trump: trump) }
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

    /// `decompose` for cards holding three or more copies of a face.
    static func decomposeSets(_ cards: [Card], trump: Trump) -> [Component] {
        var remaining = byFace(cards)
        var comps: [Component] = []

        func take(_ face: Face, _ n: Int) -> [Card] {
            let taken = Array(remaining[face]!.prefix(n))
            remaining[face]!.removeFirst(n)
            if remaining[face]!.isEmpty { remaining[face] = nil }
            return taken
        }

        for g in groups(in: cards, trump: trump) {
            let widest = remaining.filter { trump.group($0.key) == g }.map { $0.value.count }.max() ?? 0
            var width = widest
            while width >= 2 {
                // Tractors of this width: repeatedly take the longest run available (ties: the highest).
                while true {
                    let flat = remaining.values.flatMap { $0 }
                    let levels = setLevels(flat, width: width, group: g, trump: trump)
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
                    for level in start..<(start + bestLen) { tc += take(levels[level]![0], width) }
                    comps.append(Component(shape: .make(width: width, length: bestLen), cards: tc, group: g,
                                           topStrength: start + bestLen - 1))
                }
                // Sets of this width.
                for (face, cs) in remaining where cs.count >= width && trump.group(face) == g {
                    let set = take(face, width)
                    comps.append(Component(shape: .make(width: width, length: 1), cards: set, group: g,
                                           topStrength: trump.strength(face)))
                }
                width -= 1
            }
        }
        for (_, cs) in remaining {
            for c in cs {
                comps.append(Component(shape: .single, cards: [c], group: trump.group(c),
                                       topStrength: trump.strength(c)))
            }
        }
        return comps.sorted {
            if $0.shape.cardCount != $1.shape.cardCount { return $0.shape.cardCount > $1.shape.cardCount }
            if $0.topStrength != $1.topStrength { return $0.topStrength > $1.topStrength }
            if $0.shape.width != $1.shape.width { return $0.shape.width > $1.shape.width }
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
        case let .set(n):
            return sets(in: cards, width: n, trump: trump).map {
                Component(shape: shape, cards: $0, group: trump.group($0[0]), topStrength: trump.strength($0[0]))
            }
        case let .setTractor(width, length):
            return setTractors(in: cards, width: width, length: length, trump: trump).map { tc in
                Component(shape: shape, cards: tc, group: trump.group(tc[0]),
                          topStrength: tc.map { trump.strength($0) }.max()!)
            }
        }
    }
}
