import Foundation

/// Which "suit" a card belongs to for the purposes of following suit.
/// All trumps (jokers, trump-rank cards, and the trump suit) form one group.
public enum SuitGroup: Hashable, Codable, Sendable, CustomStringConvertible {
    case trump
    case plain(Suit)

    public var isTrump: Bool { self == .trump }

    public var plainSuit: Suit? {
        if case let .plain(s) = self { return s }
        return nil
    }

    /// e.g. "trumps", "spades"
    public var name: String {
        switch self {
        case .trump: return "trumps"
        case let .plain(s): return s.name.lowercased()
        }
    }

    public var symbol: String {
        switch self {
        case .trump: return "Trump"
        case let .plain(s): return s.symbol
        }
    }

    public var description: String { name }
}

/// The trump context for a round: the trump rank (the declaring team's level)
/// and the trump suit (nil when the round is played with no trump suit,
/// in which case only jokers and trump-rank cards are trumps).
///
/// Ordering (highest first), with trump suit ♥ and rank 2:
///   big joker > small joker > 2♥ > 2♠ = 2♣ = 2♦ > A♥ > K♥ > ... > 3♥
/// Plain suits rank A high down to 2, skipping the trump rank.
public struct Trump: Hashable, Codable, Sendable, CustomStringConvertible {
    public var rank: Rank
    public var suit: Suit?

    public init(rank: Rank, suit: Suit?) {
        self.rank = rank
        self.suit = suit
    }

    // MARK: Strength levels (consecutive integers are "adjacent" for tractors)

    /// Highest strength a non-rank card can have (an ace when the rank isn't an ace).
    public static let topPlainStrength = 11
    public static let offSuitRankStrength = 12
    public static let trumpSuitRankStrength = 13
    public static let smallJokerStrength = 14
    public static let bigJokerStrength = 15

    public func isTrump(_ face: Face) -> Bool {
        switch face {
        case .smallJoker, .bigJoker: return true
        case let .regular(s, r): return r == rank || s == suit
        }
    }

    public func isTrump(_ card: Card) -> Bool { isTrump(card.face) }

    public func group(_ face: Face) -> SuitGroup {
        if isTrump(face) { return .trump }
        return .plain(face.suit!)
    }

    public func group(_ card: Card) -> SuitGroup { group(card.face) }

    /// Strength of a card inside its own group. Higher beats lower; equal strength means
    /// the cards tie (the one played first wins). Within a group, consecutive values are
    /// adjacent for tractor purposes.
    ///  - Non-rank cards (plain suits and the trump suit): 0...11, skipping the trump rank.
    ///  - Trump-rank cards not of the trump suit: 12 (13 in a no-trump round).
    ///  - Trump-rank card of the trump suit: 13.
    ///  - Small joker: 14. Big joker: 15.
    public func strength(_ face: Face) -> Int {
        switch face {
        case .smallJoker: return Trump.smallJokerStrength
        case .bigJoker: return Trump.bigJokerStrength
        case let .regular(s, r):
            if r == rank {
                if suit == nil || s == suit { return Trump.trumpSuitRankStrength }
                return Trump.offSuitRankStrength
            }
            let base = r.rawValue - 2
            return r.rawValue > rank.rawValue ? base - 1 : base
        }
    }

    public func strength(_ card: Card) -> Int { strength(card.face) }

    /// Plain suits in display order: colours alternate where possible, trump suit excluded.
    public var plainSuitOrder: [Suit] {
        let suits = Suit.allCases.filter { $0 != suit }
        let blacks = suits.filter { !$0.isRed }
        let reds = suits.filter { $0.isRed }
        var first = blacks.count >= reds.count ? blacks : reds
        var second = blacks.count >= reds.count ? reds : blacks
        var out: [Suit] = []
        while !first.isEmpty || !second.isEmpty {
            if !first.isEmpty { out.append(first.removeFirst()) }
            if !second.isEmpty { out.append(second.removeFirst()) }
        }
        return out
    }

    /// Sort key for showing a hand left-to-right: plain suits (alternating colours),
    /// then trumps on the right; low to high within each group.
    public func sortKey(_ card: Card) -> Int {
        let g = group(card)
        let groupIndex: Int
        switch g {
        case .trump: groupIndex = 4
        case let .plain(s): groupIndex = plainSuitOrder.firstIndex(of: s) ?? 0
        }
        let tiebreak = card.suit.map { 3 - $0.rawValue } ?? 0
        return groupIndex * 1000 + strength(card) * 10 + tiebreak
    }

    public func sorted(_ cards: [Card]) -> [Card] {
        cards.sorted { a, b in
            let ka = sortKey(a), kb = sortKey(b)
            return ka != kb ? ka < kb : a.id < b.id
        }
    }

    /// Compares two cards of the same group. Returns nil if they are in different groups.
    public func compareWithinGroup(_ a: Face, _ b: Face) -> Int? {
        guard group(a) == group(b) else { return nil }
        return strength(a) - strength(b)
    }

    /// e.g. "5♥" (rank 5, hearts trump) or "5 · no trump suit"
    public var description: String {
        if let s = suit { return rank.label + s.symbol }
        return "\(rank.label) · no trump suit"
    }

    /// Plain-English summary used by the coach, e.g. "Trump suit ♥, trump rank 5".
    public var summary: String {
        if let s = suit { return "Trump suit \(s.symbol), trump rank \(rank.label)" }
        return "No trump suit, trump rank \(rank.label) (only jokers and \(rank.label)s are trump)"
    }

    /// All faces that are trump this round, highest first (ties grouped together).
    public var trumpFacesHighToLow: [Face] {
        var faces: [Face] = [.bigJoker, .smallJoker]
        for s in Suit.allCases { faces.append(.regular(s, rank)) }
        if let ts = suit {
            for r in Rank.allCases.reversed() where r != rank { faces.append(.regular(ts, r)) }
        }
        return faces.sorted { strength($0) > strength($1) }
    }
}
