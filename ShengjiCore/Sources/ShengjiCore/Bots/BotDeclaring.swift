import Foundation

/// Declaring trump: offline during the deal, online in turn-based bidding. Deterministic: the same
/// view and options always give the same choice.
///  - Never overrides the partner; always reinforces its own single with a pair when it can.
///  - Standard: strength = would-be trumps (that suit + every trump-rank card + jokers) as a share of
///    the cards received so far. Declares once at least 6 cards are in, when strength reaches a
///    threshold that eases from 0.30 to 0.25 as the deal ends. A joker pair (no trump) is used when
///    jokers and rank cards make up at least a fifth of the hand and no plain suit is long (under
///    0.30 of the hand, rank cards aside). An opponent's declaration is overridden only with a
///    clearly good suit (share at least 0.40 and 0.10 above theirs), or with a joker pair when no
///    trump suits us or their suit is poor for us.
///  - Beginner: declares only with a pair.
enum BotDeclaring {
    static let minimumCards = 6
    /// Share of jokers and rank cards for a no-trump declaration.
    static let noTrumpThreshold = 0.20
    /// A plain suit (rank cards aside) holding this share of the hand counts as long.
    static let longSuitShare = 0.30

    /// Why the bot declares or passes (`explain` turns it into hint texts).
    enum Why: Equatable, Sendable {
        /// Not dealing or bidding.
        case wrongPhase
        /// No declaration is available.
        case nothingToDeclare
        case partnerHolds
        /// The viewer holds the declaration and cannot reinforce it.
        case ownDeclaration
        case reinforce
        /// Standard: fewer than 6 cards received.
        case tooFewCards
        case beginnerPair
        case beginnerNoPair
        /// Nobody has declared: a suit strong enough, or no trump with a joker pair, or neither.
        case strongSuit
        case noTrump
        case tooWeak
        /// An opponent holds the declaration: override with a suit, block with a joker pair, or let it stand.
        case override
        case block
        case keepTheirs
    }

    struct Choice: Equatable, Sendable {
        /// One of the available declarations (player 0), or nil to pass.
        var declaration: Declaration?
        var why: Why
    }

    /// Share of `hand` in its longest plain suit, not counting trump-rank cards or jokers.
    static func longestPlainShare(_ hand: [Card], rank: Rank) -> Double {
        guard !hand.isEmpty else { return 0 }
        var counts = [0, 0, 0, 0]
        for card in hand where card.rank != rank {
            if let suit = card.suit { counts[suit.rawValue] += 1 }
        }
        let longest: Int = counts.max() ?? 0
        return Double(longest) / Double(hand.count)
    }

    /// The choice of the viewer of `view` among `available` (seats viewer-relative: the viewer is 0,
    /// the partner 2).
    static func choose(for bot: Bot, view: SeatView, available: [Declaration]) -> Choice {
        guard view.phase == .dealing || view.phase == .bidding else { return Choice(declaration: nil, why: .wrongPhase) }
        let options = canonical(available)
        // Who holds the declaration comes first, so a pass explains itself the same way with or without options.
        if let current = view.declaration {
            // Finding Friends has no partners while declaring: anyone else's declaration is fair game.
            if current.player != 0 && !view.findsFriends && Seats.team(of: current.player) == Seats.team(of: 0) {
                return Choice(declaration: nil, why: .partnerHolds)
            }
            if current.player == 0 {
                // Reinforce with more of the same card: a single becomes a pair (with three or more
                // decks, the most copies held).
                let more = options.last {
                    $0.kind == current.kind && $0.suit == current.suit && $0.cardCount > current.cardCount
                        && ($0.suit != nil || current.kind != .rankCards)
                }
                return Choice(declaration: more, why: more == nil ? .ownDeclaration : .reinforce)
            }
        }
        guard !options.isEmpty else { return Choice(declaration: nil, why: .nothingToDeclare) }
        switch bot.level {
        case .beginner:
            let pair = options.first { $0.strength >= 2 }
            return Choice(declaration: pair, why: pair == nil ? .beginnerNoPair : .beginnerPair)
        case .standard:
            return standard(options: options, view: view, tuning: bot.tuning)
        }
    }

