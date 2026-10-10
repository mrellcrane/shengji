import Foundation

/// Standard-level leading (DESIGN.md §Bot strategy), in priority order:
/// 1. a throw that is guaranteed to stand, in a plain suit no opponent has shown out of;
/// 2. a sure-winning plain tractor, pair or single;
/// 3. declarers with many trumps draw trumps (top pairs, else low singles);
/// 4. a suit the partner is out of, so the partner can ruff;
/// 5. a low non-point card (or low pair) from a short plain suit; last resort, the lowest trump.
/// A point card that something unseen can beat is never led while a lead without points exists
/// (leading into the partner's void aside). Reasons for plain-suit winners say "only a trump can
/// beat it" rather than promising the trick: someone may be out of the suit without having shown it.
struct StandardLead {
    let table: BotTable

    func decide() -> BotDecision {
        LeadCheck.checked(choose(), table)
    }

    private func choose() -> BotDecision {
        if let decision = throwLead() { return decision }
        if table.tuning.drawBeforeCashing, let decision = drawTrumps() { return decision }
        if let decision = sureWinnerLead() { return decision }
        if let decision = drawTrumps() { return decision }
        if let decision = partnerVoidLead() { return decision }
        if let decision = lowLead() { return decision }
        return lastResort()
    }

    private var trump: Trump { table.trump }
    private var unseen: [Card] { table.knowledge.unseen }

    /// No opponent has shown out of the plain group, and enough of it is still out that an
    /// unseen void is unlikely.
    private func safeToCash(_ group: SuitGroup) -> Bool {
        for opponent in table.opponents where table.mayRuff(opponent, group) { return false }
        return !table.isRunningOut(group, count: 1, players: 2)
    }

    // MARK: 1. Throws

    private func throwLead() -> BotDecision? {
        var best: (cards: [Card], group: SuitGroup, score: Int)?
        for suit in Suit.allCases {
            let group = SuitGroup.plain(suit)
            let mine = table.cards(in: group)
            guard mine.count >= 2, mightThrow(group), safeToCash(group) else { continue }
            var cards: [Card] = []
            var parts = 0
            for component in Combos.decompose(mine, trump: trump) where !table.unseenCanBeat(component) {
                cards += component.cards
                parts += 1
            }
            guard parts >= 2, Rules.isThrow(cards, trump: trump),
                  Rules.checkThrow(cards, against: unseen, trump: trump) == .ok else { continue }
            let score = 10 * cards.count + cards.points
            if let current = best, current.score >= score { continue }
            best = (cards, group, score)
        }
        guard let pick = best else { return nil }
        let names = BotText.cards(pick.cards, trump)
        let suits = BotText.plural(pick.group)
        // A plain-suit throw can still be trumped by someone who is out of the suit without having
        // shown it, so the reason says what is certain and no more.
        return BotDecision(
            cards: pick.cards,
            reason: "No \(BotText.singular(pick.group)) still out can beat any part of \(names), "
                + "so throw them together. Only a player out of \(suits) could trump them.",
            concept: "Throw",
            nudge: "Look for a suit where nobody else can beat any of your cards.",
            principle: "If nobody can beat any part of a group of cards in one suit, lead them all at once as a throw.")
    }

    // MARK: 2. Sure winners

    /// Quick check before decomposing a suit: at least two of its pieces could be unbeatable.
    private func mightThrow(_ group: SuitGroup) -> Bool {
        let pieces = table.pieces(in: group)
        var solid = 0
        for card in pieces.singles where !table.unseenCanBeat(.single, group: group, strength: trump.strength(card)) {
            solid += 1
        }
        for pair in pieces.pairs where !table.unseenCanBeat(.pair, group: group, strength: trump.strength(pair[0])) {
            solid += 1
        }
        let hasTractor = pieces.pairs.contains { table.tractorFaces.contains($0[0].face) }
        return solid >= 2 || hasTractor
    }

