import Foundation
import XCTest
@testable import ShengjiCore

final class GameTests: XCTestCase {
    /// A finished-round result where the defenders scored `points` (kitty bonus optional).
    private func result(dealer: Int, points: Int, rank: Rank = .two, kittyPoints: Int = 0,
                        multiplier: Int = 0) -> RoundResult {
        let defenderPoints = points + kittyPoints * multiplier
        return RoundResult(dealer: dealer, declarerTeam: dealer % 2, trump: Trump(rank: rank, suit: .spades),
                           trickPoints: points, kittyPoints: kittyPoints, kittyMultiplier: multiplier,
                           defenderPoints: defenderPoints, outcome: Scoring.outcome(defenderPoints: defenderPoints),
                           kitty: [], lastTrickWinner: dealer)
    }

    func testInitialState() {
        let game = GameState()
        XCTAssertEqual(game.settings, GameSettings(startRank: .two, targetRank: .ace))
        XCTAssertEqual(game.levels, [.two, .two])
        XCTAssertNil(game.nextDealer)
        XCTAssertEqual(game.roundsPlayed, 0)
        XCTAssertNil(game.winner)
        XCTAssertEqual(game.history, [])
        XCTAssertEqual(game.nextTrumpRank, .two)

        let custom = GameState(settings: GameSettings(startRank: .ten, targetRank: .king))
        XCTAssertEqual(custom.levels, [.ten, .ten])
        XCTAssertEqual(custom.nextTrumpRank, .ten)
    }

    func testFirstRoundHasNoDealerYet() {
        var rng = SeededGenerator(seed: 1)
        let round = GameState().makeRound(rng: &rng)
        XCTAssertNil(round.dealer)
        XCTAssertEqual(round.trumpRank, .two)
        XCTAssertEqual(round.phase, .dealing)
        XCTAssertEqual(round.undealt.count, 100)
    }

    func testDeclarersHoldGoUpAndPartnerDeals() {
        var game = GameState()
        let summary = game.record(result(dealer: 1, points: 30))
        XCTAssertEqual(game.levels, [.two, .four])
        XCTAssertEqual(game.nextDealer, 3)
        XCTAssertEqual(game.nextTrumpRank, .four)
        XCTAssertEqual(summary.advancingTeam, 1)
        XCTAssertEqual(summary.levelsGained, 2)
        XCTAssertEqual(summary.levelsBefore, [.two, .two])
        XCTAssertEqual(summary.levelsAfter, [.two, .four])
        XCTAssertEqual(summary.nextDealer, 3)
        XCTAssertNil(summary.gameWinner)
        XCTAssertEqual(summary.explanation,
                       "The defenders scored 30 points, short of 80, so the declarers keep the deal. "
                       + "East and West go up 2 levels, to 4. West deals next at level 4.")
        var rng = SeededGenerator(seed: 2)
        let next = game.makeRound(rng: &rng)
        XCTAssertEqual(next.dealer, 3)
        XCTAssertEqual(next.trumpRank, .four)
    }

    func testDefendersTakeOver() {
        var game = GameState()
        let summary = game.record(result(dealer: 0, points: 85))
        XCTAssertEqual(game.levels, [.two, .two])
        XCTAssertEqual(game.nextDealer, 1)
        XCTAssertNil(summary.advancingTeam)
        XCTAssertEqual(summary.levelsGained, 0)
        XCTAssertEqual(summary.explanation,
                       "The defenders scored 85 points, reaching 80, so they take over the deal. "
                       + "Nobody goes up a level this time. East deals next at level 2.")
    }

    func testYourTeamTakesOverAndYouDealNext() {
        var game = GameState()
        // West deals and East and West defend badly: your team scores 125 and takes over.
        let summary = game.record(result(dealer: 3, points: 125))
        XCTAssertEqual(game.nextDealer, 0)
        XCTAssertEqual(game.levels, [.three, .two])
        XCTAssertEqual(summary.advancingTeam, 0)
        XCTAssertEqual(summary.explanation,
                       "The defenders scored 125 points, reaching 80, so they take over the deal. "
                       + "Your team goes up 1 level, to 3. You deal next at level 3.")
        XCTAssertEqual(game.nextTrumpRank, .three)
    }

    func testTakeoverLevelsByPoints() {
        let cases: [(points: Int, gained: Int)] = [(115, 0), (120, 1), (175, 2), (205, 3), (245, 4)]
        for (points, gained) in cases {
            var game = GameState()
            let summary = game.record(result(dealer: 2, points: points))
            XCTAssertEqual(summary.levelsGained, gained, "points \(points)")
            XCTAssertEqual(game.levels[1].rawValue, 2 + gained)
            XCTAssertEqual(game.levels[0], .two)
            XCTAssertEqual(game.nextDealer, 3)
            XCTAssertEqual(summary.advancingTeam, gained > 0 ? 1 : nil)
        }
    }

    func testHoldLevelsByPoints() {
        let cases: [(points: Int, gained: Int)] = [(0, 3), (5, 2), (35, 2), (40, 1), (75, 1)]
        for (points, gained) in cases {
            var game = GameState()
            let summary = game.record(result(dealer: 0, points: points))
            XCTAssertEqual(summary.levelsGained, gained, "points \(points)")
            XCTAssertEqual(game.levels[0].rawValue, 2 + gained)
            XCTAssertEqual(game.nextDealer, 2)
        }
        var game = GameState()
        let summary = game.record(result(dealer: 0, points: 0))
        XCTAssertEqual(summary.explanation,
                       "The defenders scored 0 points, short of 80, so the declarers keep the deal. "
                       + "Your team goes up 3 levels, to 5. Partner deals next at level 5.")
    }

