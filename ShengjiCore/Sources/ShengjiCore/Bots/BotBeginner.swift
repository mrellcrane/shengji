import Foundation

/// Beginner-level play: legal and simple.
///  - Leads the lowest card of its longest plain suit (the lowest trump if it has no plain cards).
///  - Follows with its lowest legal cards, unless its highest legal play would win the trick right now.
enum BeginnerPlay {
    static func decide(_ table: BotTable) -> BotDecision {
        table.isLeading ? lead(table) : follow(table)
    }

    private static func lead(_ table: BotTable) -> BotDecision {
        var longest: [Card] = []
        for suit in Suit.allCases {
            let mine = table.cards(in: .plain(suit))
            if mine.count > longest.count { longest = mine }
        }
        let nudge = "Look at which of your suits is longest."
        let principle = "Keep it simple: lead low cards from your longest suit and save your high cards."
        if let card = longest.first {
            let group = table.trump.group(card)
            let decision = BotDecision(
                cards: [card],
                reason: "Lead \(card), the lowest card of your longest suit, \(BotText.plural(group)).",
                concept: "Lead low", nudge: nudge, principle: principle)
            return LeadCheck.checked(decision, table)
        }
        guard let card = table.hand.first else { return BotText.waiting() }
        let decision = BotDecision(
            cards: [card], reason: "You only have trumps left, so lead your lowest one, \(card).",
            concept: "Lead trumps", nudge: nudge, principle: principle)
        return LeadCheck.checked(decision, table)
    }

    private static func follow(_ table: BotTable) -> BotDecision {
        let trick = table.view.currentTrick
        let builder = FollowBuilder(hand: table.hand, lead: table.view.currentLead, trump: table.trump)
        let high = builder.build(CostModel(table: table, mode: .highest))
        let nudge = "Look at the card that is winning this trick and your highest cards."
        if builder.isLegal(high) && wins(high, trick: trick, table: table) {
            return BotDecision(
                cards: high,
                reason: "Play \(BotText.cards(high, table.trump)): your highest cards win this trick right now.",
                concept: "Win the trick", nudge: nudge,
                principle: "If your highest cards can win the trick, play them. If not, play low.")
        }
        var low = builder.build(CostModel(table: table, mode: .lowest))
        if !builder.isLegal(low) {
            BotDiagnostics.shared.noteFallback()
            low = builder.fallback()
        }
        return BotDecision(
            cards: low,
            reason: "You can't win this trick, so play your lowest legal cards, \(BotText.cards(low, table.trump)).",
            concept: "Duck low", nudge: nudge,
            principle: "If you can't win a trick, play your lowest cards and save the good ones.")
    }

    private static func wins(_ play: [Card], trick: [Play], table: BotTable) -> Bool {
        var plays = trick
        plays.append(Play(player: table.seat, cards: play))
        return Rules.winningIndex(plays, trump: table.trump) == trick.count
    }
}
