import XCTest
@testable import ShengjiCore

final class ScoringTests: XCTestCase {
    let t = Trump(rank: .two, suit: .hearts)

    private func check(_ points: Int, hold: Bool, levels: Int, file: StaticString = #filePath, line: UInt = #line) {
        let outcome = Scoring.outcome(defenderPoints: points)
        XCTAssertEqual(outcome.declarersHold, hold, "points \(points)", file: file, line: line)
        XCTAssertEqual(outcome.levels, levels, "points \(points)", file: file, line: line)
        XCTAssertFalse(outcome.summary.contains("\u{2014}"), file: file, line: line)
        XCTAssertTrue(outcome.summary.hasPrefix("Defenders scored \(points)"), file: file, line: line)
    }

    func testOutcomeTableBoundaries() {
        check(0, hold: true, levels: 3)
        check(5, hold: true, levels: 2)
        check(35, hold: true, levels: 2)
        check(40, hold: true, levels: 1)
        check(75, hold: true, levels: 1)
        check(80, hold: false, levels: 0)
        check(115, hold: false, levels: 0)
        check(120, hold: false, levels: 1)
        check(155, hold: false, levels: 1)
        check(160, hold: false, levels: 2)
        check(195, hold: false, levels: 2)
        check(200, hold: false, levels: 3)
        check(235, hold: false, levels: 3)
        check(240, hold: false, levels: 4)
        check(280, hold: false, levels: 5)
        check(400, hold: false, levels: 8)
    }

    func testNegativePointsCountAsZero() {
        let outcome = Scoring.outcome(defenderPoints: -10)
        XCTAssertTrue(outcome.declarersHold)
        XCTAssertEqual(outcome.levels, 3)
    }

    func testSummaries() {
        XCTAssertEqual(Scoring.outcome(defenderPoints: 40).summary,
                       "Defenders scored 40 (under 80): the declarers keep the deal and go up 1 level.")
        XCTAssertEqual(Scoring.outcome(defenderPoints: 25).summary,
                       "Defenders scored 25 (under 40): the declarers keep the deal and go up 2 levels.")
        XCTAssertEqual(Scoring.outcome(defenderPoints: 0).summary,
                       "Defenders scored 0: the declarers keep the deal and go up 3 levels.")
        XCTAssertEqual(Scoring.outcome(defenderPoints: 85).summary,
                       "Defenders scored 85 (80 or more): they take over the deal but don't go up a level.")
        XCTAssertEqual(Scoring.outcome(defenderPoints: 130).summary,
                       "Defenders scored 130 (120 or more): they take over the deal and go up 1 level.")
        XCTAssertEqual(Scoring.outcome(defenderPoints: 210).summary,
                       "Defenders scored 210 (200 or more): they take over the deal and go up 3 levels.")
    }

    func testConstants() {
        XCTAssertEqual(Scoring.totalPoints, 200)
        XCTAssertEqual(Scoring.takeoverThreshold, 80)
        XCTAssertEqual(Scoring.stepSize, 40)
        XCTAssertEqual(Deck.double().points, Scoring.totalPoints)
    }

    func testKittyMultiplier() {
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: [c(.ace, .spades)], trump: t), 2)
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: [c(.ace, .spades), c(.ace, .spades, 1)], trump: t), 4)
        let tractor = [c(.five, .clubs), c(.five, .clubs, 1), c(.six, .clubs), c(.six, .clubs, 1)]
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: tractor, trump: t), 8)
        let long = tractor + [c(.seven, .clubs), c(.seven, .clubs, 1)]
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: long, trump: t), 12)
        // A throw counts its largest component: pair + single → ×4.
        let pairPlusSingle = [c(.king, .spades), c(.king, .spades, 1), c(.ace, .spades)]
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: pairPlusSingle, trump: t), 4)
        // Trump tractor across the rank: A♥A♥ 2♠2♠ → ×8.
        let trumpTractor = [c(.ace, .hearts), c(.ace, .hearts, 1), c(.two, .spades), c(.two, .spades, 1)]
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: trumpTractor, trump: t), 8)
        // Two singles thrown → ×2.
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: [c(.ace, .spades), c(.king, .spades)], trump: t), 2)
    }
}
