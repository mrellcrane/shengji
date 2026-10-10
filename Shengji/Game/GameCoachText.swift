import Foundation
import ShengjiCore

/// Learner-facing sentences for the table: short, plain, second person.
/// Pure functions so they can be checked without the UI.
enum GameCoachText {
    // MARK: Names and grammar

    static func name(_ seat: Int) -> String { Seats.name(seat) }

    /// "You win" / "East wins".
    static func subject(_ seat: Int, _ youForm: String, _ otherForm: String) -> String {
        "\(name(seat)) \(seat == Seats.human ? youForm : otherForm)"
    }

    /// "you and Partner" / "East and West".
    static func teamName(_ team: Int, capitalized: Bool = false) -> String {
        if team == Seats.team(of: Seats.human) { return capitalized ? "You and Partner" : "you and Partner" }
        return "East and West"
    }

    /// "a 5", "an 8", "an A".
    static func article(for rank: Rank) -> String {
        (rank == .eight || rank == .ace) ? "an \(rank.label)" : "a \(rank.label)"
    }

    /// "A♠", "the big joker".
    static func cardName(_ card: Card) -> String {
        switch card.face {
        case .bigJoker: return "the big joker"
        case .smallJoker: return "the small joker"
        case .regular: return card.description
        }
    }

    /// "A♠", "a pair of 9♠", "a tractor (7♠ 7♠ 8♠ 8♠)".
    static func describePlay(_ cards: [Card], trump: Trump) -> String {
        let sorted = trump.sorted(cards)
        guard let first = sorted.first else { return "nothing" }
        if sorted.count == 1 { return cardName(first) }
        let comps = Combos.decompose(sorted, trump: trump)
        if comps.count == 1 {
            switch comps[0].shape {
            case .single:
                return cardName(first)
            case .pair:
                switch first.face {
                case .bigJoker: return "a pair of big jokers"
                case .smallJoker: return "a pair of small jokers"
                case .regular: return "a pair of \(first.description)"
                }
            case .tractor:
                return "a tractor (\(sorted.shortText))"
            }
        }
        return sorted.shortText
    }

    // MARK: Dealing and declaring

    static func dealerReason(_ game: GameState) -> String? {
        guard let last = game.history.last else { return nil }
        return last.result.outcome.declarersHold
            ? "the declarers held last round, so the dealer's partner deals"
            : "the defenders took over last round, so the next player deals"
    }

    static func dealingIntro(round: Round, game: GameState, coach: CoachLevel) -> String {
        let rank = round.trumpRank
        let show = "Trump rank is \(rank.label): show \(article(for: rank)) to pick the trump suit."
        if let dealer = round.dealer {
            let lead: String
            if let reason = dealerReason(game) {
                lead = "\(subject(dealer, "deal", "deals")) this round: \(reason)."
            } else {
                lead = "\(subject(dealer, "deal", "deals")) this round."
            }
            return "\(lead) \(show)"
        }
        if coach == .guided {
            return "Cards are dealt one at a time. Trump rank is \(rank.label): if you get \(article(for: rank)), "
                + "you can show it to make its suit trump. In the first round, whoever declares becomes the dealer."
        }
        return "Dealing. \(show)"
    }

    /// "East declares ♥ with 2♥."
    static func declarationLine(_ d: Declaration) -> String {
        sentence(d.description)
    }

    /// Title and detail for a declare button.
    static func declareButton(_ d: Declaration, current: Declaration?) -> (title: String, detail: String) {
        let strengthening = current?.player == d.player && current?.suit == d.suit && d.suit != nil
        let title: String
        if let suit = d.suit {
            title = strengthening ? "Strengthen \(suit.symbol)" : "Declare \(suit.symbol)"
        } else {
            title = "No trump"
        }
        let detail: String
        switch d.strength {
        case 1: detail = d.cards.first.map { "one \($0.description)" } ?? "one card"
        case 2: detail = d.cards.first.map { "pair of \($0.description)" } ?? "a pair"
        case 3: detail = "small jokers"
        default: detail = "big jokers"
        }
        return (title, detail)
    }

