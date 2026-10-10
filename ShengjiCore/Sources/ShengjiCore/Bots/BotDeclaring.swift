import Foundation

/// Declaring trump during the deal. Deterministic: the same deal always gives the same choices.
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

    /// Share of `hand` in its longest plain suit, not counting trump-rank cards or jokers.
    static func longestPlainShare(_ hand: [Card], rank: Rank) -> Double {
        guard !hand.isEmpty else { return 0 }
        var counts = [0, 0, 0, 0]
        for card in hand where card.rank != rank {
            if let suit = card.suit { counts[suit.rawValue] += 1 }
        }
        return Double(counts.max() ?? 0) / Double(hand.count)
    }

    static func choose(for bot: Bot, in round: Round) -> Declaration? {
        guard round.phase == .dealing else { return nil }
        let seat = bot.normalizedSeat
        guard round.hands.indices.contains(seat) else { return nil }
        let options = round.availableDeclarations(for: seat)
        guard !options.isEmpty else { return nil }
        if let current = round.declaration {
            if current.player == Seats.partner(of: seat) { return nil }
            if current.player == seat {
                return options.first { $0.strength == 2 && $0.suit != nil && $0.suit == current.suit }
            }
        }
        switch bot.level {
        case .beginner:
            return options.first { $0.strength >= 2 }
        case .standard:
            return standard(options: options, round: round, seat: seat, tuning: bot.tuning)
        }
    }

    /// Share of `hand` that would be trump with this suit (nil = no trump suit).
    static func strength(of hand: [Card], rank: Rank, suit: Suit?) -> Double {
        guard !hand.isEmpty else { return 0 }
        let trump = Trump(rank: rank, suit: suit)
        var count = 0
        for card in hand where trump.isTrump(card) { count += 1 }
        return Double(count) / Double(hand.count)
    }

    /// Threshold for declaring a suit after receiving `received` cards.
    static func threshold(received: Int, complete: Bool, tuning: BotTuning = BotTuning()) -> Double {
        let span = Double(Round.handSize - minimumCards)
        let progress = complete ? 1.0 : min(1.0, max(0.0, Double(received - minimumCards) / span))
        return tuning.declareEarly - (tuning.declareEarly - tuning.declareLate) * progress
    }

    private static func standard(options: [Declaration], round: Round, seat: Int,
                                 tuning: BotTuning) -> Declaration? {
        let hand = round.hands[seat]
        guard hand.count >= minimumCards else { return nil }
        let rank = round.trumpRank
        let bar = threshold(received: hand.count, complete: round.isDealingComplete, tuning: tuning)

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

        guard let current = round.declaration else {
            if let joker = noTrump, wantsNoTrump { return joker }
            if let best = bestSuit, best.share >= bar { return best.option }
            return nil
        }
        // An opponent holds the declaration: only override with a clearly better suit for us.
        let theirs = strength(of: hand, rank: rank, suit: current.suit)
        if let best = bestSuit, best.share >= max(tuning.overrideShare, theirs + 0.10) { return best.option }
        // A joker pair also blocks their suit: worth it when that suit does little for us.
        let poorForUs = theirs < bar || (wantsNoTrump && theirs < tuning.overrideShare)
        if let joker = noTrump, noTrumpShare >= noTrumpThreshold, poorForUs { return joker }
        return nil
    }
}
