import Foundation

/// Named Shengji moves the app recognises in real play. Each one is also a teaching unit:
/// it has a short explanation and a card example so the badge doubles as a mini lesson.
public enum MoveKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Win a trick by playing trump on a plain-suit lead you are out of (毙 bì).
    case ruff
    /// Beat an opponent's ruff in the same trick with a higher trump.
    case overruff
    /// Put point cards into a trick your partner wins (送分 sòngfēn).
    case feedPartner
    /// Lead a tractor, or win a trick with one (拖拉机 tuōlājī).
    case tractor
    /// Lead a successful throw (甩牌 shuǎipái).
    case cleanThrow
    /// Win a trick by leading a combination nobody could beat (e.g. the last ace of a suit).
    case topCard
    /// Win a trick with the big joker (大王 dàwáng).
    case bigJoker
    /// As a defender, win the last trick and collect the kitty bonus (抠底 kōudǐ).
    case kittyRaid
    /// Make the winning trump declaration (亮主 liàngzhǔ).
    case declareTrump
    /// Overturn an opponent's declaration with a stronger one (反主 fǎnzhǔ).
    case overrideDeclaration
    /// As declarers, keep the defenders under 80.
    case holdDeal
    /// As declarers, hold the defenders to 0 (declarers go up 3).
    case shutout
    /// As defenders, reach 80 points and take over the deal.
    case takeOver
    /// Your team wins a single trick worth 30 or more points.
    case bigTrick

    /// e.g. "Ruff"
    public var title: String {
        switch self {
        case .ruff: return "Ruff"
        case .overruff: return "Overruff"
        case .feedPartner: return "Feed your partner"
        case .tractor: return "Tractor"
        case .cleanThrow: return "Clean throw"
        case .topCard: return "Top card"
        case .bigJoker: return "Big joker"
        case .kittyRaid: return "Kitty raid"
        case .declareTrump: return "Declare trump"
        case .overrideDeclaration: return "Override"
        case .holdDeal: return "Hold the deal"
        case .shutout: return "Shutout"
        case .takeOver: return "Take over"
        case .bigTrick: return "Big trick"
        }
    }

    /// e.g. "毙 (bì)", nil if no common term.
    public var chineseTerm: String? {
        switch self {
        case .ruff: return "毙 (bì)"
        case .overruff: return "盖毙 (gàibì)"
        case .feedPartner: return "送分 (sòngfēn)"
        case .tractor: return "拖拉机 (tuōlājī)"
        case .cleanThrow: return "甩牌 (shuǎipái)"
        case .topCard: return "大牌 (dàpái)"
        case .bigJoker: return "大王 (dàwáng)"
        case .kittyRaid: return "抠底 (kōudǐ)"
        case .declareTrump: return "亮主 (liàngzhǔ)"
        case .overrideDeclaration: return "反主 (fǎnzhǔ)"
        case .holdDeal: return nil
        case .shutout: return "大光 (dàguāng)"
        case .takeOver: return "上台 (shàngtái)"
        case .bigTrick: return nil
        }
    }

    /// One or two sentences: what the move is and when to use it (teaching text, second person).
    public var howTo: String {
        switch self {
        case .ruff:
            return "When you have no cards left in the suit that was led, play a trump. Any trump beats every plain card, so even a small trump can take a trick full of points."
        case .overruff:
            return "When an opponent trumps a suit you are also out of, play a higher trump to take the trick back. Keep a strong trump for this when points are on the table."
        case .feedPartner:
            return "When your partner is sure to win the trick, give them your 5s, 10s and Ks. Points in your team's tricks keep the score where you want it."
        case .tractor:
            return "Two or more pairs next to each other in one suit make a tractor. When you lead one, the others must answer with a tractor or pairs, so it is very hard to beat."
        case .cleanThrow:
            return "Lead several cards of one suit at once when nobody can beat any part of them, like an ace with a pair of kings. Count the high cards first, or your throw fails."
        case .topCard:
            return "Lead a card or combination nobody can beat, like an ace, early in a suit before the others run out of it. A sure winner keeps the lead for you and collects points."
        case .bigJoker:
            return "The big joker is the highest card in the game. Use it to win a trick that matters: one with points in it, or one that keeps your opponents from leading."
        case .kittyRaid:
            return "As a defender, win the last trick and the buried kitty's points count for your team, doubled. Win it with a pair and they count four times."
        case .declareTrump:
            return "While the cards are dealt, show a card of the trump rank to make its suit trump. Declare a suit you hold many cards of, and a pair beats a single."
        case .overrideDeclaration:
            return "Beat an opponent's declaration with a stronger one: a pair of trump-rank cards beats one card, and a pair of jokers beats both. Your suit, or no trump, wins instead."
        case .holdDeal:
            return "As declarers, keep the defenders under 80 points. Draw out their trumps, win the tricks that hold points, and bury your kitty safely."
        case .shutout:
            return "As declarers, give the defenders no points at all and your team climbs 3 levels. Every 5, 10 and K has to land in your team's tricks."
        case .takeOver:
            return "As defenders, capture 80 points or more and your team becomes the declarers. Feed points to each other and watch for a chance to win the last trick."
        case .bigTrick:
            return "Tricks with several point cards decide rounds. Win one worth 30 or more for your team, often by ruffing or by feeding a partner who is sure to win."
        }
    }

    /// SF Symbol name for the badge (all available on iOS 17).
    public var symbol: String {
        switch self {
        case .ruff: return "bolt.fill"
        case .overruff: return "arrow.up.forward"
        case .feedPartner: return "gift.fill"
        case .tractor: return "tram.fill"
        case .cleanThrow: return "sparkles"
        case .topCard: return "crown.fill"
        case .bigJoker: return "star.fill"
        case .kittyRaid: return "shippingbox.fill"
        case .declareTrump: return "flag.fill"
        case .overrideDeclaration: return "arrow.uturn.up"
        case .holdDeal: return "shield.fill"
        case .shutout: return "hand.raised.fill"
        case .takeOver: return "arrow.triangle.2.circlepath"
        case .bigTrick: return "hand.thumbsup.fill"
        }
    }
}

