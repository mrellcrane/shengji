import Foundation
import XCTest
@testable import ShengjiCore

/// Whole games (levels 2 to A) between a standard team and a beginner team. The standard bots
/// must win clearly more often, from either pair of seats, and every game must end.
final class BotGameTests: XCTestCase {
    private struct Tally {
        var games = 0
        var standardWins = 0
        var rounds = 0
        var standardHolds = 0
        var standardDeals = 0
    }

    private func play(games: Int, standardTeam: Int, firstSeed: UInt64, stats: inout BotRunStats) -> Tally {
        var tally = Tally()
        let levels: [BotLevel] = (0..<4).map { $0 % 2 == standardTeam ? .standard : .beginner }
        for offset in 0..<UInt64(games) {
            var rng = SeededGenerator(seed: firstSeed + offset)
            var game = GameState()
            var rounds = 0
            while game.winner == nil && rounds < 150 {
                var round = game.makeRound(rng: &rng)
                BotHarness.play(&round, levels: levels, stats: &stats)
                guard let result = round.result else {
                    stats.problems.append("game \(offset) round \(rounds) did not finish")
                    break
                }
                if result.declarerTeam == standardTeam {
                    tally.standardDeals += 1
                    if result.outcome.declarersHold { tally.standardHolds += 1 }
                }
                game.record(result)
                rounds += 1
            }
            XCTAssertNotNil(game.winner, "game \(offset) never ended")
            tally.games += 1
            tally.rounds += rounds
            if game.winner == standardTeam { tally.standardWins += 1 }
        }
        return tally
    }

    func testStandardBeatsBeginnerFromEitherSeats() {
        var stats = BotRunStats()
        let before = BotDiagnostics.shared.fallbackCount
        let southNorth = play(games: 20, standardTeam: 0, firstSeed: 70_000, stats: &stats)
        let eastWest = play(games: 20, standardTeam: 1, firstSeed: 80_000, stats: &stats)
        XCTAssertEqual(stats.problems, [])
        XCTAssertEqual(stats.failedThrows, 0)
        XCTAssertEqual(BotDiagnostics.shared.fallbackCount, before)

        let games = southNorth.games + eastWest.games
        let wins = southNorth.standardWins + eastWest.standardWins
        XCTAssertEqual(games, 40)
        XCTAssertGreaterThan(Double(wins) / Double(games), 0.65, "standard won \(wins) of \(games)")
        // Clearly better from both pairs of seats, not just on average.
        XCTAssertGreaterThan(southNorth.standardWins, 13)
        XCTAssertGreaterThan(eastWest.standardWins, 13)
        // As declarers the standard bots usually keep the deal.
        let holds = southNorth.standardHolds + eastWest.standardHolds
        let deals = southNorth.standardDeals + eastWest.standardDeals
        XCTAssertGreaterThan(Double(holds) / Double(max(1, deals)), 0.6)
    }
}
