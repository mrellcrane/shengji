import Foundation
import XCTest
@testable import ShengjiCore

/// What happened while bots played: used to assert legality, speed and behaviour.
struct BotRunStats {
    var decisions = 0
    var leads = 0
    var follows = 0
    var throwsMade = 0
    var failedThrows = 0
    var declarations = 0
    var burials = 0
    var rounds = 0
    var finishedRounds = 0
    /// Milliseconds per decision (`decide`, `cardsToBury`, `declaration`).
    var times: [Double] = []
    var concepts: [String: Int] = [:]
    var problems: [String] = []

    mutating func time<T>(_ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try body()
        let end = DispatchTime.now().uptimeNanoseconds
        times.append(Double(end - start) / 1_000_000)
        return value
    }

    func percentile(_ p: Double) -> Double {
        guard !times.isEmpty else { return 0 }
        let sorted = times.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count) * p).rounded(.up)) - 1)
        return sorted[max(0, index)]
    }
}

enum BotHarness {
    /// Deals card by card; after each card the receiving bot may declare, and when the deal is complete
    /// every seat gets one last look (as the app does).
    static func deal(_ round: inout Round, bots: [Bot], stats: inout BotRunStats) {
        while let dealt = round.dealNext() {
            declare(&round, bot: bots[dealt.player], stats: &stats)
        }
        for seat in [1, 2, 3, 0] { declare(&round, bot: bots[seat], stats: &stats) }
        round.finishDealing()
    }

    static func declare(_ round: inout Round, bot: Bot, stats: inout BotRunStats) {
        let before = round.declaration
        let choice = stats.time { bot.declaration(in: round) }
        guard let declaration = choice else { return }
        if let before = before, before.player == Seats.partner(of: bot.seat) {
            stats.problems.append("seat \(bot.seat) overrode its partner")
        }
        do {
            try round.declare(declaration)
            stats.declarations += 1
        } catch {
            stats.problems.append("illegal declaration \(declaration) by seat \(bot.seat)")
        }
    }

    static func bury(_ round: inout Round, bots: [Bot], stats: inout BotRunStats) {
        guard let dealer = round.dealer else { return stats.problems.append("no dealer") }
        let hand = round.hands[dealer]
        let decision = stats.time { bots[dealer].cardsToBury(in: round) }
        check(decision, stats: &stats, context: "bury")
        if decision.cards.count != Round.kittySize || !hand.containsAll(decision.cards) {
            stats.problems.append("bad bury \(decision.cards.shortText)")
        }
        do {
            try round.bury(decision.cards)
            stats.burials += 1
        } catch {
            stats.problems.append("bury rejected: \(error)")
            try? round.bury(Array(hand.prefix(Round.kittySize)))
        }
    }

    /// Plays one move by whoever's turn it is.
    static func step(_ round: inout Round, bots: [Bot], stats: inout BotRunStats) {
        guard let seat = round.turn else { return }
        let leading = round.currentTrick.isEmpty
        let decision = stats.time { bots[seat].decide(in: round) }
        stats.decisions += 1
        if leading { stats.leads += 1 } else { stats.follows += 1 }
        stats.concepts[decision.concept, default: 0] += 1
        check(decision, stats: &stats, context: leading ? "lead" : "follow")
        let isThrow = leading && Rules.isThrow(decision.cards, trump: round.trump)
        do {
            let outcome = try round.play(decision.cards, by: seat)
            if isThrow { stats.throwsMade += 1 }
            if case .throwFailed = outcome { stats.failedThrows += 1 }
        } catch {
            stats.problems.append("illegal play \(decision.cards.shortText) by seat \(seat): \(error)")
            // Keep the round going so one bug doesn't stall the run.
            if let fallback = legalFallback(round, seat: seat) { _ = try? round.play(fallback, by: seat) }
        }
    }

    static func legalFallback(_ round: Round, seat: Int) -> [Card]? {
        let hand = round.hands[seat]
        if round.currentTrick.isEmpty { return hand.first.map { [$0] } }
        var rng = SeededGenerator(seed: 1)
        return EngineTestSupport.legalFollow(hand: hand, lead: round.currentLead, trump: round.trump, rng: &rng)
    }

