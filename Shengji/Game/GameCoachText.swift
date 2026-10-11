import Foundation
import ShengjiCore

/// Learner-facing sentences for the table: short, plain, second person.
/// Pure functions so they can be checked without the UI. `players` is the table size (4, 6 or 8):
/// seats are named "East", "Partner", "West" with 4 and by compass point with more.
enum GameCoachText {
    // MARK: Names and grammar

    static func name(_ seat: Int, players: Int = 4) -> String { Seats.name(seat, players: players) }

    /// "You win" / "East wins".
    static func subject(_ seat: Int, _ youForm: String, _ otherForm: String, players: Int = 4) -> String {
        "\(name(seat, players: players)) \(seat == Seats.human ? youForm : otherForm)"
    }

    /// "you and Partner" / "East and West" (with 6 or 8 players: "your team" / "the other team").
    static func teamName(_ team: Int, capitalized: Bool = false, players: Int = 4) -> String {
        let yours = team == Seats.team(of: Seats.human)
        if players > 4 {
            let text = yours ? "your team" : "the other team"
            return capitalized ? text.prefix(1).uppercased() + text.dropFirst() : text
        }
        if yours { return capitalized ? "You and Partner" : "you and Partner" }
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
            case let .set(width):
                let count = width == 3 ? "three" : width == 4 ? "four" : String(width)
                switch first.face {
                case .bigJoker: return "\(count) big jokers"
                case .smallJoker: return "\(count) small jokers"
                case .regular: return "\(count) \(first.description)"
                }
            case .setTractor:
                return "a \(comps[0].shape.name) (\(sorted.shortText))"
            }
        }
        return sorted.shortText
    }

    // MARK: Dealing and declaring

    static func dealerReason(_ game: GameState) -> String? {
        guard let last = game.history.last else { return nil }
        if game.findsFriends {
            return last.result.outcome.declarersHold
                ? "the dealer's side held last round, so its next player deals"
                : "the defenders took over last round, so the first defender after the dealer deals"
        }
        let partner = game.players > 4 ? "the dealer's next partner" : "the dealer's partner"
        return last.result.outcome.declarersHold
            ? "the declarers held last round, so \(partner) deals"
            : "the defenders took over last round, so the next player deals"
    }

    static func dealingIntro(round: Round, game: GameState, coach: CoachLevel) -> String {
        let rank = round.trumpRank
        let players = round.players
        let show = "Trump rank is \(rank.label): show \(article(for: rank)) to pick the trump suit."
        if let dealer = round.dealer {
            let lead: String
            if let reason = dealerReason(game) {
                lead = "\(subject(dealer, "deal", "deals", players: players)) this round: \(reason)."
            } else {
                lead = "\(subject(dealer, "deal", "deals", players: players)) this round."
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
    static func declarationLine(_ d: Declaration, players: Int = 4) -> String {
        sentence(d.description(players: players))
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
        case 4: detail = "big jokers"
        default:
            // Three or more decks: three or four of a card.
            let count = d.cardCount == 3 ? "three" : "\(d.cardCount)"
            switch d.kind {
            case .rankCards: detail = d.cards.first.map { "\(count) \($0.description)" } ?? "\(count) cards"
            case .smallJokers: detail = "\(count) small jokers"
            case .bigJokers: detail = "\(count) big jokers"
            }
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
    static func canDeclareNudge(_ options: [Declaration], current: Declaration?, coach: CoachLevel,
                                players: Int = 4) -> String? {
        guard coach != .solo, let first = options.first else { return nil }
        if let current, current.player == Seats.human {
            // You already hold the declaration: the only option is more of the same card (a single becomes a pair).
            guard coach == .guided, let card = first.cards.first else { return "You can strengthen your declaration." }
            let count = first.cardCount == 3 ? "three" : "\(first.cardCount)"
            let shown = first.cardCount == 2 ? "a pair of \(card.description)" : "\(count) \(card.description)"
            return "You now have \(shown). Strengthen your declaration so it's harder to beat."
        }
        if let current, current.player != Seats.human, players % 2 == 0,
           Seats.team(of: current.player) == Seats.team(of: Seats.human) {
            // Beating your partner is allowed but rarely wise: their declaration already helps your team.
            return join([declarationLine(current, players: players),
                         coach == .guided ? "That's your partner, so it helps your team too. You don't need to beat it." : nil])
        }
        if let current, current.player != Seats.human {
            return join([declarationLine(current, players: players),
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
        let players = round.players
        let team = Seats.team(of: dealer)
        let teamText = teamName(team, capitalized: true, players: players)
        let declarers = round.isFindingFriends
            ? friendsToCallLine(dealer: dealer, count: round.table.friendCount, players: players)
            : "\(teamText) are the declarers."
        let dealerName = name(dealer, players: players)
        if game.history.isEmpty {
            if let d = round.declaration, d.player == dealer {
                let whose = dealer == Seats.human ? "Your" : "\(dealerName)'s"
                return "\(whose) declaration won, so \(dealer == Seats.human ? "you deal" : "\(dealerName) deals"). \(declarers)"
            }
            var text = "Nobody declared, so \(dealer == Seats.human ? "you deal" : "\(dealerName) deals") this first round."
            if let kitty = kittyTrumpLine(round: round) { text += " " + kitty }
            return "\(text) \(declarers)"
        }
        var text: String
        if let reason = dealerReason(game) {
            text = "\(subject(dealer, "deal", "deals", players: players)): \(reason)."
        } else {
            text = "\(subject(dealer, "deal", "deals", players: players)) this round."
        }
        if round.declaration == nil, let kitty = kittyTrumpLine(round: round) { text += " " + kitty }
        return "\(text) \(declarers)"
    }

    /// "East picks up the kitty and buries 8 cards." / "You pick up the kitty and bury 8 cards."
    static func kittyPickupLine(dealer: Int?, kittySize: Int = Round.kittySize, players: Int = 4) -> String {
        guard let dealer else { return "The dealer picks up the kitty and buries \(kittySize) cards." }
        let bury = dealer == Seats.human ? "bury" : "buries"
        return "\(subject(dealer, "pick", "picks", players: players)) up the kitty and \(bury) \(kittySize) cards."
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
        if game.findsFriends, let reason = dealerReason(game) {
            return join([sentence(reason.prefix(1).uppercased() + reason.dropFirst()), kitty])
        }
        let partner = game.players > 4 ? "the dealer's next partner" : "the dealer's partner"
        let reason = last.result.outcome.declarersHold
            ? "Your team held the deal, so \(partner) deals."
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

    // MARK: Finding Friends

    /// "East calls 3 friends after burying: whoever plays a card East names joins East's side."
    static func friendsToCallLine(dealer: Int, count: Int, players: Int) -> String {
        let friends = count == 1 ? "a friend" : "\(count) friends"
        if dealer == Seats.human {
            return "You call \(friends) after burying: whoever plays a card you name joins your side."
        }
        let dealerName = name(dealer, players: players)
        return "\(dealerName) calls \(friends) after burying: whoever plays a card \(dealerName) names joins their side."
    }

    /// "East calls the first A♠ and the first K♥." / "You call the first A♠."
    static func friendCallLine(dealer: Int, calls: [FriendCall], players: Int) -> String? {
        friendCallLine(dealer: dealer, calls: calls, name: { name($0, players: players) })
    }

    /// The same with names from `name` ("You" for seat 0), e.g. "Mei calls the first A♠."
    static func friendCallLine(dealer: Int, calls: [FriendCall], name: (Int) -> String) -> String? {
        guard !calls.isEmpty else { return nil }
        let unfound = calls.map(\.unfound)
        let verb = dealer == Seats.human ? "call" : "calls"
        return sentence("\(name(dealer)) \(verb) \(unfound.spokenList)")
    }

    /// The friends found by the play just made, e.g. "Northeast played the first A♠ and joins your side!"
    /// or "East played the first K♥, a card East called: no friend for that call."
    static func friendsFoundLine(before: [FriendCall], after: [FriendCall], dealer: Int?, players: Int) -> String? {
        friendsFoundLine(before: before, after: after, dealer: dealer, name: { name($0, players: players) })
    }

    /// The same with names from `name` ("You" for seat 0).
    static func friendsFoundLine(before: [FriendCall], after: [FriendCall], dealer: Int?,
                                 name: (Int) -> String) -> String? {
        guard let dealer else { return nil }
        var lines: [String] = []
        for (old, new) in zip(before, after) where old.friend == nil {
            guard let friend = new.friend else { continue }
            let call = new.unfound.description
            let who = name(friend)
            if friend == dealer {
                let dealerWho = dealer == Seats.human ? "you" : name(dealer)
                lines.append("\(who) played \(call), a card \(dealerWho) called: no friend for that call.")
            } else if before.contains(where: { $0.friend == friend }) {
                lines.append("\(who) played \(call) too, but \(friend == Seats.human ? "you were" : "they were") already a friend.")
            } else if friend == Seats.human {
                let side = dealer == Seats.human ? "your" : "\(name(dealer))'s"
                lines.append("You played \(call), so you join \(side) side!")
            } else if dealer == Seats.human {
                lines.append("\(who) played \(call), so \(who) is your friend!")
            } else {
                lines.append("\(who) played \(call) and joins \(name(dealer))'s side.")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    // MARK: Playing

    static func throwFailedLine(player: Int, forced: [Card], blocker: Int, trump: Trump, players: Int = 4) -> String {
        let played = describePlay(forced, trump: trump)
        let blockerName = name(blocker, players: players)
        if player == Seats.human {
            return "Your throw failed: \(blockerName) could beat part of it, so only \(played) was played."
        }
        return "\(name(player, players: players))'s throw failed: \(blocker == Seats.human ? "you" : blockerName) could beat part of it, so only \(played) was played."
    }

    /// Concept tag for an illegal move.
    static func concept(for error: RoundError) -> String? {
        switch error {
        case let .illegalFollow(violation):
            switch violation {
            case .mustFollowSuit: return "Follow suit"
            case .mustPlayPairs: return "Follow a pair"
            case .mustPlayTractor, .mustPlaySetTractor: return "Follow a tractor"
            case .mustPlaySets: return "Follow a triple"
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
        case .mustPlayPairs, .mustPlayTractor, .mustPlaySets, .mustPlaySetTractor: return .legalFollow
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
        let players = TableSize(players: trick.plays.count).players
        var concept: String?
        var parts: [String] = []
        if full {
            let why = whyWon(trick, trump: trump)
            parts.append(why.text)
            concept = why.concept
        } else {
            parts.append("\(subject(trick.winner, "win", "wins", players: players)) the trick.")
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
        let players = TableSize(players: trick.plays.count).players
        func subject(_ seat: Int, _ youForm: String, _ otherForm: String) -> String {
            GameCoachText.subject(seat, youForm, otherForm, players: players)
        }
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
            let tiedName = tied.player == Seats.human ? "You" : name(tied.player, players: players)
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
        case .tractor, .setTractor:
            shapeWord = " tractor"
            concept = "Tractors"
        case let .set(width):
            shapeWord = width == 3 ? " triple" : " set"
            concept = "Triples"
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
    static func kittyLine(_ result: RoundResult, decks: Int = 2) -> String {
        if result.kittyMultiplier <= 0 {
            if result.kittyPoints == 0 { return "Declarers won the last trick. The kitty had no points anyway." }
            return "Declarers won the last trick, so the kitty's \(result.kittyPoints) points don't count."
        }
        let shape: String
        let size = result.kittyMultiplier / 2
        switch size {
        case 1: shape = "a single"
        case 2: shape = "a pair"
        case 3: shape = "a triple"
        case 4 where decks <= 2: shape = "a tractor"
        case 4: shape = "a 4-card tractor or set"
        default: shape = decks <= 2 ? "a long tractor" : "a \(size)-card combination"
        }
        if result.kittyPoints == 0 {
            return "Defenders won the last trick with \(shape), but the kitty had no points."
        }
        let bonus = result.kittyPoints * result.kittyMultiplier
        return "Defenders won the last trick with \(shape): kitty \(result.kittyPoints) x \(result.kittyMultiplier) = \(bonus)"
    }

    /// One takeaway sentence for the results screen.
    static func takeaway(_ summary: RoundSummary, decks: Int = 2) -> String {
        let result = summary.result
        let threshold = Scoring.takeoverThreshold(decks: decks)
        let humanTeam = Seats.team(of: Seats.human)
        let humanDeclares = result.declarerTeam == humanTeam
        if result.declarers != nil, result.dealer == Seats.human, result.kittyMultiplier == 0 {
            return result.outcome.declarersHold
                ? "Tip: call cards you don't hold, in suits where you can lead a low card, so your friends can win it and show themselves."
                : "Tip: as dealer, lead low in the suit of a card you called early: the sooner your friends show themselves, the better they can help."
        }
        if result.kittyMultiplier > 0 && result.kittyPoints > 0 {
            return humanDeclares
                ? "Tip: as declarers, keep point cards out of the kitty. If the defenders win the last trick, those points get multiplied."
                : "Tip: winning the last trick as defenders multiplies the kitty. Save a strong pair for the end."
        }
        if humanDeclares {
            if result.defenderPoints >= threshold {
                return "Tip: as declarers, draw out trumps early so the defenders can't ruff your winners."
            }
            return "Tip: nice holding! Play your sure winners before the defenders run you out of a suit."
        }
        if result.defenderPoints >= threshold {
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