/// One recognised move, with a learner-facing toast line naming it.
public struct MoveEvent: Hashable, Codable, Sendable {
    public var kind: MoveKind
    /// Toast text, e.g. "Ruff! You trumped East's spade lead and won 15 points."
    public var detail: String
    /// Points involved (trick points, kitty bonus, ...), 0 if not applicable.
    public var points: Int

    public init(kind: MoveKind, detail: String, points: Int) {
        self.kind = kind
        self.detail = detail
        self.points = points
    }
}

/// Recognises moves from what actually happened in the round. Pure functions over engine values.
/// Only moves made by `player` (or, for team moves like holdDeal/takeOver/bigTrick/kittyRaid, by `player`'s team) count.
///
/// Exact rules (a "plain lead" is a lead of a non-trump suit; "won" means `player` won the trick):
///  - ruff: plain lead by someone else; `player`'s play is all trump and won; no opponent had ruffed
///    earlier in the trick (that case is an overruff instead, so the trick gives one event, not two).
///  - overruff: plain lead; `player`'s play is all trump and won; an opponent who played earlier in the trick
///    played all trump with the lead's shape (a real ruff that could have won, not a mixed discard).
///  - feedPartner: `player` followed (did not lead), the partner won, and `player`'s cards hold 5 or more points.
///    It counts even when following suit forced the point cards out: the points still reached your team.
///  - tractor: `player` led a tractor (alone or inside a throw), or won a trick whose lead contained a tractor
///    (a play can only win one if it has a matching tractor too).
///  - cleanThrow: `player` led several components at once and the throw stood (a failed throw is recorded as
///    only the forced component, so it does not count). Winning the trick is not required.
///  - topCard: `player` led a single, pair or tractor in a plain suit, won the trick (so nobody ruffed it), and
///    it was a sure winner: from what `player` had seen when the trick began (their hand, the earlier tricks,
///    the kitty they buried), no cards still out could make a higher single, pair or tractor of that suit.
///    A card that only won because nobody happened to beat it, such as the forced part of a failed throw
///    (it failed because someone could beat it), is not a top card.
///  - bigJoker: `player`'s play includes a big joker and won.
///  - bigTrick: `player`'s team won the trick and it held 30 or more points.
///  - kittyRaid: `player`'s team were the defenders and won the last trick (the kitty bonus applies,
///    even if the kitty held no points).
///  - holdDeal: `player`'s team were the declarers and the defenders stayed under 80. shutout (defenders 0)
///    also counts as holdDeal, so both are reported.
///  - takeOver: `player`'s team were the defenders and reached 80.
///  - declareTrump: `player` made the final, winning declaration (once dealing is over).
///  - overrideDeclaration: each declaration by `player` that replaced one made by an opponent.
/// Events come in `MoveKind.allCases` order. Detail lines speak to the human ("You ...") and name seats as
/// the human sees them. Round-end lines don't count levels: the detector can't see the game, and gains are
/// capped at the target level (the results sheet explains the levels).
public enum MoveDetector {
    /// Points a trick needs to count as a big trick.
    public static let bigTrickPoints = 30
    /// Points `player` must add to a trick their partner wins for a feed.
    public static let feedPoints = 5

