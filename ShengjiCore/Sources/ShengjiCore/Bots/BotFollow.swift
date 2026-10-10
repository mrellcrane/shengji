import Foundation

/// Reads a trick in progress once and answers "would this play take the lead?" with exactly the
/// rules of `Rules.winningIndex`, without rebuilding the lead's format for every candidate.
struct TrickJudge {
    let trump: Trump
    let format: Rules.LeadFormat
    let ledGroup: SuitGroup
    /// True when the lead has more than one component (a throw that stood).
    let isThrowLead: Bool
    /// Index into the trick of the play winning so far.
    let winnerIndex: Int
    private let bestIsTrump: Bool
    private let bestKey: Int

    init(trick: [Play], trump: Trump) {
        self.trump = trump
        let lead = trick.first?.cards ?? []
        let format = Rules.LeadFormat(lead, trump: trump)
        self.format = format
        self.isThrowLead = Rules.isThrow(lead, trump: trump)
        let group = Combos.group(of: lead, trump: trump) ?? lead.first.map { trump.group($0) } ?? .trump
        self.ledGroup = group
        var index = 0
        var isTrump = group.isTrump
        var key = Rules.structureKey(lead, format: format, trump: trump) ?? format.largest?.topStrength ?? 0
        for position in trick.indices.dropFirst() {
            guard let challenger = TrickJudge.challenge(trick[position].cards, ledGroup: group, format: format,
                                                        trump: trump) else { continue }
            if challenger.isTrump && !isTrump {
                index = position
                isTrump = true
                key = challenger.key
            } else if challenger.isTrump == isTrump && challenger.key > key {
                index = position
                key = challenger.key
            }
        }
        self.winnerIndex = index
        self.bestIsTrump = isTrump
        self.bestKey = key
    }

    /// True if `cards`, played next, would be winning the trick.
    func wins(_ cards: [Card]) -> Bool {
        guard let challenger = TrickJudge.challenge(cards, ledGroup: ledGroup, format: format, trump: trump) else {
            return false
        }
        if challenger.isTrump && !bestIsTrump { return true }
        return challenger.isTrump == bestIsTrump && challenger.key > bestKey
    }

    /// The play's comparison key if it can compete at all (all led group or all trump, same structure).
    func key(of cards: [Card]) -> Int? {
        TrickJudge.challenge(cards, ledGroup: ledGroup, format: format, trump: trump)?.key
    }

    private static func challenge(_ cards: [Card], ledGroup: SuitGroup, format: Rules.LeadFormat,
                                  trump: Trump) -> (isTrump: Bool, key: Int)? {
        guard let group = Combos.group(of: cards, trump: trump), group == ledGroup || group.isTrump,
              let key = Rules.structureKey(cards, format: format, trump: trump) else { return nil }
        return (group.isTrump, key)
    }
}

/// Standard-level following (DESIGN.md §Bot strategy). Every play is built by `FollowBuilder`
/// (owed structure first, then filler chosen by cost) and checked with `Rules.validateFollow`.
///  - Partner winning safely (this seat is last, or nobody after can beat them): feed points.
///  - Partner winning but beatable: overtake with a sure winner if points are at risk, else duck low.
///  - Opponent winning: win cheaply when it is worth it, ruff when out of the suit and points are
///    at stake (high enough when a later opponent may overruff), otherwise duck low.
struct StandardFollow {
    let table: BotTable
    private let builder: FollowBuilder
    private let judge: TrickJudge
    private let trick: [Play]
    private let lead: [Card]
    private let count: Int
    private let leadShape: ComboShape
    private let winner: Int
    private let winningCards: [Card]
    private let onTable: Int
    private let laterOpponents: [Int]
    private let partnerLater: Bool
    private let isLast: Bool

    init(table: BotTable) {
        self.table = table
        let trick = table.round.currentTrick
        let lead = table.round.currentLead
        self.trick = trick
        self.lead = lead
        self.count = lead.count
        self.builder = FollowBuilder(hand: table.hand, lead: lead, trump: table.trump)
        let judge = TrickJudge(trick: trick, trump: table.trump)
        self.judge = judge
        self.leadShape = judge.format.largest?.shape ?? .single
        let index = judge.winnerIndex
        let winning: Play? = trick.indices.contains(index) ? trick[index] : trick.first
        self.winner = winning?.player ?? table.round.leader
        self.winningCards = winning?.cards ?? lead
        var points = 0
        for play in trick { points += play.cards.points }
        self.onTable = points
        let position = trick.count
        var later: [Int] = []
        if position < 3 {
            for step in 1...(3 - position) { later.append((table.seat + step) % 4) }
        }
        self.laterOpponents = later.filter { table.isOpponent($0) }
        self.partnerLater = later.contains(table.partner)
        self.isLast = position >= 3
    }