    static func declarationAccessibility(_ d: Declaration) -> String {
        let b = declareButton(d, current: nil)
        return "\(b.title) with \(b.detail)"
    }

    /// Guided/coached nudge when you first could declare. If an opponent holds the declaration,
    /// it keeps their line on screen and adds that you can beat it; if it's your partner's, it says
    /// there's no need; if it's yours, it suggests strengthening it to a pair.
    static func canDeclareNudge(_ options: [Declaration], current: Declaration?, coach: CoachLevel) -> String? {
        guard coach != .solo, let first = options.first else { return nil }
        if let current, current.player == Seats.human {
            // You already hold the declaration: the only option is turning your single into a pair.
            guard coach == .guided, let card = first.cards.first else { return "You can strengthen your declaration." }
            return "You now have a pair of \(card.description). Strengthen your declaration so it's harder to beat."
        }
        if let current, current.player == Seats.partner(of: Seats.human) {
            // Beating your partner is allowed but rarely wise: their declaration already helps your team.
            return join([declarationLine(current),
                         coach == .guided ? "That's your partner, so it helps your team too. You don't need to beat it." : nil])
        }
        if let current, current.player != Seats.human {
            return join([declarationLine(current),
                         coach == .guided ? "You can beat it: tap a Declare button below." : "You can beat it."])
        }
        guard coach == .guided else { return "You can declare now." }
        if let suit = first.suit, let card = first.cards.first {
            return "You can declare! Showing \(card.description) makes \(suit.name.lowercased()) trump. "
                + "Declare a suit you hold lots of cards in."
        }
        return "You can declare! A pair of jokers means no trump suit: only jokers and rank cards are trump."
    }

    /// Why the dealer is the dealer (said once the deal closes).
    static func dealerExplanation(round: Round, game: GameState) -> String {
        guard let dealer = round.dealer else { return "" }
        let team = Seats.team(of: dealer)
        let declarers = "\(teamName(team, capitalized: true)) are the declarers."
        if game.history.isEmpty {
            if let d = round.declaration, d.player == dealer {
                let whose = dealer == Seats.human ? "Your" : "\(name(dealer))'s"
                return "\(whose) declaration won, so \(dealer == Seats.human ? "you deal" : "\(name(dealer)) deals"). \(declarers)"
            }
            var text = "Nobody declared, so \(dealer == Seats.human ? "you deal" : "\(name(dealer)) deals") this first round."
            if let kitty = kittyTrumpLine(round: round) { text += " " + kitty }
            return "\(text) \(declarers)"
        }
        var text: String
        if let reason = dealerReason(game) {
            text = "\(subject(dealer, "deal", "deals")): \(reason)."
        } else {
            text = "\(subject(dealer, "deal", "deals")) this round."
        }
        if round.declaration == nil, let kitty = kittyTrumpLine(round: round) { text += " " + kitty }
        return "\(text) \(declarers)"
    }

    /// "East picks up the kitty and buries 8 cards." / "You pick up the kitty and bury 8 cards."
    static func kittyPickupLine(dealer: Int?) -> String {
        guard let dealer else { return "The dealer picks up the kitty and buries \(Round.kittySize) cards." }
        let bury = dealer == Seats.human ? "bury" : "buries"
        return "\(subject(dealer, "pick", "picks")) up the kitty and \(bury) \(Round.kittySize) cards."
    }