    /// The available declarations as the viewer's (player 0), in the engine's order: weakest first,
    /// then by suit, no trump suit last (`Round.availableDeclarations` already uses this order).
    static func canonical(_ available: [Declaration]) -> [Declaration] {
        available.map { $0.withPlayer(0) }.sorted { a, b in
            if a.strength != b.strength { return a.strength < b.strength }
            let first = a.suit?.rawValue ?? 9, second = b.suit?.rawValue ?? 9
            if first != second { return first < second }
            return a.cards.map(\.id).lexicographicallyPrecedes(b.cards.map(\.id))
        }
    }

    /// Cards of `hand` that would be trump with this suit (nil = no trump suit).
    static func trumpCount(of hand: [Card], rank: Rank, suit: Suit?) -> Int {
        let trump = Trump(rank: rank, suit: suit)
        var count = 0
        for card in hand where trump.isTrump(card) { count += 1 }
        return count
    }

    /// Share of `hand` that would be trump with this suit (nil = no trump suit).
    static func strength(of hand: [Card], rank: Rank, suit: Suit?) -> Double {
        guard !hand.isEmpty else { return 0 }
        return Double(trumpCount(of: hand, rank: rank, suit: suit)) / Double(hand.count)
    }

    /// Threshold for declaring a suit after receiving `received` of `handSize` cards.
    static func threshold(received: Int, complete: Bool, handSize: Int = Round.handSize,
                          tuning: BotTuning = BotTuning()) -> Double {
        let span = Double(handSize - minimumCards)
        let progress = complete ? 1.0 : min(1.0, max(0.0, Double(received - minimumCards) / span))
        return tuning.declareEarly - (tuning.declareEarly - tuning.declareLate) * progress
    }

    /// Every card is dealt: online bidding, or offline once every hand is full (100 cards with 4 players).
    static func isDealComplete(_ view: SeatView) -> Bool {
        let table = view.table
        return view.phase == .bidding || view.handCounts.reduce(0, +) >= table.players * table.handSize
    }

    private static func standard(options: [Declaration], view: SeatView, tuning: BotTuning) -> Choice {
        let hand = view.hand
        guard hand.count >= minimumCards else { return Choice(declaration: nil, why: .tooFewCards) }
        let rank = view.trump.rank
        let bar = threshold(received: hand.count, complete: isDealComplete(view), handSize: view.table.handSize,
                            tuning: tuning)

        // Best suit option: highest share, then the stronger declaration (a pair is harder to override).
        var bestSuit: (option: Declaration, share: Double)?
        for option in options {
            guard let suit = option.suit else { continue }
            let share = strength(of: hand, rank: rank, suit: suit)
            if let current = bestSuit {
                if share < current.share { continue }
                if share == current.share && option.strength <= current.option.strength { continue }
            }
            bestSuit = (option, share)
        }
        let noTrump = options.last { $0.suit == nil }
        // Jokers and trump-rank cards are trumps whatever the suit; no trump suit suits a hand rich in
        // them with no long plain suit to make trumps of.
        let noTrumpShare = strength(of: hand, rank: rank, suit: nil)
        let wantsNoTrump = noTrumpShare >= noTrumpThreshold && longestPlainShare(hand, rank: rank) < longSuitShare

        guard let current = view.declaration else {
            if let joker = noTrump, wantsNoTrump { return Choice(declaration: joker, why: .noTrump) }
            if let best = bestSuit, best.share >= bar { return Choice(declaration: best.option, why: .strongSuit) }
            return Choice(declaration: nil, why: .tooWeak)
        }
        // An opponent holds the declaration: only override with a clearly better suit for us.
        let theirs = strength(of: hand, rank: rank, suit: current.suit)
        if let best = bestSuit, best.share >= max(tuning.overrideShare, theirs + 0.10) {
            return Choice(declaration: best.option, why: .override)
        }
        // A joker pair also blocks their suit: worth it when that suit does little for us.
        let poorForUs = theirs < bar || (wantsNoTrump && theirs < tuning.overrideShare)
        if let joker = noTrump, noTrumpShare >= noTrumpThreshold, poorForUs {
            return Choice(declaration: joker, why: .block)
        }
        return Choice(declaration: nil, why: .keepTheirs)
    }

