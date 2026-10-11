import Foundation

/// Small helpers for the learner-facing sentences in `BotDecision`.
/// Rules for the texts: second person, short and warm. `nudge` and `principle` never name cards
/// (no suit symbols, ranks, digits or joker codes); `reason` always names the chosen cards.
enum BotText {
    /// How `seat` refers to `player` at a table of `players`: "you", "your partner", or a compass
    /// name. With 6 or 8 players there are several partners, so they are "your partner Northeast"; with
    /// an odd number nobody has a fixed partner, so everyone gets their compass name.
    static func name(_ player: Int, from seat: Int, players: Int = 4) -> String {
        let n = max(players, 4)
        let p = Seats.normalized(player, players: n)
        let me = Seats.normalized(seat, players: n)
        if p == me { return "you" }
        if n == 4 {
            if p == Seats.partner(of: me) { return "your partner" }
            return Seats.compassName(p, players: 4)
        }
        let compass = Seats.compassName(p, players: n)
        // Finding Friends (odd tables): no fixed partners to name.
        if n % 2 == 1 { return compass }
        return Seats.team(of: p) == Seats.team(of: me) ? "your partner \(compass)" : compass
    }

    /// "your", "your partner's", "East's".
    static func possessive(_ player: Int, from seat: Int, players: Int = 4) -> String {
        let n = max(players, 4)
        if Seats.normalized(player, players: n) == Seats.normalized(seat, players: n) { return "your" }
        return name(player, from: seat, players: n) + "'s"
    }

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Cards in display order, e.g. "9♠ 9♠ K♠".
    static func cards(_ cards: [Card], _ trump: Trump) -> String {
        CardOrder(trump).sorted(cards).shortText
    }

    static func points(_ value: Int) -> String {
        value == 1 ? "1 point" : "\(value) points"
    }

    /// "spade" / "trump".
    static func singular(_ group: SuitGroup) -> String {
        switch group {
        case .trump: return "trump"
        case let .plain(suit): return suit.singularName
        }
    }

    /// "spades" / "trumps".
    static func plural(_ group: SuitGroup) -> String { group.name }

    /// "clubs", "clubs and hearts", "clubs, hearts and spades".
    static func list(_ words: [String]) -> String {
        guard let last = words.last else { return "" }
        if words.count == 1 { return last }
        return words.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Returned when a bot is asked to act out of turn (never by the app, but it must not crash).
    static func waiting() -> BotDecision {
        BotDecision(cards: [], reason: "It isn't your turn to play yet, so there is nothing to choose.",
                    concept: "Wait",
                    nudge: "Watch the cards as they are played.",
                    principle: "While you wait, notice which high cards and point cards are gone.")
    }

    /// Returned when asked to bury outside the burying phase or by a non-dealer.
    static func notBurying() -> BotDecision {
        BotDecision(cards: [], reason: "Only the dealer buries cards, right after picking up the kitty.",
                    concept: "Bury low",
                    nudge: "Check whose turn it is to bury.",
                    principle: "The dealer picks up the kitty and buries the same number of cards face down.")
    }
}