    private var trump: Trump { table.trump }
    private var ledGroup: SuitGroup { builder.ledGroup }
    private var seat: Int { table.seat }

    func decide() -> BotDecision {
        let decision = winner == table.partner ? partnerWinning() : opponentWinning()
        if builder.isLegal(decision.cards) { return decision }
        BotDiagnostics.shared.noteFallback()
        let cards = builder.fallback()
        return BotDecision(
            cards: cards,
            reason: "Play \(BotText.cards(cards, trump)) to follow the rules for this lead.",
            concept: "Follow suit",
            nudge: "Look at what was led and which of those cards you still hold.",
            principle: "Follow the suit and shape of the lead as far as your cards allow.")
    }

    // MARK: Trick reading

    private func wouldWin(_ play: [Card]) -> Bool { judge.wins(play) }

    /// True if, as far as this seat can tell, no opponent still to play can beat `play`.
    private func holds(_ play: [Card]) -> Bool {
        guard !laterOpponents.isEmpty else { return true }
        guard let group = Combos.group(of: play, trump: trump), let key = judge.key(of: play) else { return false }
        // A throw that stood can't be beaten in its own suit (nobody held a higher part), only trumped.
        let standingThrow = judge.isThrowLead && play == lead
        let higherOut = !standingThrow && table.unseenCanBeat(leadShape, group: group, strength: key)
        let ruffThreat = laterOpponents.contains(where: { table.mayRuff($0, ledGroup) })
            || table.isRunningOut(ledGroup, count: count, players: laterOpponents.count)
        if group.isTrump && !ledGroup.isTrump {
            // A ruff: only an opponent who is also out of the led suit can trump over it.
            return !(ruffThreat && higherOut)
        }
        if higherOut { return false }
        return group.isTrump || !ruffThreat
    }

    private struct Candidate {
        let cards: [Card]
        /// Value of the cards given up (points ignored).
        let cost: Int
        let sure: Bool
        let key: Int
    }

    /// Plays that would win the trick right now, cheapest first (point cards count as cheap: they come back).
    private func winningPlays() -> [Candidate] {
        let win = CostModel(table: table, mode: .win)
        let plays: [[Card]] = builder.held.isEmpty ? builder.ruffs(win) : builder.inSuitShapes()
        let keep = CostModel(table: table, mode: .keep)
        var scored: [(candidate: Candidate, order: Int, tiebreak: Int)] = []
        for play in plays where wouldWin(play) {
            let key = judge.key(of: play) ?? 0
            let candidate = Candidate(cards: play, cost: keep.cost(of: play), sure: holds(play), key: key)
            var tiebreak = 0
            if let first = table.order.sorted(play).first {
                let orderKey: Int = table.order.key(first)
                tiebreak = orderKey * 200 + first.id
            }
            scored.append((candidate, win.cost(of: play), tiebreak))
        }
        scored.sort { a, b in
            if a.order != b.order { return a.order < b.order }
            if a.candidate.key != b.candidate.key { return a.candidate.key < b.candidate.key }
            return a.tiebreak < b.tiebreak
        }
        return scored.map { $0.candidate }
    }

    /// Defenders chase points; declarers fight hardest for points late in the round.
    private func worthContesting(_ stake: Int) -> Bool {
        let tuning = table.tuning
        if table.isDeclarer {
            return stake >= tuning.declarerContestStake || (table.isLate && stake >= tuning.defenderContestStake)
        }
        return stake >= tuning.defenderContestStake
    }

    private func worthRuffing(_ stake: Int) -> Bool {
        let tuning = table.tuning
        if table.isDeclarer {
            return stake >= tuning.declarerRuffStake || (table.isLate && stake >= tuning.defenderRuffStake)
        }
        return stake >= tuning.defenderRuffStake
    }

    // MARK: Partner winning

