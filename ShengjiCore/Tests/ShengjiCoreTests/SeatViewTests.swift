import Foundation
import XCTest
@testable import ShengjiCore

final class SeatViewTests: XCTestCase {
    private func playedRound(seed: UInt64, tricks: Int) -> Round {
        var rng = SeededGenerator(seed: seed)
        var round = Round(trumpRank: .two, dealer: 1, rng: &rng)
        round.dealAll()
        if let d = round.availableDeclarations(for: 2).first { try? round.declare(d) }
        round.finishDealing()
        let dealer = round.dealer ?? 1
        let bury = Array(round.trump.sorted(round.hands[dealer]).prefix(Round.kittySize))
        XCTAssertNoThrow(try round.bury(bury))
        var played = 0
        while played < tricks * 4, let turn = round.turn {
            let hand = round.trump.sorted(round.hands[turn])
            let lead = round.currentLead
            var candidate: [Card]? = nil
            if lead.isEmpty {
                candidate = [hand[0]]
            } else {
                // Search a few simple candidates for a legal follow.
                let group = round.trump.group(lead[0])
                let inGroup = hand.filter { round.trump.group($0) == group }
                let others = hand.filter { round.trump.group($0) != group }
                let pool = inGroup + others
                for start in 0..<max(1, pool.count - lead.count + 1) {
                    let tryCards = Array(pool[start..<min(pool.count, start + lead.count)])
                    if tryCards.count == lead.count, round.legalityError(for: tryCards, by: turn) == nil {
                        candidate = tryCards
                        break
                    }
                }
                if candidate == nil {
                    for pair in Combos.pairs(in: inGroup, trump: round.trump) where lead.count == 2 {
                        if round.legalityError(for: pair, by: turn) == nil { candidate = pair; break }
                    }
                }
            }
            guard let cards = candidate else { break }
            _ = try? round.play(cards, by: turn)
            played += 1
        }
        return round
    }

    func testViewerZeroMatchesRound() {
        let round = playedRound(seed: 3, tricks: 2)
        let view = round.seatView(for: 0)
        XCTAssertEqual(view.hand, round.hands[0])
        XCTAssertEqual(view.handCounts, round.hands.map(\.count))
        XCTAssertEqual(view.dealer, round.dealer)
        XCTAssertEqual(view.trump, round.trump)
        XCTAssertEqual(view.tricks, round.tricks)
        XCTAssertEqual(view.currentTrick, round.currentTrick)
        XCTAssertEqual(view.turn, round.turn)
        XCTAssertEqual(view.players.map(\.name), ["You", "East", "Partner", "West"])
    }

    func testRotationPutsViewerAtSeatZero() {
        let round = playedRound(seed: 5, tricks: 3)
        for viewer in 0..<4 {
            let view = round.seatView(for: viewer)
            XCTAssertEqual(view.hand, round.hands[viewer])
            for s in 0..<4 {
                XCTAssertEqual(view.handCounts[s], round.hands[(s + viewer) % 4].count)
            }
            if let dealer = round.dealer { XCTAssertEqual(view.dealer, ((dealer - viewer) % 4 + 4) % 4) }
            for (t, trick) in round.tricks.enumerated() {
                XCTAssertEqual(view.tricks[t].winner, ((trick.winner - viewer) % 4 + 4) % 4)
                XCTAssertEqual(view.tricks[t].plays.map(\.cards), trick.plays.map(\.cards))
            }
            XCTAssertEqual(view.isDefender(0), round.isDefender(viewer))
        }
    }

    func testPrivacyNoOtherHandsAndKittyOnlyForDealer() throws {
        let round = playedRound(seed: 9, tricks: 1)
        let dealer = try XCTUnwrap(round.dealer)
        for viewer in 0..<4 {
            let view = round.seatView(for: viewer)
            let visible = Set(view.hand.map(\.id) + view.playedCards.map(\.id) + (view.kitty ?? []).map(\.id)
                + view.declarationHistory.flatMap(\.cards).map(\.id))
            for other in 0..<4 where other != viewer {
                let secret = Set(round.hands[other].map(\.id)).subtracting(view.declarationHistory.flatMap(\.cards).map(\.id))
                XCTAssertTrue(secret.isDisjoint(with: visible), "viewer \(viewer) sees seat \(other)'s cards")
            }
            if viewer == dealer {
                XCTAssertEqual(view.kitty, round.kitty)
            } else {
                XCTAssertNil(view.kitty)
            }
        }
    }

    func testJSONUsesCardIdsAndRoundTrips() throws {
        let round = playedRound(seed: 11, tricks: 2)
        let view = round.seatView(for: 1)
        let data = try JSONEncoder().encode(view)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hand = try XCTUnwrap(json["hand"] as? [Int])
        XCTAssertEqual(hand, view.hand.map(\.id))
        let decoded = try JSONDecoder().decode(SeatView.self, from: data)
        XCTAssertEqual(decoded, view)
    }

    func testCardIdRoundTripAndRange() {
        for id in 0..<270 { XCTAssertEqual(Card(id: id)?.id, id) }
        XCTAssertNil(Card(id: -1))
        XCTAssertNil(Card(id: 270))
        XCTAssertThrowsError(try JSONDecoder().decode([Card].self, from: Data("[270]".utf8)))
    }

    func testRotatedSummaryRewritesExplanation() {
        var rng = SeededGenerator(seed: 21)
        var game = GameState()
        var round = game.makeRound(rng: &rng)
        round.dealAll()
        round.finishDealing()
        let dealer = round.dealer ?? 0
        XCTAssertNoThrow(try round.bury(Array(round.hands[dealer].prefix(8))))
        var guardCount = 0
        while round.phase == .playing, let turn = round.turn, guardCount < 400 {
            guardCount += 1
            let hand = round.hands[turn]
            let lead = round.currentLead
            if lead.isEmpty {
                _ = try? round.play([hand[0]], by: turn)
                continue
            }
            var done = false
            for start in 0..<hand.count where !done {
                let cards = Array(hand[start..<min(hand.count, start + lead.count)])
                if cards.count == lead.count, (try? round.play(cards, by: turn)) != nil { done = true }
            }
            if !done { break }
        }
        guard let result = round.result else { return }
        let summary = game.record(result)
        let rotated = summary.rotated(by: 1, target: game.settings.targetRank)
        XCTAssertEqual(rotated.levelsAfter[0], summary.levelsAfter[1])
        XCTAssertEqual(rotated.nextDealer, ((summary.nextDealer - 1) % 4 + 4) % 4)
        XCTAssertFalse(rotated.explanation.isEmpty)
        XCTAssertFalse(rotated.explanation.contains("\u{2014}"))
    }
}