    func testKittyBonusIsMentioned() {
        var game = GameState()
        let summary = game.record(result(dealer: 2, points: 60, kittyPoints: 15, multiplier: 2))
        XCTAssertEqual(summary.result.defenderPoints, 90)
        XCTAssertEqual(summary.explanation,
                       "The defenders scored 90 points (including 30 from the kitty), reaching 80, so they take over the deal. "
                       + "Nobody goes up a level this time. West deals next at level 2.")
    }

    func testLevelsAreCappedAtTarget() {
        var game = GameState(settings: GameSettings(startRank: .queen, targetRank: .ace))
        let summary = game.record(result(dealer: 0, points: 0, rank: .queen))
        XCTAssertEqual(game.levels, [.ace, .queen])
        XCTAssertEqual(summary.levelsGained, 2)
        XCTAssertNil(game.winner, "reaching A is not enough: you must then hold the deal at A")
        XCTAssertTrue(summary.explanation.contains("Your team goes up 2 levels, to A (levels stop at A)."))
        XCTAssertEqual(game.nextDealer, 2)
        XCTAssertEqual(game.nextTrumpRank, .ace)
    }

    func testHoldingAtTargetWinsTheGame() {
        var game = GameState(settings: GameSettings(startRank: .ace, targetRank: .ace))
        let summary = game.record(result(dealer: 0, points: 40, rank: .ace))
        XCTAssertEqual(game.winner, 0)
        XCTAssertEqual(summary.gameWinner, 0)
        XCTAssertEqual(game.levels, [.ace, .ace])
        XCTAssertEqual(summary.levelsGained, 0)
        XCTAssertNil(summary.advancingTeam)
        XCTAssertEqual(summary.explanation,
                       "The defenders scored 40 points, short of 80, so the declarers keep the deal. "
                       + "Your team held the deal at level A, so you win the game!")
    }

    func testTakingOverAtTargetDoesNotWin() {
        var game = GameState(settings: GameSettings(startRank: .ace, targetRank: .ace))
        let first = game.record(result(dealer: 0, points: 130, rank: .ace))
        XCTAssertNil(game.winner)
        XCTAssertNil(first.gameWinner)
        XCTAssertEqual(first.levelsGained, 0)
        XCTAssertEqual(first.explanation,
                       "The defenders scored 130 points, reaching 80, so they take over the deal. "
                       + "East and West stay at level A, the top level. East deals next at level A.")
        XCTAssertEqual(game.nextDealer, 1)
        let second = game.record(result(dealer: 1, points: 75, rank: .ace))
        XCTAssertEqual(game.winner, 1)
        XCTAssertEqual(second.gameWinner, 1)
        XCTAssertTrue(second.explanation.hasSuffix("East and West held the deal at level A, so they win the game."))
    }

    func testCustomTargetRank() {
        var game = GameState(settings: GameSettings(startRank: .nine, targetRank: .ten))
        game.record(result(dealer: 1, points: 0, rank: .nine))
        XCTAssertEqual(game.levels, [.nine, .ten])
        XCTAssertNil(game.winner)
        XCTAssertEqual(game.nextDealer, 3)
        game.record(result(dealer: 3, points: 50, rank: .ten))
        XCTAssertEqual(game.winner, 1)
    }

    func testDealerRotationOverSeveralRounds() {
        var game = GameState()
        var dealers: [Int] = []
        // Seat 2 declared in round one; then: hold, take over, take over, hold.
        let script: [(dealer: Int, points: Int)] = [(2, 50), (0, 90), (1, 100), (2, 10)]
        for step in script {
            XCTAssertTrue(game.nextDealer == nil || game.nextDealer == step.dealer)
            game.record(result(dealer: step.dealer, points: step.points, rank: game.nextTrumpRank))
            if let next = game.nextDealer { dealers.append(next) }
        }
        XCTAssertEqual(dealers, [0, 1, 2, 0])
        XCTAssertEqual(game.roundsPlayed, 4)
        XCTAssertEqual(game.history.count, 4)
        XCTAssertEqual(game.history.map(\.nextDealer), dealers)
        // Team 0 held twice (+1 then +2), team 1 never went up.
        XCTAssertEqual(game.levels, [.five, .two])
        XCTAssertEqual(game.nextTrumpRank, .five)
        for summary in game.history {
            XCTAssertFalse(summary.explanation.contains("\u{2014}"))
            let sentences = summary.explanation.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertTrue((2...3).contains(sentences.count), summary.explanation)
        }
    }

    func testCodableRoundTrip() throws {
        var game = GameState(settings: GameSettings(startRank: .three, targetRank: .king))
        game.record(result(dealer: 1, points: 20, rank: .three))
        let data = try JSONEncoder().encode(game)
        let decoded = try JSONDecoder().decode(GameState.self, from: data)
        XCTAssertEqual(decoded.levels, game.levels)
        XCTAssertEqual(decoded.nextDealer, game.nextDealer)
        XCTAssertEqual(decoded.history, game.history)
        XCTAssertEqual(decoded.settings, game.settings)
        XCTAssertEqual(decoded.roundsPlayed, 1)
    }
}