    private func partnerWinning() -> BotDecision {
        if isLast || holds(winningCards) { return feed() }
        let dump = builder.build(CostModel(table: table, mode: .guarded))
        // Points at risk: the trick so far plus any points this seat would have to throw in.
        let stake = onTable + dump.points
        if stake >= 10, let sure = winningPlays().first(where: { $0.sure }) {
            let extra = sure.cost - CostModel(table: table, mode: .keep).cost(of: dump)
            if extra <= 20 + 4 * stake { return overtake(sure, stake: stake) }
        }
        return duckForPartner(dump)
    }

    private func feed() -> BotDecision {
        let play = builder.build(CostModel(table: table, mode: .feed))
        let names = BotText.cards(play, trump)
        let partnerCards = "your partner's \(BotText.cards(winningCards, trump))"
        let why = isLast ? "You play last and \(partnerCards) is winning" : "Nobody after you can beat \(partnerCards)"
        let nudge = "Look at who is winning this trick and whether anyone after you can still beat it."
        let principle = "When your partner is sure to win the trick, give them your point cards: fives, tens and kings."
        if play.points > 0 && wouldWin(play) {
            return BotDecision(
                cards: play,
                reason: "\(why), so add \(names) for \(BotText.points(play.points)). Your side takes the trick either way.",
                concept: "Feed points", nudge: nudge, principle: principle)
        }
        if play.points > 0 {
            return BotDecision(
                cards: play, reason: "\(why), so give them \(names) for \(BotText.points(play.points)).",
                concept: "Feed points", nudge: nudge, principle: principle)
        }
        return BotDecision(
            cards: play, reason: "\(why), but you have no points to spare, so play \(names) and keep your better cards.",
            concept: "Duck low", nudge: nudge,
            principle: "When your partner is sure to win, add points if you can. If you can't, play your cheapest cards.")
    }

    private func overtake(_ candidate: Candidate, stake: Int) -> BotDecision {
        let names = BotText.cards(candidate.cards, trump)
        let theirs = BotText.cards(winningCards, trump)
        let safe = max(stake, onTable + candidate.cards.points)
        return BotDecision(
            cards: candidate.cards,
            reason: "Your partner's \(theirs) could still be beaten, so take the trick yourself with \(names), "
                + "which nobody can beat, and keep \(BotText.points(safe)) safe.",
            concept: "Sure winner",
            nudge: "Look at who is winning, who still plays after you, and how many points are at risk.",
            principle: "When points are at risk, win the trick yourself with a card nobody can beat.")
    }

    private func duckForPartner(_ play: [Card]) -> BotDecision {
        let names = BotText.cards(play, trump)
        let threat = BotText.list(laterOpponents.map { BotText.name($0, from: seat) })
        let opening = "Your partner is winning for now, but \(threat) plays after you and could still beat it"
        let reason: String
        if wouldWin(play) {
            reason = opening + ", so play \(names). It costs you the least and keeps the trick on your side for now."
        } else if play.points > 0 {
            reason = opening + ", and \(names) is your cheapest choice."
        } else {
            reason = opening + ", so play \(names) and keep your points."
        }
        return BotDecision(
            cards: play, reason: reason, concept: "Duck low",
            nudge: "Look at who is winning and who still has to play after you.",
            principle: "Only give your partner points when nobody after you can beat them.")
    }

    // MARK: Opponent winning

    private func opponentWinning() -> BotDecision {
        let dump = builder.build(CostModel(table: table, mode: .dump))
        let keep = CostModel(table: table, mode: .keep)
        let dumpCost = keep.cost(of: dump)
        let candidates = winningPlays()
        let stake = onTable + dump.points

        if builder.held.isEmpty && !ledGroup.isTrump {
            if let ruff = chooseRuff(candidates, stake: stake, dumpCost: dumpCost) { return ruffDecision(ruff) }
            return dumpDecision(dump, canWin: !candidates.isEmpty)
        }
        if isLast {
            if let best = candidates.first {
                let extra = best.cost - dumpCost
                let limit = stake > 0 ? 10 + 4 * stake : 10
                if extra <= limit { return winCheaply(best) }
            }
            return dumpDecision(dump, canWin: !candidates.isEmpty)
        }
        if let sure = candidates.first(where: { $0.sure }) {
            let extra = sure.cost - dumpCost
            var limit = stake > 0 ? 20 + 4 * stake : 10
            if partnerLater { limit += 20 }
            if extra <= limit { return sureWin(sure) }
        }
        if worthContesting(stake), let best = candidates.first(where: { $0.cards.points == 0 }) {
            if best.cost - dumpCost <= 10 + 2 * stake { return contest(best, stake: stake) }
        }
        return dumpDecision(dump, canWin: !candidates.isEmpty)
    }