    /// A shorter reason used in your bury prompt (the prompt itself says you're the dealer).
    static func shortDealerReason(round: Round, game: GameState) -> String? {
        guard round.dealer != nil else { return nil }
        let kitty = kittyTrumpLine(round: round)
        if game.history.isEmpty {
            if let d = round.declaration, d.player == round.dealer { return "Your declaration won." }
            return join(["Nobody declared, so you deal.", kitty])
        }
        guard let last = game.history.last else { return kitty }
        let reason = last.result.outcome.declarersHold
            ? "Your team held the deal, so the dealer's partner deals."
            : "Your team took over the deal."
        return join([reason, kitty])
    }

    /// How the kitty fixed trump when nobody declared.
    static func kittyTrumpLine(round: Round) -> String? {
        guard round.declaration == nil, let card = round.trumpFromKitty else { return nil }
        if card.isJoker { return "A joker turned up in the kitty, so there is no trump suit." }
        guard let suit = card.suit else { return nil }
        if card.rank == round.trumpRank {
            return "The kitty was turned over: the first \(round.trumpRank.label) was \(card.description), so \(suit.name.lowercased()) are trump."
        }
        return "The kitty had no \(round.trumpRank.label), so its highest card, \(card.description), makes \(suit.name.lowercased()) trump."
    }

    // MARK: Playing

    static func throwFailedLine(player: Int, forced: [Card], blocker: Int, trump: Trump) -> String {
        let played = describePlay(forced, trump: trump)
        if player == Seats.human {
            return "Your throw failed: \(name(blocker)) could beat part of it, so only \(played) was played."
        }
        return "\(name(player))'s throw failed: \(blocker == Seats.human ? "you" : name(blocker)) could beat part of it, so only \(played) was played."
    }

    /// Concept tag for an illegal move.
    static func concept(for error: RoundError) -> String? {
        switch error {
        case let .illegalFollow(violation):
            switch violation {
            case .mustFollowSuit: return "Follow suit"
            case .mustPlayPairs: return "Follow a pair"
            case .mustPlayTractor: return "Follow a tractor"
            case .wrongCount: return "Card count"
            case .cardsNotInHand: return nil
            }
        case let .illegalLead(violation):
            switch violation {
            case .mixedSuits: return "One suit per lead"
            case .empty, .cardsNotInHand: return nil
            }
        case .invalidDeclaration: return "Declaring"
        case .invalidBury: return "The kitty"
        case .wrongPhase, .notYourTurn: return nil
        }
    }

    /// The practice skill an illegal play points at (it becomes due for review).
    static func mistakeSkill(for error: RoundError, lead: [Card]) -> SkillID? {
        guard case let .illegalFollow(violation) = error else { return nil }
        switch violation {
        case .mustFollowSuit: return lead.count == 1 ? .cardBeats : .legalFollow
        case .mustPlayPairs, .mustPlayTractor: return .legalFollow
        case .wrongCount, .cardsNotInHand: return nil
        }
    }

    static func pointsLine(points: Int, winnerIsDefender: Bool) -> String? {
        guard points > 0 else { return nil }
        return winnerIsDefender ? "Defenders +\(points)." : "The \(points) points stay with the declarers."
    }

    /// The one-line explanation shown after a trick.
    ///  - guided (or `detailed`): why it was won, plus points;
    ///  - coached: who won, plus points;
    ///  - solo: nothing.
    static func trickExplanation(_ trick: TrickRecord, trump: Trump, coach: CoachLevel, detailed: Bool = false,
                                 winnerIsDefender: Bool, isLastTrick: Bool) -> (text: String, concept: String?)? {
        let full = detailed || coach == .guided
        if !full && coach == .solo { return nil }
        var concept: String?
        var parts: [String] = []
        if full {
            let why = whyWon(trick, trump: trump)
            parts.append(why.text)
            concept = why.concept
        } else {
            parts.append("\(subject(trick.winner, "win", "wins")) the trick.")
        }
        if let pts = pointsLine(points: trick.points, winnerIsDefender: winnerIsDefender) { parts.append(pts) }
        if isLastTrick {
            parts.append(winnerIsDefender
                         ? "Defenders won the last trick, so the kitty counts for them too."
                         : "Declarers won the last trick, so the kitty is safe.")
            concept = concept ?? "The kitty"
        }
        return (parts.joined(separator: " "), concept)
    }