    private func sureWinnerLead() -> BotDecision? {
        var best: (component: Component, score: Int)?
        func consider(_ component: Component) {
            guard !table.unseenCanBeat(component) else { return }
            var score = 100 * component.cards.count + 3 * component.cards.points
            if component.shape == .single && table.pairPenalty(component.cards[0]) > 0 { score -= 50 }
            if let current = best, current.score >= score { return }
            best = (component, score)
        }
        for suit in Suit.allCases {
            let group = SuitGroup.plain(suit)
            let mine = table.cards(in: group)
            guard !mine.isEmpty, safeToCash(group) else { continue }
            let pieces = table.pieces(in: group)
            for card in pieces.singles {
                consider(Component(shape: .single, cards: [card], group: group, topStrength: trump.strength(card)))
            }
            for pair in pieces.pairs {
                consider(Component(shape: .pair, cards: pair, group: group, topStrength: trump.strength(pair[0])))
            }
            guard pieces.pairs.contains(where: { table.tractorFaces.contains($0[0].face) }) else { continue }
            let run = Combos.longestRun(in: mine, trump: trump)
            if run >= 2 {
                for length in 2...run {
                    for component in Combos.components(of: .tractor(length), in: mine, trump: trump) {
                        consider(component)
                    }
                }
            }
        }
        guard let pick = best else { return nil }
        let cards = pick.component.cards
        let names = BotText.cards(cards, trump)
        let suitWord = BotText.singular(pick.component.group)
        // Plain suits only: someone out of the suit could still trump it, so promise no more than that.
        var reason: String
        switch pick.component.shape {
        case .single:
            reason = "\(names) is the highest \(suitWord) still out, so only a trump can beat it."
        case .pair:
            reason = "Nobody can hold a higher \(suitWord) pair than \(names), so only a pair of trumps can beat it."
        case .tractor:
            reason = "No \(suitWord) tractor still out can beat \(names), so only trumps can beat it."
        }
        if cards.points > 0 {
            reason += " Cash its \(BotText.points(cards.points)) now, before someone runs out of "
                + "\(BotText.plural(pick.component.group))."
        }
        return BotDecision(
            cards: cards, reason: reason, concept: "Sure winner",
            nudge: "Count the high cards that are already gone in each suit.",
            principle: "Lead a card nobody can beat to win a trick safely, before an opponent runs out of that suit.")
    }

    // MARK: 3. Draw trumps

    private func drawTrumps() -> BotDecision? {
        guard table.isDeclarer, table.tuning.drawTrumps else { return nil }
        let mine = table.trumps
        guard mine.count >= 4, mine.count >= 8 || 2 * mine.count >= table.hand.count,
              !table.unseen(in: .trump).isEmpty else { return nil }
        guard table.opponents.contains(where: { !table.knowledge.isVoid($0, in: .trump) }) else { return nil }
        let nudge = "Count your trumps and think about how many are still out."
        let principle = "When your side holds most of the trumps, lead them to pull trumps out of your "
            + "opponents' hands. Then your other winners are safe."

        // Top pairs or tractors nobody can beat.
        if let component = sureTrumpCombo() {
            let names = BotText.cards(component.cards, trump)
            return BotDecision(
                cards: component.cards,
                reason: "Nobody can beat \(names), so lead it to pull trumps out of your opponents' hands.",
                concept: "Draw trumps", nudge: nudge, principle: principle)
        }

        // A low single: no points, not from a pair, not a joker or trump-rank card.
        var low: Card?
        for card in mine where card.points == 0 && !table.pairFaces.contains(card.face)
            && !card.isJoker && card.rank != trump.rank {
            if let current = low, table.value(current) <= table.value(card) { continue }
            low = card
        }
        guard let card = low else { return nil }
        return BotDecision(
            cards: [card],
            reason: "You hold \(mine.count) trumps, so lead \(card), one you can spare, to draw out your opponents' trumps.",
            concept: "Draw trumps", nudge: nudge, principle: principle)
    }

    // MARK: 4. Partner's void

    private func partnerVoidLead() -> BotDecision? {
        guard !table.knowledge.isVoid(table.partner, in: .trump) else { return nil }
        var best: (card: Card, group: SuitGroup, score: Int)?
        for suit in Suit.allCases {
            let group = SuitGroup.plain(suit)
            guard table.knowledge.isVoid(table.partner, in: group) else { continue }
            guard !table.opponents.contains(where: { table.mayRuff($0, group) }) else { continue }
            for card in table.cards(in: group) {
                let score = table.value(card) + table.pairPenalty(card) + 2 * card.points
                if let current = best, current.score <= score { continue }
                best = (card, group, score)
            }
        }
        guard let pick = best else { return nil }
        return BotDecision(
            cards: [pick.card],
            reason: "Your partner is out of \(BotText.plural(pick.group)), so lead \(pick.card) "
                + "and let them win it with a trump.",
            concept: "Partner's void",
            nudge: "Think about which suits your partner has already run out of.",
            principle: "Lead a suit your partner is out of, so they can win the trick with a trump.")
    }