    private func chooseRuff(_ candidates: [Candidate], stake: Int, dumpCost: Int) -> Candidate? {
        guard let cheapest = candidates.first, worthRuffing(stake) else { return nil }
        let affordable = cheapest.cost - dumpCost <= 20 + 4 * stake
        let threatened = !isLast && (laterOpponents.contains(where: { table.mayRuff($0, ledGroup) })
            || table.isRunningOut(ledGroup, count: count, players: laterOpponents.count))
        if !threatened { return affordable ? cheapest : nil }
        if let sure = candidates.first(where: { $0.sure }), sure.cost - dumpCost <= 40 + 4 * stake { return sure }
        let high = candidates.first(where: { $0.key >= Trump.topPlainStrength - 1 })
        if let high = high, high.cost - dumpCost <= 30 + 4 * stake { return high }
        return stake >= 15 && affordable ? cheapest : nil
    }

    private func winCheaply(_ candidate: Candidate) -> BotDecision {
        let names = BotText.cards(candidate.cards, trump)
        let total = onTable + candidate.cards.points
        let reason = total > 0
            ? "You play last, so \(names) is enough to beat \(winnerPhrase) and take \(BotText.points(total))."
            : "You play last, so \(names) wins this trick cheaply and gives you the lead."
        return BotDecision(
            cards: candidate.cards, reason: reason, concept: "Win cheaply",
            nudge: "You play last. Look at what is winning and what you hold in \(BotText.plural(ledGroup)).",
            principle: "When you play last, win with the smallest card that does the job, especially when there are points.")
    }

    private func sureWin(_ candidate: Candidate) -> BotDecision {
        let names = BotText.cards(candidate.cards, trump)
        let total = onTable + candidate.cards.points
        let opening = candidate.cards.count == 1
            ? "\(names) is the highest \(BotText.singular(ledGroup)) still out, so it wins this trick for sure"
            : "Nobody can beat \(names), so it wins this trick for sure"
        let ending: String
        if total > 0 {
            ending = " and takes \(BotText.points(total))."
        } else if partnerLater {
            ending = ", and your partner can add points after you."
        } else {
            ending = "."
        }
        return BotDecision(
            cards: candidate.cards, reason: opening + ending, concept: "Sure winner",
            nudge: "Look at what is still out in \(BotText.plural(ledGroup)) and who plays after you.",
            principle: "Win with a card nobody can beat when there are points to take or your partner can add more.")
    }

    private func contest(_ candidate: Candidate, stake: Int) -> BotDecision {
        let names = BotText.cards(candidate.cards, trump)
        let principle = table.isDeclarer
            ? "As a declarer, don't let the defenders collect tricks full of points."
            : "As a defender, fight for tricks that hold points."
        return BotDecision(
            cards: candidate.cards,
            reason: "This trick holds \(BotText.points(stake)), so try to win it with \(names), which beats \(winnerPhrase).",
            concept: table.isDeclarer ? "Protect points" : "Chase points",
            nudge: "Count the points in this trick and see whether you can beat the card that is winning.",
            principle: principle)
    }

    private func ruffDecision(_ candidate: Candidate) -> BotDecision {
        let names = BotText.cards(candidate.cards, trump)
        let total = onTable + candidate.cards.points
        let prize = total > 0 ? "take \(BotText.points(total))" : "take this trick"
        let suits = BotText.plural(ledGroup)
        let overruff = Combos.group(of: winningCards, trump: trump)?.isTrump == true
        var reason: String
        if overruff {
            let who = BotText.capitalized(BotText.name(winner, from: seat))
            reason = "\(who) trumped with \(BotText.cards(winningCards, trump)), so beat it with \(names) and \(prize)."
        } else {
            reason = "You're out of \(suits), so trump with \(names) and \(prize)."
        }
        let threats = laterOpponents.filter { table.mayRuff($0, ledGroup) }
        if !isLast, !threats.isEmpty, candidate.key >= Trump.topPlainStrength - 1 {
            let threatNames = BotText.list(threats.map { BotText.name($0, from: seat) })
            reason += " Trump high, because \(threatNames) is out of \(suits) too and could trump over a low one."
        }
        return BotDecision(
            cards: candidate.cards, reason: reason, concept: overruff ? "Overruff" : "Ruff",
            nudge: "You have no \(suits) left. Look at how many points are in this trick.",
            principle: overruff
                ? "If an opponent trumps a trick with points, beat their trump with a higher one if you can."
                : "When you are out of the suit led and the trick holds points, win it with a trump.")
    }