    /// Moves in the completed trick `round.tricks[trickIndex]` (call right after the trick finishes; `round`
    /// supplies trump, history, roles and what `player` had seen). E.g. ruff: player's play was all trump on a
    /// plain lead and won; overruff: player won with trump after an opponent ruffed earlier in the trick;
    /// feedPartner: partner won and player's play contained points (forced or not, see the rules above);
    /// tractor: player led a tractor or won with one; cleanThrow: player led a multi-component lead that stood;
    /// topCard: player led a single, pair or tractor in a plain suit that nobody could beat, nobody ruffed, and
    /// it won; bigJoker: player won with a play containing a big joker; bigTrick: player's team won 30+ points
    /// in the trick.
    public static func moves(inTrick trickIndex: Int, of round: Round, player: Int = Seats.human) -> [MoveEvent] {
        guard round.tricks.indices.contains(trickIndex) else { return [] }
        let hand = round.hands.indices.contains(player) ? round.hands[player] : []
        // Tricks only exist once the kitty is buried, so `round.kitty` is what the dealer buried.
        let buried = round.dealer == player ? round.kitty : []
        let seen = seenBefore(trickIndex, tricks: round.tricks, current: round.currentTrick, hand: hand,
                              buried: buried, player: player)
        return trickMoves(round.tricks[trickIndex], trump: round.trump, player: player, seen: seen)
    }

    /// Moves in a completed trick of a seat view (online play): the viewer is seat 0.
    public static func moves(inTrick trickIndex: Int, of view: SeatView) -> [MoveEvent] {
        guard view.tricks.indices.contains(trickIndex) else { return [] }
        let buried = view.dealer == Seats.human ? (view.kitty ?? []) : []
        let seen = seenBefore(trickIndex, tricks: view.tricks, current: view.currentTrick, hand: view.hand,
                              buried: buried, player: Seats.human)
        return trickMoves(view.tricks[trickIndex], trump: view.trump, player: Seats.human, seen: seen)
    }

    /// Moves when the round is finished (`round.result` set): kittyRaid, holdDeal, shutout, takeOver.
    public static func moves(inFinishedRound round: Round, player: Int = Seats.human) -> [MoveEvent] {
        guard round.phase == .finished, let result = round.result else { return [] }
        return roundMoves(result, player: player)
    }