    /// "Partner wins with A♠, the highest spade." / "East ruffs with 3♥, a trump."
    static func whyWon(_ trick: TrickRecord, trump: Trump) -> (text: String, concept: String?) {
        let winnerSeat = trick.winner
        guard let lead = trick.plays.first, let leadCard = lead.cards.first,
              let win = trick.plays.first(where: { $0.player == winnerSeat }), !win.cards.isEmpty else {
            return ("\(subject(winnerSeat, "win", "wins")) the trick.", nil)
        }
        let leadGroup = trump.group(leadCard)
        let winGroup = Combos.group(of: win.cards, trump: trump)
        let what = describePlay(win.cards, trump: trump)

        // Ruff: a plain suit was led and the winner played only trumps.
        if win.player != lead.player, winGroup == .trump, !leadGroup.isTrump {
            let otherRuffs = trick.plays.filter {
                $0.player != win.player && $0.player != lead.player
                    && Combos.group(of: $0.cards, trump: trump) == .trump
            }
            if otherRuffs.isEmpty {
                let trumpWord = win.cards.count == 1 ? "a trump" : win.cards.count == 2 ? "both trumps" : "all trumps"
                return ("\(subject(winnerSeat, "ruff", "ruffs")) with \(what), \(trumpWord).", "Ruff")
            }
            return ("\(subject(winnerSeat, "ruff", "ruffs")) with \(what), the highest trump played.", "Overruff")
        }

        // Tie: a later play of the same shape and strength loses to the earlier one. Plays are compared
        // on their biggest part, as the engine does (a throw's pair decides it, not its top single).
        let winKey = keyStrength(win.cards, trump: trump)
        let winShape = shapes(win.cards, trump: trump)
        if let tied = trick.plays.first(where: { p in
            p.player != win.player
                && Combos.group(of: p.cards, trump: trump) == winGroup
                && shapes(p.cards, trump: trump) == winShape
                && keyStrength(p.cards, trump: trump) == winKey
        }) {
            let tiedName = tied.player == Seats.human ? "You" : name(tied.player)
            return ("\(subject(winnerSeat, "win", "wins")) with \(what). \(tiedName) played an equal card, "
                    + "and a tie goes to whoever played first.", "Ties")
        }

        let groupWord = leadGroup.plainSuit?.singularName ?? "trump"
        let leadComps = Combos.decompose(lead.cards, trump: trump)
        if leadComps.count > 1 {
            if win.player == lead.player {
                return ("\(subject(winnerSeat, "win", "wins")) with the throw: nobody could beat it.", "Throws")
            }
            return ("\(subject(winnerSeat, "win", "wins")) with \(what).", nil)
        }
        let shapeWord: String
        let concept: String?
        switch leadComps.first?.shape ?? .single {
        case .single:
            shapeWord = ""
            concept = leadGroup.isTrump ? "Trump order" : "Highest card"
        case .pair:
            shapeWord = " pair"
            concept = "Pairs"
        case .tractor:
            shapeWord = " tractor"
            concept = "Tractors"
        }
        if win.player == lead.player, lead.cards.count > 1 {
            let matched = trick.plays.dropFirst().contains { p in
                shapes(p.cards, trump: trump) == winShape
                    && (Combos.group(of: p.cards, trump: trump) == leadGroup
                        || Combos.group(of: p.cards, trump: trump) == .trump)
            }
            if !matched {
                return ("\(subject(winnerSeat, "win", "wins")) with \(what): nobody could match it with a higher \(groupWord)\(shapeWord).", concept)
            }
        }
        // "played": the winning card is the best in this trick, not necessarily the best in the deck.
        return ("\(subject(winnerSeat, "win", "wins")) with \(what), the highest \(groupWord)\(shapeWord) played.", concept)
    }