    private var winnerPhrase: String {
        "\(BotText.possessive(winner, from: seat)) \(BotText.cards(winningCards, trump))"
    }

    private func dumpDecision(_ play: [Card], canWin: Bool) -> BotDecision {
        let names = BotText.cards(play, trump)
        let suits = BotText.plural(ledGroup)
        let total = onTable + play.points
        if table.hand.count == count {
            return BotDecision(
                cards: play, reason: "This is the last trick, so play your remaining cards: \(names).",
                concept: "Last trick",
                nudge: "Count how many cards you have left.",
                principle: "On the last trick everyone plays all their remaining cards.")
        }
        let followNudge = "Look at which \(suits) you still hold."
        let followPrinciple = "You must follow the suit that was led for as long as you have it."
        if builder.held.count == count {
            let verb = play.count == 1 ? "is" : "are"
            let note = wouldWin(play) ? " It beats \(winnerPhrase) for now." : ""
            return BotDecision(
                cards: play, reason: "You must follow \(suits), and \(names) \(verb) all you have left.\(note)",
                concept: "Follow suit", nudge: followNudge, principle: followPrinciple)
        }
        if wouldWin(play) && isLast {
            let prize = total > 0 ? " and its \(BotText.points(total))." : "."
            return BotDecision(
                cards: play, reason: "\(names) is enough to win this trick\(prize)", concept: "Win cheaply",
                nudge: "Look at what is winning this trick and what you hold.",
                principle: "When you play last, win with the smallest card that does the job.")
        }
        if wouldWin(play) {
            return BotDecision(
                cards: play,
                reason: "Play \(names): it is the choice you will miss least, and it beats \(winnerPhrase) for now.",
                concept: "Duck low",
                nudge: "Look at what is winning this trick and who still plays after you.",
                principle: "When a trick isn't worth a fight, play the cards you will miss least.")
        }
        if builder.held.isEmpty {
            let excuse = canWin ? " and this trick isn't worth a trump" : ""
            let ending = play.points > 0 ? ", your cheapest choice." : " and give away no points."
            return BotDecision(
                cards: play, reason: "You're out of \(suits)\(excuse), so throw away \(names)\(ending)",
                concept: "Discard low",
                nudge: "You have no \(suits). Look at how many points are in this trick.",
                principle: "When you can't or shouldn't win, throw away low cards from a suit you don't need, "
                    + "and keep your trumps.")
        }
        if builder.held.count < count {
            return BotDecision(
                cards: play,
                reason: "You have too few \(suits) to compete, so play \(names): all your \(suits) "
                    + "plus your cheapest other cards.",
                concept: "Follow suit", nudge: followNudge,
                principle: "If you have too few cards of the suit led, play them all and fill up with your cheapest cards.")
        }
        let reason: String
        if canWin && partnerLater {
            reason = "Your partner still plays after you, so play \(names), the cards you will miss least, "
                + "and save your strength."
        } else if canWin {
            reason = "Beating \(winnerPhrase) would cost more than this trick is worth, so play \(names) "
                + "and save your strength."
        } else if play.points > 0 {
            reason = "You can't beat \(winnerPhrase) and must follow \(suits), so \(names) is your cheapest choice."
        } else {
            reason = "You can't beat \(winnerPhrase), so play \(names) and keep your points and high cards."
        }
        return BotDecision(
            cards: play, reason: reason, concept: "Duck low",
            nudge: "Look at who is winning this trick and whether you can beat it.",
            principle: "When you can't win a trick, play your lowest cards without points, and keep your pairs "
                + "and high cards.")
    }
}