    // MARK: 5. Low lead

    private func lowLead() -> BotDecision? {
        var best: (cards: [Card], group: SuitGroup, score: Int)?
        for suit in Suit.allCases {
            let group = SuitGroup.plain(suit)
            let mine = table.cards(in: group)
            guard !mine.isEmpty else { continue }
            let ruffRisk = table.opponents.contains(where: { table.mayRuff($0, group) }) ? 25 : 0
            let base = 3 * mine.count + ruffRisk
            for card in mine where card.points == 0 && !table.pairFaces.contains(card.face) {
                let score = base + 2 * trump.strength(card) + (table.isTopUnseen(card) ? 20 : 0)
                if let current = best, current.score <= score { continue }
                best = ([card], group, score)
            }
            for pair in Combos.pairs(in: mine, trump: trump) {
                guard let first = pair.first, first.points == 0 else { continue }
                let linked = table.tractorFaces.contains(first.face) ? 20 : 0
                let score = base + 2 * trump.strength(first) + 6 + linked
                if let current = best, current.score <= score { continue }
                best = (pair, group, score)
            }
        }
        guard let pick = best else { return nil }
        let names = BotText.cards(pick.cards, trump)
        let suitCount = table.cards(in: pick.group).count
        let reason: String
        if pick.cards.count == 2 {
            reason = "Lead \(names): a low pair gives away no points, and others must spend a pair to beat it."
        } else if suitCount <= 3 {
            let suits = BotText.plural(pick.group)
            reason = "Lead \(names) from your short \(suits). It gives away no points, "
                + "and running out of \(suits) lets you trump them later."
        } else {
            reason = "Lead \(names): it gives away no points and keeps your pairs together."
        }
        return BotDecision(
            cards: pick.cards, reason: reason, concept: "Lead low",
            nudge: "Look at which of your suits is shortest and which of your cards are worth points.",
            principle: "If you can't win a trick for sure, lead a low card without points, from a short suit "
                + "if you can, and keep your pairs together.")
    }

    // MARK: Last resort

    private func lastResort() -> BotDecision {
        let costs = CostModel(table: table, mode: .dump)
        let nudge = "Look at which of your cards would give away points if you led them."
        let onlyTrumps = table.trumps.count == table.hand.count
        let trumpPrinciple = "Avoid leading point cards that can be beaten. Leading a low trump is often safer."
        if let combo = sureTrumpCombo() {
            let names = BotText.cards(combo.cards, trump)
            return BotDecision(
                cards: combo.cards,
                reason: "Nobody can beat \(names), so lead it: you win the trick and pull trumps from both opponents.",
                concept: "Sure winner",
                nudge: "Count the high trumps that are already gone.",
                principle: "Leading a trump pair nobody can beat wins the trick and makes everyone spend two trumps.")
        }
        let loose = table.trumps.filter { !table.pairFaces.contains($0.face) }
        let trumpPairs = BotPick.cheapestFirst(Combos.pairs(in: table.trumps, trump: trump), costs)
        // Never lead a point card that can be beaten while a lead without points is possible:
        // first a loose trump without points (or one nobody can beat), then a pair without points.
        let safeLoose = loose.filter { $0.points == 0 || table.isTopUnseen($0) }
        let safePairs = trumpPairs.filter { $0.points == 0 }
        if let card = BotPick.cheapest(safeLoose, 1, costs).first {
            return looseTrumpLead(card, onlyTrumps: onlyTrumps, nudge: nudge, principle: trumpPrinciple)
        }
        if let pair = safePairs.first {
            let names = BotText.cards(pair, trump)
            return BotDecision(
                cards: pair,
                reason: "Lead your pair \(names): it gives away no points, and others must spend a pair to beat it.",
                concept: "Keep pairs", nudge: nudge,
                principle: "Lead a low pair rather than splitting it. Others must then spend a pair too.")
        }
        if let card = BotPick.cheapest(loose, 1, costs).first {
            return looseTrumpLead(card, onlyTrumps: onlyTrumps, nudge: nudge, principle: trumpPrinciple)
        }
        if let pair = trumpPairs.first {
            let names = BotText.cards(pair, trump)
            return BotDecision(
                cards: pair,
                reason: "Your trumps all come in pairs, so lead your lowest pair, \(names), rather than break one up.",
                concept: "Keep pairs", nudge: nudge,
                principle: "Lead a low pair rather than splitting it. Others must then spend a pair too.")
        }
        guard let card = BotPick.cheapest(table.hand, 1, costs).first else { return BotText.waiting() }
        return BotDecision(
            cards: [card],
            reason: "Every card you hold is worth points or too good to waste, so lead \(card), "
                + "the one that risks the least.",
            concept: "Lead low", nudge: nudge,
            principle: "When every lead costs something, give up the card you will miss least.")
    }

