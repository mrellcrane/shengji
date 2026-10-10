import Foundation
import XCTest
@testable import ShengjiCore

/// The hint texts: every decision fills all four texts; the nudge and principle never give the
/// cards away (no suit symbols, ranks or joker codes of the chosen cards, no digits); the reason
/// names at least one chosen card; the concept is a 1 to 3 word tag; never an em-dash.
final class BotTextTests: XCTestCase {
    /// Hints for South at every turn (both levels) and every burial, across many rounds.
    private func collectDecisions() -> [BotDecision] {
        var decisions: [BotDecision] = []
        for seed in UInt64(0)..<UInt64(40) {
            var rng = SeededGenerator(seed: seed + 300)
            var round = Round(trumpRank: Rank.allCases[Int(seed % 13)], dealer: seed % 5 == 0 ? nil : Int(seed % 4),
                              rng: &rng)
            let levels: [BotLevel] = seed % 3 == 0 ? [.beginner, .standard, .beginner, .standard]
                : [.standard, .standard, .standard, .standard]
            let bots = (0..<4).map { Bot(seat: $0, level: levels[$0]) }
            var stats = BotRunStats()
            BotHarness.deal(&round, bots: bots, stats: &stats)
            if let dealer = round.dealer {
                decisions.append(Bot(seat: dealer).cardsToBury(in: round))
                decisions.append(Bot(seat: dealer, level: .beginner).cardsToBury(in: round))
            }
            BotHarness.bury(&round, bots: bots, stats: &stats)
            while round.phase == .playing {
                if let seat = round.turn {
                    decisions.append(Bot(seat: seat, level: .standard).decide(in: round))
                    decisions.append(Bot(seat: seat, level: .beginner).decide(in: round))
                }
                BotHarness.step(&round, bots: bots, stats: &stats)
            }
            XCTAssertEqual(stats.problems, [])
        }
        return decisions
    }

    func testEveryDecisionExplainsItselfWithoutGivingAwayTheCards() {
        let decisions = collectDecisions()
        XCTAssertGreaterThan(decisions.count, 5000)
        var concepts = Set<String>()
        for decision in decisions {
            XCTAssertFalse(decision.cards.isEmpty)
            for text in [decision.reason, decision.concept, decision.nudge, decision.principle] {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(decision)")
                XCTAssertFalse(text.contains("\u{2014}"), "em-dash in \(text)")
                XCTAssertFalse(text.contains("  "), "double space in \(text)")
            }
            for hint in [decision.nudge, decision.principle] {
                XCTAssertFalse(hint.contains("SJ") || hint.contains("BJ"), hint)
                XCTAssertFalse(hint.contains { "♠♥♣♦".contains($0) }, hint)
                for card in decision.cards {
                    XCTAssertFalse(hint.contains(card.description), "\(card) named in \(hint)")
                }
            }
            XCTAssertTrue(decision.cards.contains { decision.reason.contains($0.description) },
                          "reason names no chosen card: \(decision.reason)")
            let words = decision.concept.split(separator: " ").count
            XCTAssertTrue((1...3).contains(words), decision.concept)
            XCTAssertTrue(decision.reason.hasSuffix(".") || decision.reason.hasSuffix("!"), decision.reason)
            XCTAssertEqual(BotHarness.textProblems(decision), [], "\(decision)")
            concepts.insert(decision.concept)
        }
        XCTAssertGreaterThan(concepts.count, 12, "\(concepts.sorted())")
    }

    /// Who a reason promises will win the trick, if it promises anything.
    private enum Promise { case seat, side }

    private static func promise(in reason: String) -> Promise? {
        let side = ["Nobody after you can beat your partner", "either way", "You play last and your partner"]
        if side.contains(where: { reason.contains($0) }) { return .side }
        let seat = ["for sure", "Nobody can beat", "nobody can beat", "win the trick", "wins the trick",
                    "wins this trick", "is enough to win", "is enough to beat"]
        if seat.contains(where: { reason.contains($0) }) { return .seat }
        return nil
    }