    // MARK: Hint texts

    /// Learner-facing texts for a choice among `available`: the declaration's cards, or no cards for a pass.
    static func explain(_ choice: Choice, view: SeatView, available: [Declaration], compassSeat: Int) -> BotDecision {
        let hand = view.hand
        let rank = view.trump.rank
        let total = hand.count
        func trumps(_ suit: Suit?) -> Int { trumpCount(of: hand, rank: rank, suit: suit) }
        let players = view.playerCount
        let seat = Seats.normalized(compassSeat, players: players)
        let holder = view.declaration.map {
            BotText.name(Seats.normalized($0.player + seat, players: players), from: seat, players: players)
        }
        let holderName = BotText.capitalized(holder ?? "someone")

        let countNudge = "Count how many of your cards would be trumps with each suit you could declare."
        let compareNudge = "Compare how many trumps you would hold with their declaration and with yours."
        let overridePrinciple = "Override an opponent's declaration only when your suit would give you clearly "
            + "more trumps than theirs."
        let holderNudge = "Look at who holds the declaration right now."
        let pairNudge = "Look for a pair of rank cards or jokers in your hand."
        let pairPrinciple = "Declare when you hold a pair: it is hard to override."

        guard let declaration = choice.declaration else {
            func pass(_ reason: String, nudge: String, principle: String, concept: String = "Pass") -> BotDecision {
                BotDecision(cards: [], reason: reason, concept: concept, nudge: nudge, principle: principle)
            }
            switch choice.why {
            case .partnerHolds:
                return pass("\(holderName) holds the declaration, so pass: their trump suit works for your side too.",
                            nudge: holderNudge,
                            principle: "Never override your partner. Their declaration already serves your side.")
            case .ownDeclaration:
                return pass("You already hold the declaration, so pass and let it stand.", nudge: holderNudge,
                            principle: "Once you hold the declaration, you can only strengthen it in the same suit.")
            case .nothingToDeclare where view.declaration == nil:
                return pass("You have no rank cards or joker pairs to declare with, so pass.",
                            nudge: "Look for rank cards and pairs of jokers in your hand.",
                            principle: "You declare by showing a rank card, a pair of them, or a pair of jokers.")
            case .nothingToDeclare:
                return pass("Nothing you hold beats the current declaration, so pass.",
                            nudge: "Look at how strong the current declaration is.",
                            principle: "To override, you need a stronger declaration: a pair beats a single, and "
                                + "jokers in pairs beat any suit.")
            case .tooWeak:
                // The suit that would give the most trumps (ties: the first in the engine's order).
                var best: Suit?
                for option in canonical(available) {
                    guard let suit = option.suit else { continue }
                    if let current = best, trumps(current) >= trumps(suit) { continue }
                    best = suit
                }
                if let best {
                    return pass("With \(BotText.plural(.plain(best))) as trumps, only \(trumps(best)) of your "
                                + "\(total) cards would be trumps. That is too few to declare, so pass.",
                                nudge: countNudge,
                                principle: "Only declare a suit that would make many of your cards trumps. "
                                    + "Otherwise let someone else choose.")
                }
                return pass("Your only declaration is a joker pair for no trump suit, and your hand doesn't suit "
                            + "it, so pass.",
                            nudge: "Count your jokers and rank cards, and look at how long your suits are.",
                            principle: "Only declare no trump suit when jokers and rank cards are many and no suit "
                                + "is long.")
            case .keepTheirs:
                let theirs = trumps(view.declaration?.suit)
                return pass("\(holderName)'s declaration gives you \(theirs) trumps, and nothing you could declare "
                            + "is clearly better, so pass.",
                            nudge: compareNudge, principle: overridePrinciple)
            case .beginnerNoPair:
                return pass("You have no pair to declare with, so pass.", nudge: pairNudge, principle: pairPrinciple)
            case .tooFewCards:
                return pass("You have seen too few cards to choose a trump suit yet, so wait.",
                            nudge: countNudge,
                            principle: "Wait until you have seen enough cards to judge which suit suits you.",
                            concept: "Wait")
            case .wrongPhase, .reinforce, .beginnerPair, .strongSuit, .noTrump, .override, .block:
                return pass("It isn't your turn to declare, so there is nothing to choose.",
                            nudge: holderNudge,
                            principle: "Declarations are made while the cards are dealt or in turn after the deal.",
                            concept: "Wait")
            }
        }

        let cards = declaration.cards
        let names = BotText.cards(cards, view.trump)
        let suitWords = declaration.suit.map { BotText.plural(.plain($0)) }
        switch choice.why {
        case .reinforce:
            return BotDecision(
                cards: cards,
                reason: declaration.cardCount == 2
                    ? "Declare \(names) to make your declaration a pair, which is harder to override."
                    : "Declare \(names) to strengthen your declaration with more of the same card, which is harder "
                        + "to override.",
                concept: "Reinforce",
                nudge: "Look at whether you hold a second copy of the card you declared with.",
                principle: "Strengthen your own single declaration to a pair when you can: it is harder to override.")
        case .beginnerPair:
            return BotDecision(
                cards: cards, reason: "Declare \(names): a pair is a strong declaration and hard to override.",
                concept: "Declare", nudge: pairNudge, principle: pairPrinciple)
        case .noTrump:
            return BotDecision(
                cards: cards,
                reason: "Declare \(names) for no trump suit: \(trumps(nil)) of your \(total) cards are jokers or "
                    + "rank cards, and none of your suits is long enough to be worth making trumps.",
                concept: "No trump",
                nudge: "Count your jokers and rank cards, and look at how long your suits are.",
                principle: "With many jokers and rank cards but no long suit, declare no trump suit with a pair of "
                    + "jokers.")
        case .override where suitWords != nil:
            let suits = suitWords ?? ""
            return BotDecision(
                cards: cards,
                reason: "\(holderName)'s declaration leaves you only \(trumps(view.declaration?.suit)) trumps. "
                    + "With \(suits) as trumps you would hold \(trumps(declaration.suit)) of your \(total) cards, "
                    + "so declare \(names) to take it over.",
                concept: "Override", nudge: compareNudge, principle: overridePrinciple)
        case .block where view.declaration?.suit == nil:
            return BotDecision(
                cards: cards,
                reason: "Your \(names) beats \(holderName)'s jokers, so declare it and take the "
                    + "declaration for your side. There is still no trump suit.",
                concept: "Override", nudge: compareNudge,
                principle: "Jokers in pairs beat any suit declaration, and big jokers beat small ones.")
        case .block:
            return BotDecision(
                cards: cards,
                reason: "\(holderName)'s declaration would leave you only \(trumps(view.declaration?.suit)) trumps, "
                    + "so declare \(names) for no trump suit and block it.",
                concept: "Block",
                nudge: "Think about how many trumps you would hold if their declaration stands.",
                principle: "Jokers in pairs beat any suit declaration. Use them when the opponents' suit would leave "
                    + "you with few trumps.")
        default:
            var reason: String
            if let suits = suitWords {
                reason = "Declare \(names): with \(suits) as trumps, \(trumps(declaration.suit)) of your \(total) "
                    + "cards would be trumps."
            } else {
                reason = "Declare \(names) for no trump suit: \(trumps(nil)) of your \(total) cards are jokers or "
                    + "rank cards."
            }
            if declaration.strength == 2 { reason += " A pair is hard to override." }
            return BotDecision(
                cards: cards, reason: reason, concept: "Declare", nudge: countNudge,
                principle: "Declare a suit that would make many of your cards trumps: its own cards, every rank card "
                    + "and the jokers.")
        }
    }
}