    /// Moves of a finished round in a seat view (the viewer is seat 0).
    public static func moves(inFinishedRoundOf view: SeatView) -> [MoveEvent] {
        guard view.phase == .finished, let result = view.result else { return [] }
        return roundMoves(result, player: Seats.human)
    }

    /// Declaration moves: call after the deal closes (finishDealing) with the round. declareTrump if `player`
    /// made the final winning declaration; overrideDeclaration once per time `player` overrode an opponent
    /// (from `round.declarationHistory`). Returns nothing while the round is still dealing.
    public static func moves(inDeclarationsOf round: Round, player: Int = Seats.human) -> [MoveEvent] {
        guard round.phase != .dealing else { return [] }
        return declarationMoves(round.declarationHistory, final: round.declaration, player: player)
    }

    /// Declaration moves from a seat view once bidding is over (the viewer is seat 0).
    public static func moves(inDeclarationsOf view: SeatView) -> [MoveEvent] {
        guard view.phase != .dealing && view.phase != .bidding else { return [] }
        return declarationMoves(view.declarationHistory, final: view.declaration, player: Seats.human)
    }

    // MARK: - Tricks

    /// Cards `player` knew the place of when trick `index` began: their hand at that moment (the hand now plus
    /// everything they have played since), every card of the earlier tricks, and the kitty they buried.
    static func seenBefore(_ index: Int, tricks: [TrickRecord], current: [Play], hand: [Card], buried: [Card],
                           player: Int) -> [Card] {
        var seen: [Card] = hand + buried
        for (position, trick) in tricks.enumerated() {
            for play in trick.plays where position < index || play.player == player {
                seen += play.cards
            }
        }
        for play in current where play.player == player {
            seen += play.cards
        }
        return seen
    }

    /// True if no cards outside `seen` (and the component itself) could form a component of the same shape and
    /// suit that beats `component`: a higher single, a higher pair, or a higher tractor of the same length.
    static func isSureWinner(_ component: Component, seen: [Card], trump: Trump, decks: Int = 2) -> Bool {
        var known = Set(seen.map(\.id))
        for card in component.cards { known.insert(card.id) }
        let unseen: [Card] = Deck.cards(decks: decks).filter { !known.contains($0.id) && trump.group($0) == component.group }
        return !Rules.canBeat(component, with: unseen, trump: trump)
    }

