import Foundation

/// Finding Friends: the friends a dealer calls when burying (DESIGN.md §Finding Friends).
/// For each plain suit, the highest card the dealer holds no copy of (so someone else answers the call),
/// one suit per friend: suits the dealer still holds cards of first (they can lead one low and let the
/// friend win it), shortest first, then in suit order. If that is not enough, the next card down in the
/// same order; failing that, the second copy of the cards already called.
enum BotFriends {
    static func calls(view: SeatView, buried: [Card]) -> [FriendCall] {
        let needed = view.table.friendCount
        guard needed > 0 else { return [] }
        var hand = view.hand
        hand.remove(cards: buried)
        let trump = view.trump
        let counts = hand.faceCounts
        func held(_ suit: Suit, _ rank: Rank) -> Int { counts[.regular(suit, rank)] ?? 0 }
        let ranks = Rank.allCases.reversed().filter { $0 != trump.rank }
        let suits = Suit.allCases.filter { $0 != trump.suit }
        var length: [Suit: Int] = [:]
        for card in hand where !trump.isTrump(card) {
            if let suit = card.suit { length[suit, default: 0] += 1 }
        }
        let ordered = suits.sorted { a, b in
            let la = length[a] ?? 0, lb = length[b] ?? 0
            if (la == 0) != (lb == 0) { return la != 0 }
            if la != lb { return la < lb }
            return a.rawValue < b.rawValue
        }

        var calls: [FriendCall] = []
        // One unheld card per suit, highest first; then the next unheld card down, suit by suit.
        var depth = 0
        while calls.count < needed, depth < ranks.count {
            for suit in ordered where calls.count < needed {
                let unheld = ranks.filter { held(suit, $0) == 0 }
                guard unheld.indices.contains(depth) else { continue }
                calls.append(FriendCall(unheld[depth], suit))
            }
            depth += 1
        }
        // The dealer holds every card: call later copies of the top cards.
        var ordinal = 2
        while calls.count < needed, ordinal <= max(view.table.decks, 1) {
            for suit in ordered where calls.count < needed {
                guard let top = ranks.first else { break }
                calls.append(FriendCall(top, suit, ordinal: ordinal))
            }
            ordinal += 1
        }
        return calls
    }

    /// One sentence on why these calls, for the hint at the burying step.
    static func reason(_ calls: [FriendCall], view: SeatView, buried: [Card]) -> String {
        guard !calls.isEmpty else { return "This table has fixed partners: there are no friends to call." }
        var hand = view.hand
        hand.remove(cards: buried)
        let trump = view.trump
        let lowSuits = calls.compactMap { call -> Suit? in
            guard let suit = call.face.suit, let rank = call.face.rank else { return nil }
            let called = Card(rank, suit)
            let hasLower = hand.contains {
                !trump.isTrump($0) && $0.suit == suit && trump.strength($0) < trump.strength(called)
            }
            return hasLower ? suit : nil
        }
        let what = "Call \(calls.spokenList)"
        if lowSuits.isEmpty {
            return "\(what): you hold none of them, so whoever plays one joins your side."
        }
        return "\(what): you hold none of them, and you can lead a low card in "
            + (lowSuits.count == 1 ? "that suit" : "those suits") + " so your friends can win it and show themselves."
    }
}

/// The bot's friend calls with the reason it gives.
public struct FriendCallChoice: Hashable, Sendable {
    public var calls: [FriendCall]
    public var reason: String
}

extension Bot {
    /// Finding Friends, dealer only (phase `.burying`): the friends to call when burying `buried`.
    /// Empty at a table of fixed teams.
    public func friendCalls(view: SeatView, buried: [Card]) -> [FriendCall] {
        BotFriends.calls(view: view, buried: buried)
    }

    /// The same calls with a one-sentence reason (the hint at the burying step).
    public func friendCallChoice(view: SeatView, buried: [Card]) -> FriendCallChoice {
        let calls = BotFriends.calls(view: view, buried: buried)
        return FriendCallChoice(calls: calls, reason: BotFriends.reason(calls, view: view, buried: buried))
    }

    /// Offline: the friends this seat calls as dealer when burying `buried`.
    public func friendCalls(in round: Round, buried: [Card]) -> [FriendCall] {
        friendCalls(view: round.seatView(for: Seats.normalized(seat, players: round.players)), buried: buried)
    }
}
