import Foundation

/// The four French suits. Raw values give the default display order (alternating colours).
public enum Suit: Int, CaseIterable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    case spades = 0, hearts, clubs, diamonds

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .clubs: return "♣"
        case .diamonds: return "♦"
        }
    }

    public var name: String {
        switch self {
        case .spades: return "Spades"
        case .hearts: return "Hearts"
        case .clubs: return "Clubs"
        case .diamonds: return "Diamonds"
        }
    }

    /// Singular name, e.g. "spade".
    public var singularName: String {
        switch self {
        case .spades: return "spade"
        case .hearts: return "heart"
        case .clubs: return "club"
        case .diamonds: return "diamond"
        }
    }

    public var isRed: Bool { self == .hearts || self == .diamonds }

    public var description: String { symbol }

    public static func < (lhs: Suit, rhs: Suit) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Card ranks. Raw values are the natural rank (2...14, ace high).
public enum Rank: Int, CaseIterable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    case two = 2, three, four, five, six, seven, eight, nine, ten, jack, queen, king, ace

    /// Short label used on card faces: "2"..."10", "J", "Q", "K", "A".
    public var label: String {
        switch self {
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        default: return String(rawValue)
        }
    }

    public var name: String {
        switch self {
        case .jack: return "Jack"
        case .queen: return "Queen"
        case .king: return "King"
        case .ace: return "Ace"
        default: return String(rawValue)
        }
    }

    /// Point value of a card of this rank: 5s are worth 5, 10s and Kings are worth 10.
    public var points: Int {
        switch self {
        case .five: return 5
        case .ten, .king: return 10
        default: return 0
        }
    }

    public var description: String { label }

    public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The rank `steps` levels above this one, capped at `cap`.
    public func advanced(by steps: Int, cap: Rank = .ace) -> Rank {
        let target = min(rawValue + max(0, steps), cap.rawValue)
        return Rank(rawValue: max(target, rawValue)) ?? self
    }
}

/// What is printed on a card, ignoring which of the two decks it came from.
/// Two cards with the same face form a pair.
public enum Face: Hashable, Codable, Sendable, CustomStringConvertible {
    case regular(Suit, Rank)
    case smallJoker
    case bigJoker

    public var suit: Suit? {
        if case let .regular(s, _) = self { return s }
        return nil
    }

    public var rank: Rank? {
        if case let .regular(_, r) = self { return r }
        return nil
    }

    public var isJoker: Bool { suit == nil }

    public var points: Int { rank?.points ?? 0 }

    /// Stable index 0...53 (52 = small joker, 53 = big joker).
    public var index: Int {
        switch self {
        case let .regular(s, r): return s.rawValue * 13 + (r.rawValue - 2)
        case .smallJoker: return 52
        case .bigJoker: return 53
        }
    }

    public init?(index: Int) {
        switch index {
        case 0..<52:
            guard let s = Suit(rawValue: index / 13), let r = Rank(rawValue: index % 13 + 2) else { return nil }
            self = .regular(s, r)
        case 52: self = .smallJoker
        case 53: self = .bigJoker
        default: return nil
        }
    }

    /// Short text such as "10♥", "A♠", "SJ" (small joker) or "BJ" (big joker).
    public var description: String {
        switch self {
        case let .regular(s, r): return r.label + s.symbol
        case .smallJoker: return "SJ"
        case .bigJoker: return "BJ"
        }
    }

    /// Spoken-style name, e.g. "ten of hearts", "small joker".
    public var longName: String {
        switch self {
        case let .regular(s, r): return "\(r.name.lowercased()) of \(s.name.lowercased())"
        case .smallJoker: return "small joker"
        case .bigJoker: return "big joker"
        }
    }
}

/// A physical card. Shengji uses two full decks (108 cards), so every face exists twice;
/// `copy` (0 or 1) tells the two apart so each card has a unique identity.
public struct Card: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let face: Face
    public let copy: Int

    public init(_ face: Face, copy: Int = 0) {
        self.face = face
        self.copy = copy
    }

    public init(_ rank: Rank, _ suit: Suit, copy: Int = 0) {
        self.init(.regular(suit, rank), copy: copy)
    }

    /// The card with the given `id` (0...107, see `id`), or nil if out of range. This is the card
    /// wire format of online play.
    public init?(id: Int) {
        guard (0..<108).contains(id), let face = Face(index: id % 54) else { return nil }
        self.init(face, copy: id / 54)
    }

    public static func smallJoker(copy: Int = 0) -> Card { Card(.smallJoker, copy: copy) }
    public static func bigJoker(copy: Int = 0) -> Card { Card(.bigJoker, copy: copy) }

    /// Unique id 0...107.
    public var id: Int { face.index + copy * 54 }

    public var suit: Suit? { face.suit }
    public var rank: Rank? { face.rank }
    public var isJoker: Bool { face.isJoker }
    public var points: Int { face.points }
    public var description: String { face.description }
}

public extension Array where Element == Card {
    /// Total point value of the cards.
    var points: Int { reduce(0) { $0 + $1.points } }

    /// Removes the given cards (by identity). Returns false if any card was missing (array unchanged).
    @discardableResult
    mutating func remove(cards: [Card]) -> Bool {
        var copy = self
        for c in cards {
            guard let i = copy.firstIndex(of: c) else { return false }
            copy.remove(at: i)
        }
        self = copy
        return true
    }

    /// True if every card in `cards` is present (by identity).
    func containsAll(_ cards: [Card]) -> Bool {
        var copy = self
        return copy.remove(cards: cards)
    }

    /// Count of each face.
    var faceCounts: [Face: Int] {
        var d: [Face: Int] = [:]
        for c in self { d[c.face, default: 0] += 1 }
        return d
    }

    /// Readable list like "A♠ A♠ K♠".
    var shortText: String { map(\.description).joined(separator: " ") }
}

public enum Deck {
    /// Two full decks including four jokers: 108 cards, in a fixed order.
    public static func double() -> [Card] {
        var cards: [Card] = []
        cards.reserveCapacity(108)
        for copy in 0..<2 {
            for s in Suit.allCases {
                for r in Rank.allCases { cards.append(Card(r, s, copy: copy)) }
            }
            cards.append(.smallJoker(copy: copy))
            cards.append(.bigJoker(copy: copy))
        }
        return cards
    }

    public static func shuffled<G: RandomNumberGenerator>(using rng: inout G) -> [Card] {
        double().shuffled(using: &rng)
    }
}

/// Small, fast, seedable RNG (SplitMix64) so games, drills and tests are reproducible.
public struct SeededGenerator: RandomNumberGenerator, Codable, Hashable, Sendable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