    /// A reason may only promise the result of a trick ("wins this trick for sure", "nobody can beat",
    /// "nobody after you can beat your partner's...") when nothing still out can change it. A plain
    /// suit can always be trumped by someone who is out of it without having shown it, so those
    /// reasons must say "only a trump can beat it" instead. Every promise made must come true.
    func testPromisedResultsComeTrue() {
        var promises = 0, broken: [String] = []
        for seed in UInt64(0)..<UInt64(120) {
            var rng = SeededGenerator(seed: seed &* 31 &+ 5)
            var round = Round(trumpRank: Rank.allCases[Int(seed % 13)], dealer: Int(seed % 4), rng: &rng)
            let bots = (0..<4).map { Bot(seat: $0) }
            var stats = BotRunStats()
            BotHarness.deal(&round, bots: bots, stats: &stats)
            BotHarness.bury(&round, bots: bots, stats: &stats)
            var pending: [(seat: Int, reason: String)] = []
            while round.phase == .playing, let seat = round.turn {
                let decision = bots[seat].decide(in: round)
                pending.append((seat, decision.reason))
                guard (try? round.play(decision.cards, by: seat)) != nil else { return XCTFail("illegal play") }
                guard round.currentTrick.isEmpty, let trick = round.tricks.last else { continue }
                for (player, reason) in pending {
                    guard let promise = BotTextTests.promise(in: reason) else { continue }
                    promises += 1
                    let kept = promise == .seat
                        ? trick.winner == player
                        : Seats.team(of: trick.winner) == Seats.team(of: player)
                    if !kept {
                        let plays = trick.plays.map { "\($0.player):\($0.cards.shortText)" }.joined(separator: " | ")
                        broken.append("seed \(seed) seat \(player): \(reason) [\(plays), won by \(trick.winner)]")
                    }
                }
                pending = []
            }
            XCTAssertEqual(stats.problems, [])
        }
        XCTAssertEqual(broken.count, 0, broken.prefix(5).joined(separator: "\n"))
        XCTAssertGreaterThan(promises, 500)
    }

    /// Burial reasons say what the burial keeps; that must match the cards actually buried.
    func testBurialReasonsOnlyClaimWhatTheyKeep() {
        var checked = 0, claims = 0
        for seed in UInt64(0)..<UInt64(400) {
            var rng = SeededGenerator(seed: seed &* 17 &+ 3)
            var round = Round(trumpRank: Rank.allCases[Int(seed % 13)], dealer: Int(seed % 4), rng: &rng)
            var stats = BotRunStats()
            BotHarness.deal(&round, bots: (0..<4).map { Bot(seat: $0) }, stats: &stats)
            guard let dealer = round.dealer else { return XCTFail("no dealer") }
            for level in BotLevel.allCases {
                let decision = Bot(seat: dealer, level: level).cardsToBury(in: round)
                let problems = BotHarness.burialClaimProblems(decision, hand: round.hands[dealer], trump: round.trump)
                XCTAssertEqual(problems, [], "seed \(seed) \(level)")
                if decision.reason.contains("keep your") { claims += 1 }
                checked += 1
            }
        }
        XCTAssertEqual(checked, 800)
        XCTAssertGreaterThan(claims, 300)
    }

    func testHintLadderWalksTheDecision() throws {
        var rng = SeededGenerator(seed: 21)
        var round = Round(trumpRank: .four, dealer: 0, rng: &rng)
        var stats = BotRunStats()
        let bots = (0..<4).map { Bot(seat: $0) }
        BotHarness.deal(&round, bots: bots, stats: &stats)
        BotHarness.bury(&round, bots: bots, stats: &stats)
        let decision = Bot(seat: 0).decide(in: round)
        var ladder = HintLadder(decision: decision)
        ladder.advance()
        XCTAssertEqual(ladder.step, .nudge)
        XCTAssertEqual(ladder.text, decision.nudge)
        XCTAssertEqual(ladder.highlightedCards, [])
        ladder.advance()
        XCTAssertEqual(ladder.step, .principle)
        XCTAssertEqual(ladder.concept, decision.concept)
        ladder.advance()
        XCTAssertEqual(ladder.step, .show)
        XCTAssertEqual(ladder.text, decision.reason)
        XCTAssertEqual(ladder.highlightedCards, decision.cards)
        XCTAssertNil(round.legalityError(for: decision.cards, by: 0))
    }

    func testFixedMessagesAreFilled() {
        for decision in [BotText.waiting(), BotText.notBurying()] {
            XCTAssertTrue(decision.cards.isEmpty)
            for text in [decision.reason, decision.concept, decision.nudge, decision.principle] {
                XCTAssertFalse(text.isEmpty)
                XCTAssertFalse(text.contains("\u{2014}"))
            }
        }
    }
}