    /// Moves `player` made in `trick`. `seen` is what they had seen when the trick began (see `seenBefore`);
    /// only the top-card check uses it.
    static func trickMoves(_ trick: TrickRecord, trump: Trump, player: Int, seen: [Card] = []) -> [MoveEvent] {
        let plays = trick.plays
        guard let leadPlay = plays.first, let firstCard = leadPlay.cards.first,
              let myIndex = plays.firstIndex(where: { $0.player == player }) else { return [] }
        let mine = plays[myIndex].cards
        let lead = leadPlay.cards
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(firstCard)
        let leadComponents = Combos.decompose(lead, trump: trump)
        let iLed = myIndex == 0
        let iWon = trick.winner == player
        // Every seat plays to a trick, so its plays tell the table size.
        let players = TableSize(players: plays.count).players
        let myTeam = Seats.team(of: player)
        let teamWon = Seats.team(of: trick.winner) == myTeam
        let partnerWon = trick.winner != player && teamWon
        let myGroup = Combos.group(of: mine, trump: trump)
        let wonPoints = trick.points
        var events: [MoveEvent] = []

        // Ruff and overruff.
        if !ledGroup.isTrump, !iLed, iWon, myGroup == .trump, case let .plain(ledSuit) = ledGroup {
            let earlierRuff = plays[1..<myIndex].first { play in
                Seats.team(of: play.player) != myTeam
                    && Combos.group(of: play.cards, trump: trump) == .trump
                    && Rules.matchesStructure(play.cards, lead: lead, trump: trump)
            }
            if let ruffer = earlierRuff {
                let detail = "Overruff! \(Seats.name(ruffer.player, players: players)) trumped the \(ledSuit.singularName) lead, but your higher trump took the trick"
                    + pointsTail(wonPoints, prefix: " and ") + "."
                events.append(MoveEvent(kind: .overruff, detail: detail, points: wonPoints))
            } else {
                let detail = "Ruff! You trumped \(CoachText.possessive(leadPlay.player)) \(ledSuit.singularName) lead and "
                    + (wonPoints > 0 ? "won \(pointsText(wonPoints))." : "took the trick.")
                events.append(MoveEvent(kind: .ruff, detail: detail, points: wonPoints))
            }
        }

        // Feeding the partner.
        let fed = mine.points
        if !iLed, partnerWon, fed >= feedPoints {
            let partner = players > 4 ? Seats.name(trick.winner, players: players) : "Partner"
            let detail = "Point feed! You gave \(partner) \(pointsText(fed)) (\(trump.sorted(mine.filter { $0.points > 0 }).shortText)) in a trick they won."
            events.append(MoveEvent(kind: .feedPartner, detail: detail, points: fed))
        }

        // Tractors.
        let tractorInLead = leadComponents.first { $0.shape.isTractor }
        if let tractor = tractorInLead, iLed || iWon {
            let detail: String
            if iLed {
                let cards = trump.sorted(tractor.cards).shortText
                detail = "Tractor! You led \(cards)" + (iWon ? pointsTail(wonPoints, prefix: " and won ", bare: " and won the trick") : "") + "."
            } else {
                let myTractor = Combos.decompose(mine, trump: trump).first { $0.shape.isTractor }
                let cards = myTractor.map { trump.sorted($0.cards).shortText } ?? trump.sorted(mine).shortText
                detail = "Tractor! Your \(cards) beat \(CoachText.possessive(leadPlay.player)) tractor lead"
                    + pointsTail(wonPoints, prefix: " and won ") + "."
            }
            events.append(MoveEvent(kind: .tractor, detail: detail, points: iWon ? wonPoints : 0))
        }

        // A throw that stood.
        if iLed, leadComponents.count > 1 {
            var detail = "Clean throw! Your \(trump.sorted(lead).shortText) stood: nobody could beat any part of it."
            if iWon && wonPoints > 0 { detail += " You won \(pointsText(wonPoints))." }
            events.append(MoveEvent(kind: .cleanThrow, detail: detail, points: iWon ? wonPoints : 0))
        }

        // A sure winner led in a plain suit: it won, and from what you had seen nobody could have beaten it.
        if iLed, iWon, !ledGroup.isTrump, leadComponents.count == 1, let component = leadComponents.first,
           isSureWinner(component, seen: seen, trump: trump, decks: TableSize(players: players).decks) {
            let detail = "Top card! Nobody could beat your \(trump.sorted(lead).shortText)"
                + pointsTail(wonPoints, prefix: ", and it won ", bare: ", so you keep the lead") + "."
            events.append(MoveEvent(kind: .topCard, detail: detail, points: wonPoints))
        }

        // The big joker.
        if iWon, mine.contains(where: { $0.face == .bigJoker }) {
            let detail = "Big joker! Your BJ took the trick" + pointsTail(wonPoints, prefix: " and ") + "."
            events.append(MoveEvent(kind: .bigJoker, detail: detail, points: wonPoints))
        }

        // A trick worth 30 or more for the team.
        if teamWon, wonPoints >= bigTrickPoints {
            let who = iWon ? "You" : "Partner"
            let detail = "Big trick! \(who) won a trick worth \(wonPoints) points for your team."
            events.append(MoveEvent(kind: .bigTrick, detail: detail, points: wonPoints))
        }
        return sorted(events)
    }

    // MARK: - Round end

