import Foundation
import XCTest
@testable import ShengjiCore

/// Many seeded all-bot rounds: every declaration, burial and play must be legal, no bot throw may
/// fail, every round must finish, the fallback construction must never be needed, and decisions
/// must be fast (p99 under 20 ms in a debug build).
final class BotSimulationTests: XCTestCase {
    private let standard: [BotLevel] = [.standard, .standard, .standard, .standard]

    /// Runs `count` rounds from `firstSeed`, varying trump rank and dealer (every fourth round is a
    /// first round, where declaring decides the dealer).
    private func run(_ count: Int, firstSeed: UInt64, levels: (UInt64) -> [BotLevel]) -> BotRunStats {
        var stats = BotRunStats()
        for offset in 0..<UInt64(count) {
            let seed = firstSeed + offset
            let rank = Rank.allCases[Int(seed % 13)]
            let dealer: Int? = seed % 4 == 0 ? nil : Int(seed % 4)
            let round = BotHarness.playRound(rank: rank, dealer: dealer, seed: seed &* 7919 &+ 13,
                                             levels: levels(seed), stats: &stats)
            if round.phase != .finished { stats.problems.append("round \(seed) did not finish") }
            if let result = round.result {
                // Everything is accounted for: 108 cards, 200 points.
                let all = round.playedCards + round.kitty
                if Set(all.map(\.id)).count != 108 { stats.problems.append("round \(seed) lost cards") }
                let declarerPoints = round.tricks.filter { !round.isDefender($0.winner) }.reduce(0) { $0 + $1.points }
                if result.trickPoints + declarerPoints + result.kittyPoints != Scoring.totalPoints {
                    stats.problems.append("round \(seed) points don't add up")
                }
            }
        }
        return stats
    }

    private func assertHealthy(_ stats: BotRunStats, rounds: Int, fallbacksBefore: Int,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(stats.problems, [], file: file, line: line)
        XCTAssertEqual(stats.rounds, rounds, file: file, line: line)
        XCTAssertEqual(stats.finishedRounds, rounds, "every round must finish", file: file, line: line)
        XCTAssertEqual(stats.burials, rounds, "every round needs exactly one burial", file: file, line: line)
        XCTAssertEqual(stats.failedThrows, 0, "bots only throw when the throw is guaranteed", file: file, line: line)
        XCTAssertEqual(BotDiagnostics.shared.fallbackCount, fallbacksBefore,
                       "the fallback follow construction was used", file: file, line: line)
        XCTAssertLessThan(stats.percentile(0.99), 20, "p99 decision time in ms", file: file, line: line)
    }

    func testStandardRoundsFirstHalf() {
        let before = BotDiagnostics.shared.fallbackCount
        let stats = run(300, firstSeed: 0) { _ in self.standard }
        assertHealthy(stats, rounds: 300, fallbacksBefore: before)
        // The runs must actually exercise the interesting strategies.
        XCTAssertGreaterThan(stats.throwsMade, 100)
        for concept in ["Feed points", "Sure winner", "Ruff", "Overruff", "Draw trumps", "Throw", "Duck low",
                        "Partner's void", "Lead low", "Win cheaply", "Discard low", "Follow suit"] {
            XCTAssertGreaterThan(stats.concepts[concept] ?? 0, 0, "never used: \(concept)")
        }
        XCTAssertGreaterThan(stats.declarations, 200)
    }

    func testStandardRoundsSecondHalf() {
        let before = BotDiagnostics.shared.fallbackCount
        let stats = run(300, firstSeed: 300) { _ in self.standard }
        assertHealthy(stats, rounds: 300, fallbacksBefore: before)
        XCTAssertGreaterThan(stats.decisions, 300 * 60)
    }

    func testMixedLevelRounds() {
        let before = BotDiagnostics.shared.fallbackCount
        let stats = run(200, firstSeed: 5000) { seed in
            (0..<4).map { seat in (seed >> UInt64(seat)) & 1 == 0 ? .standard : .beginner }
        }
        assertHealthy(stats, rounds: 200, fallbacksBefore: before)
        for concept in ["Win the trick", "Lead low", "Duck low", "Feed points"] {
            XCTAssertGreaterThan(stats.concepts[concept] ?? 0, 0, "never used: \(concept)")
        }
    }

    func testAllBeginnerRoundsAreLegal() {
        let before = BotDiagnostics.shared.fallbackCount
        let stats = run(40, firstSeed: 9000) { _ in [.beginner, .beginner, .beginner, .beginner] }
        assertHealthy(stats, rounds: 40, fallbacksBefore: before)
        XCTAssertEqual(stats.throwsMade, 0, "beginners never throw")
    }

    /// The same deal always produces the same declarations, burial and plays.
    func testBotsAreDeterministic() {
        for seed in UInt64(1)...UInt64(5) {
            var first = BotRunStats(), second = BotRunStats()
            let a = BotHarness.playRound(rank: .seven, dealer: seed == 1 ? nil : Int(seed % 4), seed: seed,
                                         levels: [.standard, .beginner, .standard, .standard], stats: &first)
            let b = BotHarness.playRound(rank: .seven, dealer: seed == 1 ? nil : Int(seed % 4), seed: seed,
                                         levels: [.standard, .beginner, .standard, .standard], stats: &second)
            XCTAssertEqual(a.declarationHistory, b.declarationHistory)
            XCTAssertEqual(a.tricks, b.tricks)
            XCTAssertEqual(a.kitty, b.kitty)
            XCTAssertEqual(a.result, b.result)
        }
    }
}