    static func playOut(_ round: inout Round, bots: [Bot], stats: inout BotRunStats) {
        var guardCount = 0
        while round.phase == .playing && guardCount < 400 {
            step(&round, bots: bots, stats: &stats)
            guardCount += 1
        }
    }

    /// A whole round: deal with declarations, bury, play to the end.
    @discardableResult
    static func playRound(rank: Rank, dealer: Int?, seed: UInt64, levels: [BotLevel],
                          stats: inout BotRunStats) -> Round {
        var rng = SeededGenerator(seed: seed)
        var round = Round(trumpRank: rank, dealer: dealer, rng: &rng)
        return play(&round, levels: levels, stats: &stats)
    }

    @discardableResult
    static func play(_ round: inout Round, levels: [BotLevel], stats: inout BotRunStats) -> Round {
        let bots = (0..<4).map { Bot(seat: $0, level: levels[$0]) }
        stats.rounds += 1
        deal(&round, bots: bots, stats: &stats)
        bury(&round, bots: bots, stats: &stats)
        playOut(&round, bots: bots, stats: &stats)
        if round.phase == .finished { stats.finishedRounds += 1 }
        return round
    }

    /// Every decision must carry all four texts, and the reason must name a chosen card.
    static func check(_ decision: BotDecision, stats: inout BotRunStats, context: String) {
        let problems = textProblems(decision)
        if !problems.isEmpty {
            stats.problems.append("\(context): \(problems.joined(separator: "; ")) in \(decision)")
        }
    }

    static let suitSymbols: [Character] = ["♠", "♥", "♣", "♦"]

    static func textProblems(_ decision: BotDecision) -> [String] {
        var problems: [String] = []
        let texts = [decision.reason, decision.concept, decision.nudge, decision.principle]
        if texts.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) { problems.append("empty text") }
        if texts.contains(where: { $0.contains("\u{2014}") }) { problems.append("em-dash") }
        let words = decision.concept.split(separator: " ").count
        if words < 1 || words > 3 { problems.append("concept has \(words) words") }
        for text in [decision.nudge, decision.principle] {
            if text.contains(where: { suitSymbols.contains($0) }) { problems.append("suit symbol in hint: \(text)") }
            if text.contains("SJ") || text.contains("BJ") { problems.append("joker code in hint: \(text)") }
            if text.contains(where: { $0.isNumber }) { problems.append("digit in hint: \(text)") }
            let tokens = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            for card in decision.cards {
                if text.contains(card.description) { problems.append("card \(card) in hint: \(text)") }
                if let label = card.rank?.label, tokens.contains(label) {
                    problems.append("rank \(label) in hint: \(text)")
                }
            }
        }
        if !decision.cards.isEmpty && !decision.cards.contains(where: { decision.reason.contains($0.description) }) {
            problems.append("reason names no chosen card")
        }
        return problems
    }
}

/// Small builders for scenario tests.
enum BotScenario {
    /// A round dealt from a deck arranged so `hands[seat]` (up to 25 cards each) go to each seat and
    /// `kitty` (up to 8) forms the kitty; the rest is filled randomly from `seed`.
    static func round(rank: Rank, dealer: Int, hands: [[Card]], kitty: [Card] = [], seed: UInt64 = 3) -> Round {
        let deck = EngineTestSupport.deck(hands: hands, kitty: kitty, firstSeat: dealer, seed: seed)
        return Round(trumpRank: rank, dealer: dealer, deck: deck)
    }

    /// Deals everything, declares `declaration` (if any), finishes dealing and buries `bury`
    /// (or the dealer's 8 kitty cards when nil).
    static func start(_ round: inout Round, declare declaration: Declaration?, bury: [Card]? = nil) throws {
        round.dealAll()
        if let declaration = declaration { try round.declare(declaration) }
        round.finishDealing()
        guard round.dealer != nil else { return }
        try round.bury(bury ?? round.kitty)
    }
}
