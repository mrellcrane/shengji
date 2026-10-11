import Foundation

/// Finding Friends (找朋友 zhǎo péngyou): with an odd number of players nobody has fixed partners. After
/// burying, the dealer calls friends by naming cards, such as "the first A♠" or "the second K♥". Whoever
/// plays that copy of the card this round joins the dealer's side, and nobody knows who the friends are
/// until they play it. If the dealer (or someone already found) plays it, the dealer's side gains
/// nobody, so it plays short-handed.
public struct FriendCall: Hashable, Sendable, CustomStringConvertible {
    /// The card named: any suited card that is not of the trump rank (jokers and trump-rank cards
    /// can't be called).
    public var face: Face
    /// Which copy counts: 1 = the first one played this round, 2 = the second, up to the number of decks.
    public var ordinal: Int
    /// The seat that played that copy, once it has been played.
    public var friend: Int?

    public init(face: Face, ordinal: Int = 1, friend: Int? = nil) {
        self.face = face
        self.ordinal = ordinal
        self.friend = friend
    }

    public init(_ rank: Rank, _ suit: Suit, ordinal: Int = 1) {
        self.init(face: .regular(suit, rank), ordinal: ordinal)
    }

    /// True once the called copy has been played.
    public var isFound: Bool { friend != nil }

    /// "first", "second", ... for the ordinal.
    public var ordinalWord: String { FriendCall.ordinalWord(ordinal) }

    /// e.g. "the first A♠"
    public var description: String { "the \(ordinalWord) \(face)" }

    static func ordinalWord(_ n: Int) -> String {
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        default: return "#\(n)"
        }
    }

    /// The same call before anyone has played the card.
    public var unfound: FriendCall { FriendCall(face: face, ordinal: ordinal) }

    /// Why the dealer can't make `calls` at `table` when `trumpRank` is trump, or nil when they can:
    /// exactly `table.friendCount` calls, each a suited card that is not of the trump rank, a copy that
    /// exists (1 up to the number of decks), and no call made twice.
    public static func problem(with calls: [FriendCall], table: TableSize, trumpRank: Rank) -> String? {
        let needed = table.friendCount
        guard needed > 0 else {
            return calls.isEmpty ? nil : "Only a table with an odd number of players calls friends."
        }
        guard calls.count == needed else {
            let friends = needed == 1 ? "1 friend" : "\(needed) friends"
            return "Call exactly \(friends) (you called \(calls.count))."
        }
        var seen = Set<FriendCall>()
        for call in calls {
            guard let rank = call.face.rank else {
                return "Jokers can't be called: pick a suited card."
            }
            guard rank != trumpRank else {
                return "Trump-rank cards (\(rank.label)) can't be called: pick another card."
            }
            guard (1...max(table.decks, 1)).contains(call.ordinal) else {
                return "With \(table.decks) decks there are only \(table.decks) copies of each card: "
                    + "call one of the first \(table.decks)."
            }
            guard seen.insert(call.unfound).inserted else {
                return "You called \(call) twice: pick a different card or copy."
            }
        }
        return nil
    }
}

/// Wire and storage format: {"face": face index 0...53, "ordinal": n, "friend": seat (absent until found)}.
extension FriendCall: Codable {
    private enum CodingKeys: String, CodingKey { case face, ordinal, friend }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let index = try container.decode(Int.self, forKey: .face)
        guard let face = Face(index: index) else {
            throw DecodingError.dataCorruptedError(forKey: .face, in: container,
                                                   debugDescription: "Face index \(index) is out of range 0...53")
        }
        self.face = face
        self.ordinal = try container.decode(Int.self, forKey: .ordinal)
        self.friend = try container.decodeIfPresent(Int.self, forKey: .friend)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(face.index, forKey: .face)
        try container.encode(ordinal, forKey: .ordinal)
        try container.encodeIfPresent(friend, forKey: .friend)
    }
}

public extension Array where Element == FriendCall {
    /// Calls with any friend found by `player`'s play of `cards`, given every card played before it this
    /// round: a call is found when this play holds the copy that reaches its ordinal.
    func noting(_ cards: [Card], by player: Int, playedBefore: [Card]) -> [FriendCall] {
        map { call in
            guard call.friend == nil else { return call }
            let before = playedBefore.reduce(0) { $0 + ($1.face == call.face ? 1 : 0) }
            let now = cards.reduce(0) { $0 + ($1.face == call.face ? 1 : 0) }
            guard before < call.ordinal, before + now >= call.ordinal else { return call }
            var found = call
            found.friend = player
            return found
        }
    }

    /// "the first A♠ and the second K♥"
    var spokenList: String {
        let names = map(\.description)
        switch names.count {
        case 0: return "no friends"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}