    static func topStrength(_ cards: [Card], trump: Trump) -> Int {
        cards.map { trump.strength($0) }.max() ?? -1
    }

    /// Strength of the top card in the play's biggest part (its highest tractor, pair or single).
    static func keyStrength(_ cards: [Card], trump: Trump) -> Int {
        Combos.decompose(cards, trump: trump).first?.topStrength ?? -1
    }

    /// Multiset of component shapes, largest first, e.g. [pair, single].
    static func shapes(_ cards: [Card], trump: Trump) -> [ComboShape] {
        Combos.decompose(cards, trump: trump).map(\.shape)
    }

    /// How worthwhile a trick is for a "who wins?" prompt: ruffs, pairs and close calls score higher.
    static func predictionInterest(_ trick: TrickRecord, trump: Trump) -> Int {
        guard let lead = trick.plays.first, let leadCard = lead.cards.first else { return 0 }
        let leadGroup = trump.group(leadCard)
        var score = 0
        if !leadGroup.isTrump, trick.plays.dropFirst().contains(where: { p in
            !p.cards.isEmpty && p.cards.allSatisfy { trump.isTrump($0) }
        }) {
            score += 2
        }
        if lead.cards.count >= 2 { score += 2 }
        let tops = trick.plays.compactMap { p -> Int? in
            guard let g = Combos.group(of: p.cards, trump: trump), g == leadGroup else { return nil }
            return topStrength(p.cards, trump: trump)
        }.sorted(by: >)
        if tops.count >= 2, tops[0] - tops[1] <= 1 { score += 1 }
        return score
    }

    // MARK: Round result

    /// "Defenders won the last trick with a pair: kitty 15 x 4 = 60"
    static func kittyLine(_ result: RoundResult) -> String {
        if result.kittyMultiplier <= 0 {
            if result.kittyPoints == 0 { return "Declarers won the last trick. The kitty had no points anyway." }
            return "Declarers won the last trick, so the kitty's \(result.kittyPoints) points don't count."
        }
        let shape: String
        switch result.kittyMultiplier / 2 {
        case 1: shape = "a single"
        case 2: shape = "a pair"
        case 4: shape = "a tractor"
        default: shape = "a long tractor"
        }
        if result.kittyPoints == 0 {
            return "Defenders won the last trick with \(shape), but the kitty had no points."
        }
        let bonus = result.kittyPoints * result.kittyMultiplier
        return "Defenders won the last trick with \(shape): kitty \(result.kittyPoints) x \(result.kittyMultiplier) = \(bonus)"
    }

    /// One takeaway sentence for the results screen.
    static func takeaway(_ summary: RoundSummary) -> String {
        let result = summary.result
        let humanTeam = Seats.team(of: Seats.human)
        let humanDeclares = result.declarerTeam == humanTeam
        if result.kittyMultiplier > 0 && result.kittyPoints > 0 {
            return humanDeclares
                ? "Tip: as declarers, keep point cards out of the kitty. If the defenders win the last trick, those points get multiplied."
                : "Tip: winning the last trick as defenders multiplies the kitty. Save a strong pair for the end."
        }
        if humanDeclares {
            if result.defenderPoints >= Scoring.takeoverThreshold {
                return "Tip: as declarers, draw out trumps early so the defenders can't ruff your winners."
            }
            return "Tip: nice holding! Play your sure winners before the defenders run you out of a suit."
        }
        if result.defenderPoints >= Scoring.takeoverThreshold {
            return "Tip: you took over the deal. Next round your team's level sets the trump rank."
        }
        return "Tip: as a defender, give 5s, 10s and Kings to your partner when they are winning a trick."
    }

    // MARK: Helpers

    /// Adds a full stop unless the text already ends with punctuation.
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        return ".!?".contains(last) ? trimmed : trimmed + "."
    }

    static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