    /// Leading one loose trump. Only an ordinary trump-suit card is called "low": jokers and
    /// trump-rank cards are among the highest trumps.
    private func looseTrumpLead(_ card: Card, onlyTrumps: Bool, nudge: String, principle: String) -> BotDecision {
        if table.isTopUnseen(card) {
            return BotDecision(
                cards: [card],
                reason: "Nobody can beat \(card), so lead it: you win the trick, and everyone who still has "
                    + "trumps must play one.",
                concept: "Sure winner",
                nudge: "Count the high trumps that are already gone.",
                principle: "Leading a trump nobody can beat wins the trick for sure, and everyone who still has "
                    + "trumps must follow with one.")
        }
        let isLow = !card.isJoker && card.rank != trump.rank
        let reason: String
        if onlyTrumps {
            reason = "You only have trumps left, so lead \(card), the one you can best spare."
        } else if isLow {
            reason = "Your other cards are worth points or too good to waste, so lead a low trump, \(card)."
        } else {
            reason = "Your other cards are worth points or too good to waste, so lead \(card), the trump you can best spare."
        }
        return BotDecision(cards: [card], reason: reason, concept: "Lead trumps", nudge: nudge, principle: principle)
    }

    /// A trump pair or tractor nobody can beat (longest first, then the lowest such).
    private func sureTrumpCombo() -> Component? {
        let mine = table.trumps
        let pieces = table.pieces(in: .trump)
        guard !pieces.pairs.isEmpty else { return nil }
        var shapes: [ComboShape] = [.pair]
        if pieces.pairs.contains(where: { table.tractorFaces.contains($0[0].face) }) {
            let run = Combos.longestRun(in: mine, trump: trump)
            if run >= 2 {
                for length in 2...run { shapes.append(.tractor(length)) }
            }
        }
        var best: Component?
        for shape in shapes {
            for component in Combos.components(of: shape, in: mine, trump: trump)
            where !table.unseenCanBeat(component) {
                if let current = best {
                    if component.cards.count < current.cards.count { continue }
                    if component.cards.count == current.cards.count && component.topStrength >= current.topStrength {
                        continue
                    }
                }
                best = component
            }
        }
        return best
    }
}

/// Final safety check for leads: legal, and a throw only if it is guaranteed against the unseen cards.
enum LeadCheck {
    static func checked(_ decision: BotDecision, _ table: BotTable) -> BotDecision {
        let cards = decision.cards
        if Rules.validateLead(cards, hand: table.hand, trump: table.trump) == nil {
            let isThrow = Rules.isThrow(cards, trump: table.trump)
            if !isThrow || Rules.checkThrow(cards, against: table.knowledge.unseen, trump: table.trump) == .ok {
                return decision
            }
        }
        BotDiagnostics.shared.noteFallback()
        let costs = CostModel(table: table, mode: .dump)
        guard let card = BotPick.cheapest(table.hand, 1, costs).first else { return BotText.waiting() }
        return BotDecision(
            cards: [card],
            reason: "Lead \(card), a card that gives little away.",
            concept: "Lead low",
            nudge: "Look at which of your cards would give away points if you led them.",
            principle: "When in doubt, lead a low card without points.")
    }
}
