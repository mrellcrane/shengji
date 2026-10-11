import Foundation

/// Burying the kitty (dealer only): exactly as many cards as the kitty held (8, or 6 with 6 players).
///  - Standard: never trumps unless there are too few other cards; avoids aces, pairs and point
///    cards; prefers emptying short plain suits entirely (a void lets you trump that suit later);
///    otherwise the lowest singles.
///  - Beginner: the 8 lowest cards that aren't trumps.
enum BotBurying {
    /// Nil unless the viewer is the dealer, burying, with at least 8 cards (the kitty included).
    static func decide(for bot: Bot, view: SeatView) -> BotDecision? {
        guard view.phase == .burying, view.dealer == 0, view.hand.count >= view.table.kittySize else { return nil }
        let table = BotTable(view: view, compassSeat: bot.normalizedSeat, usesPlayerNames: bot.usesPlayerNames, tuning: bot.tuning)
        switch bot.level {
        case .beginner: return beginner(table)
        case .standard: return standard(table)
        }
    }

    static let nudge = "Look at which of your plain suits are short and which cards you could spare."

    /// How much it hurts to bury a card (lower = bury first).
    static func cost(_ card: Card, _ table: BotTable) -> Int {
        let strength = table.trump.strength(card)
        var cost: Int
        if table.trump.isTrump(card) {
            cost = 1000 + 10 * strength
        } else {
            cost = 2 * strength
            if strength >= Trump.topPlainStrength { cost += 40 }
        }
        cost += 4 * card.points
        if table.pairFaces.contains(card.face) { cost += 40 }
        if table.tractorFaces.contains(card.face) { cost += 20 }
        return cost
    }

    private static func cheapest(_ cards: [Card], _ count: Int, _ table: BotTable) -> [Card] {
        guard count > 0 else { return [] }
        var scored: [ScoredCard] = []
        for card in cards {
            scored.append(ScoredCard(card: card, cost: cost(card, table), key: table.order.key(card)))
        }
        scored.sort { $0.precedes($1) }
        return scored.prefix(count).map { $0.card }
    }

    private static func standard(_ table: BotTable) -> BotDecision {
        let size = table.view.table.kittySize
        var suits: [Suit] = []
        for suit in Suit.allCases where !table.cards(in: .plain(suit)).isEmpty { suits.append(suit) }
        let trumpCount = table.trumps.count
        // A void is only worth much with trumps to ruff with.
        let voidBonus = trumpCount >= 8 ? 30 : (trumpCount >= 5 ? 18 : 6)

        var best: (cards: [Card], score: Int)?
        for mask in 0..<(1 << suits.count) {
            var voided: Set<SuitGroup> = []
            var chosen: [Card] = []
            for (index, suit) in suits.enumerated() where mask & (1 << index) != 0 {
                voided.insert(.plain(suit))
                chosen += table.cards(in: .plain(suit))
            }
            guard chosen.count <= size else { continue }
            let rest = table.hand.filter { !voided.contains(table.trump.group($0)) }
            let cards = chosen + cheapest(rest, size - chosen.count, table)
            guard cards.count == size else { continue }
            var score = -voidBonus * voided.count
            for card in cards { score += cost(card, table) }
            if let current = best, current.score <= score { continue }
            best = (cards, score)
        }
        let cards = best?.cards ?? cheapest(table.hand, size, table)
        return explain(cards, table)
    }

    private static func explain(_ cards: [Card], _ table: BotTable) -> BotDecision {
        let names = BotText.cards(cards, table.trump)
        var emptied: [String] = []
        for suit in Suit.allCases {
            let mine = table.cards(in: .plain(suit))
            if !mine.isEmpty && cards.containsAll(mine) { emptied.append(suit.name.lowercased()) }
        }
        // Only claim to keep what this burial really keeps.
        let trump = table.trump
        var kept: [String] = []
        if !cards.contains(where: { trump.isTrump($0) }) { kept.append("trumps") }
        if !cards.contains(where: { $0.rank == .ace && !trump.isTrump($0) }) { kept.append("aces") }
        if !cards.contains(where: { table.pairFaces.contains($0.face) }) { kept.append("pairs") }
        if cards.points == 0 { kept.append("points") }
        var reason: String
        let concept: String
        if !emptied.isEmpty {
            let suits = BotText.list(emptied)
            let them = emptied.count == 1 ? "that suit" : "those suits"
            reason = "Bury \(names). This empties your \(suits), so you can trump \(them) later"
            reason += kept.isEmpty ? "." : ", and you keep your \(BotText.list(kept))."
            concept = "Create a void"
        } else {
            reason = "Bury \(names), the cards you will miss least"
            reason += kept.isEmpty ? "." : ", and keep your \(BotText.list(kept))."
            concept = "Bury low"
        }
        if cards.contains(where: { table.trump.isTrump($0) }) {
            reason += " You don't have \(cards.count) other cards, so a few low trumps go too."
        }
        if cards.points > 0 {
            reason += " This buries \(BotText.points(cards.points)), so try to win the last trick to protect them."
        }
        return BotDecision(
            cards: cards, reason: reason, concept: concept, nudge: nudge,
            principle: "Bury low cards you won't miss. Keep trumps, aces, pairs and points, and empty a short suit "
                + "if you can, so you can trump it later.")
    }

    private static func beginner(_ table: BotTable) -> BotDecision {
        let cards = BotPick.cheapest(table.hand, table.view.table.kittySize, CostModel(table: table, mode: .lowest))
        let names = BotText.cards(cards, table.trump)
        var reason = "Bury \(names), your lowest cards that aren't trumps."
        if cards.contains(where: { table.trump.isTrump($0) }) {
            reason = "Bury \(names): your lowest cards, using low trumps only because you ran out of other cards."
        }
        return BotDecision(
            cards: cards, reason: reason, concept: "Bury low", nudge: nudge,
            principle: "Bury low cards you won't miss, and keep your trumps.")
    }
}
