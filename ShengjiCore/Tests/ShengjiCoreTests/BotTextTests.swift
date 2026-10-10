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