    static func roundMoves(_ result: RoundResult, player: Int) -> [MoveEvent] {
        let myTeam = Seats.team(of: player)
        let weDeclared = result.declarerTeam == myTeam
        let defenders = result.defenderPoints
        var events: [MoveEvent] = []

        if !weDeclared, Seats.team(of: result.lastTrickWinner) == myTeam {
            let bonus = result.kittyPoints * result.kittyMultiplier
            let detail: String
            if result.kittyPoints > 0 {
                detail = "Kitty raid! Your team won the last trick, so the kitty's \(result.kittyPoints) points counted ×\(result.kittyMultiplier): \(bonus) bonus points."
            } else {
                detail = "Kitty raid! Your team won the last trick and took the kitty, though it held no points this time."
            }
            events.append(MoveEvent(kind: .kittyRaid, detail: detail, points: bonus))
        }
        if weDeclared && result.outcome.declarersHold {
            let detail = "Deal held! The defenders scored \(defenders), under 80, so your team keeps the deal."
            events.append(MoveEvent(kind: .holdDeal, detail: detail, points: defenders))
            if defenders == 0 {
                let shutout = "Shutout! The defenders scored nothing: the biggest win a declaring team can have."
                events.append(MoveEvent(kind: .shutout, detail: shutout, points: 0))
            }
        }
        if !weDeclared && !result.outcome.declarersHold {
            let detail = "Take over! Your team scored \(defenders), so you take over the deal."
            events.append(MoveEvent(kind: .takeOver, detail: detail, points: defenders))
        }
        return sorted(events)
    }

    // MARK: - Declarations

    static func declarationMoves(_ history: [Declaration], final: Declaration?, player: Int) -> [MoveEvent] {
        var events: [MoveEvent] = []
        let myTeam = Seats.team(of: player)
        for (index, declaration) in history.enumerated() where index > 0 && declaration.player == player {
            let previous = history[index - 1]
            guard Seats.team(of: previous.player) != myTeam else { continue }
            let beaten = previous.suit.map { "\($0.symbol) declaration" } ?? "no-trump declaration"
            let shown = declaration.strength >= 2 ? "a " + shownText(declaration) : shownText(declaration)
            let detail = "Override! You beat \(CoachText.possessive(previous.player)) \(beaten) with \(shown)."
            events.append(MoveEvent(kind: .overrideDeclaration, detail: detail, points: 0))
        }
        if let final, final.player == player {
            let made: String
            if let suit = final.suit {
                made = "made \(suit.name.lowercased()) trump this round"
            } else {
                made = "made this a no-trump round"
            }
            let detail = "Trump declared! Your \(shownText(final)) \(made)."
            events.append(MoveEvent(kind: .declareTrump, detail: detail, points: 0))
        }
        return sorted(events)
    }

    // MARK: - Text helpers

    /// Events in `MoveKind.allCases` order (stable for events of the same kind).
    static func sorted(_ events: [MoveEvent]) -> [MoveEvent] {
        var out: [MoveEvent] = []
        for kind in MoveKind.allCases {
            for event in events where event.kind == kind { out.append(event) }
        }
        return out
    }

    /// "one 2♥", "pair of 2♠", "pair of big jokers"
    static func shownText(_ declaration: Declaration) -> String {
        let card = declaration.cards.first?.description ?? "trump-rank card"
        switch declaration.strength {
        case 1: return card
        case 2: return "pair of \(card)"
        case 3: return "pair of small jokers"
        case 4: return "pair of big jokers"
        default: return declaration.cards.shortText
        }
    }

    static func pointsText(_ points: Int) -> String {
        points == 1 ? "1 point" : "\(points) points"
    }

    /// " and won 15 points" when there are points, else `bare`.
    static func pointsTail(_ points: Int, prefix: String, bare: String = "") -> String {
        points > 0 ? prefix + pointsText(points) : bare
    }
}
